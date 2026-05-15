defmodule Foundry.ProjectManager do
  @moduledoc """
  Coordinates project selection, cloning, dependency installation, and runtime switching.
  """

  use GenServer

  @status_idle :idle
  @status_running :running
  @status_ready :ready
  @status_failed :failed
  @recent_limit 8

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  catch
    :exit, _ -> default_status()
  end

  def active_project_root do
    GenServer.call(__MODULE__, :active_project_root)
  catch
    :exit, _ -> nil
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Foundry.PubSub, "project_manager")
  end

  def recent_projects do
    GenServer.call(__MODULE__, :recent_projects)
  catch
    :exit, _ -> []
  end

  def open_project(project_root) when is_binary(project_root) do
    GenServer.call(__MODULE__, {:open_project, project_root}, 30_000)
  end

  def clone_project(repo_url, parent_dir) when is_binary(repo_url) and is_binary(parent_dir) do
    GenServer.call(__MODULE__, {:clone_project, repo_url, parent_dir}, 30_000)
  end

  def reopen_last_project do
    GenServer.call(__MODULE__, :reopen_last_project, 30_000)
  end

  def current_project_root do
    active_project_root() || default_project_root()
  end

  def default_project_root do
    Application.get_env(
      :foundry_web,
      :default_project_root,
      Path.expand("../../reference_projects/igaming", __DIR__)
    )
  end

  def classify_folder(path) do
    normalized = path |> String.trim() |> Path.expand()
    has_mix = File.exists?(Path.join(normalized, "mix.exs"))
    has_foundry = File.dir?(Path.join(normalized, ".foundry"))

    cond do
      not File.dir?(normalized) -> {:error, :not_a_directory}
      has_mix and has_foundry -> :existing_project
      not has_mix and not has_foundry -> :empty_folder
      true -> :partial_project
    end
  end

  def new_project(folder_path, project_name) when is_binary(folder_path) and is_binary(project_name) do
    GenServer.call(__MODULE__, {:new_project, folder_path, project_name}, 120_000)
  end

  def init(_opts) do
    persisted = load_persisted_state()

    {:ok,
     %{
       active_project_root: nil,
       action_ref: nil,
       recent_projects: persisted.recent_projects,
       last_project_root: persisted.last_project_root,
       auto_reopen_attempted?: false,
       status: default_status()
     }}
  end

  def handle_call(:get_status, _from, state), do: {:reply, state.status, state}

  def handle_call(:active_project_root, _from, state),
    do: {:reply, state.active_project_root, state}

  def handle_call(:recent_projects, _from, state), do: {:reply, state.recent_projects, state}

  def handle_call(:reopen_last_project, _from, %{last_project_root: nil} = state) do
    {:reply, {:error, :no_last_project}, %{state | auto_reopen_attempted?: true}}
  end

  def handle_call(:reopen_last_project, _from, state) do
    reply_with_start({:open, state.last_project_root}, %{state | auto_reopen_attempted?: true})
  end

  def handle_call({:open_project, project_root}, _from, state) do
    reply_with_start({:open, project_root}, state)
  end

  def handle_call({:clone_project, repo_url, parent_dir}, _from, state) do
    reply_with_start({:clone, repo_url, parent_dir}, state)
  end

  def handle_call({:new_project, folder_path, project_name}, _from, state) do
    reply_with_start({:new_project, folder_path, project_name}, state)
  end

  def handle_info({:project_manager_log, action_ref, chunk}, %{action_ref: action_ref} = state) do
    new_state = update_in(state.status.logs, &append_log(&1, chunk))
    broadcast_status(new_state.status)
    {:noreply, new_state}
  end

  def handle_info(
        {:project_manager_complete, action_ref, {:ok, project_root, recent_entry}},
        %{action_ref: action_ref} = state
      ) do
    recent_projects =
      state.recent_projects
      |> prepend_recent(recent_entry)
      |> Enum.filter(&valid_recent_entry?/1)
      |> Enum.take(@recent_limit)

    persist_state(project_root, recent_projects)

    status =
      state.status
      |> Map.put(:state, @status_ready)
      |> Map.put(:step, "ready")
      |> Map.put(:message, "Project ready. Opening Foundry Studio...")
      |> Map.put(:project_root, project_root)
      |> Map.put(:last_error, nil)

    broadcast_status(status)

    {:noreply,
     %{
       state
       | action_ref: nil,
         active_project_root: project_root,
         last_project_root: project_root,
         recent_projects: recent_projects,
         status: status
     }}
  end

  def handle_info(
        {:project_manager_complete, action_ref, {:error, reason}},
        %{action_ref: action_ref} = state
      ) do
    status =
      state.status
      |> Map.put(:state, @status_failed)
      |> Map.put(:step, "failed")
      |> Map.put(:message, "Project launch failed.")
      |> Map.put(:last_error, format_error(reason))

    broadcast_status(status)

    {:noreply, %{state | action_ref: nil, status: status}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp reply_with_start(_action, %{action_ref: _ref} = state) when not is_nil(state.action_ref) do
    {:reply, {:error, :busy}, state}
  end

  defp reply_with_start(action, state) do
    action_ref = make_ref()
    status = status_for_action(action)
    server = self()

    Task.start(fn ->
      result = run_action(server, action_ref, action)
      send(server, {:project_manager_complete, action_ref, result})
    end)

    {:reply, :ok, %{state | action_ref: action_ref, status: status}}
  end

  defp run_action(server, action_ref, {:open, project_root}) do
    with {:ok, normalized_root} <- validate_project_root(project_root),
         :ok <- install_dependencies(server, action_ref, normalized_root),
         :ok <- configure_runtime(normalized_root) do
      {:ok, normalized_root, recent_entry(normalized_root, nil)}
    end
  end

  defp run_action(server, action_ref, {:clone, repo_url, parent_dir}) do
    with {:ok, normalized_parent} <- validate_parent_dir(parent_dir),
         {:ok, target_root} <- clone_repository(server, action_ref, repo_url, normalized_parent),
         :ok <- install_dependencies(server, action_ref, target_root),
         :ok <- configure_runtime(target_root) do
      {:ok, target_root, recent_entry(target_root, repo_url)}
    end
  end

  defp run_action(server, action_ref, {:new_project, folder_path, project_name}) do
    normalized_folder = folder_path |> String.trim() |> Path.expand()
    project_root = Path.join(normalized_folder, project_name)

    with {:ok, _} <- validate_parent_dir(normalized_folder),
         :ok <- run_command(server, action_ref, "mix", ["phx.new", project_name, "--umbrella"], normalized_folder),
         :ok <- run_command(server, action_ref, "mix", ["foundry.init"], project_root),
         :ok <- install_dependencies(server, action_ref, project_root),
         :ok <- configure_runtime(project_root) do
      {:ok, project_root, recent_entry(project_root, nil)}
    end
  end

  defp validate_project_root(project_root) do
    normalized_root = project_root |> String.trim() |> Path.expand()

    cond do
      normalized_root == "" ->
        {:error, "Project path is required."}

      not File.dir?(normalized_root) ->
        {:error, "Project directory does not exist: #{normalized_root}"}

      not File.exists?(Path.join(normalized_root, "mix.exs")) ->
        {:error, "Expected a Mix project at #{normalized_root}"}

      true ->
        {:ok, normalized_root}
    end
  end

  defp validate_parent_dir(parent_dir) do
    normalized_parent = parent_dir |> String.trim() |> Path.expand()

    cond do
      normalized_parent == "" ->
        {:error, "Destination folder is required."}

      not File.dir?(normalized_parent) ->
        {:error, "Destination folder does not exist: #{normalized_parent}"}

      true ->
        {:ok, normalized_parent}
    end
  end

  defp clone_repository(server, action_ref, repo_url, parent_dir) do
    repo_name = derive_repo_name(repo_url)
    target_root = Path.join(parent_dir, repo_name)

    if File.exists?(target_root) do
      {:error, "Clone target already exists: #{target_root}"}
    else
      emit_log(server, action_ref, "$ git clone #{repo_url} #{target_root}\n")

      with :ok <- run_command(server, action_ref, "git", ["clone", repo_url, target_root], nil),
           {:ok, normalized_root} <- validate_project_root(target_root) do
        {:ok, normalized_root}
      end
    end
  end

  defp install_dependencies(server, action_ref, project_root) do
    emit_log(server, action_ref, "$ mix deps.get\n")
    run_command(server, action_ref, "mix", ["deps.get"], project_root)
  end

  defp configure_runtime(project_root) do
    Foundry.Studio.configure_runtime(project_root)
  end

  defp run_command(server, action_ref, executable, args, cd) do
    resolved = System.find_executable(executable)

    if is_nil(resolved) do
      {:error, "#{executable} is not installed or not on PATH."}
    else
      port =
        Port.open(
          {:spawn_executable, resolved},
          [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            :use_stdio,
            :hide,
            args: args
          ] ++ port_cd_option(cd)
        )

      collect_command_output(server, action_ref, port, "")
    end
  end

  defp collect_command_output(server, action_ref, port, acc) do
    receive do
      {^port, {:data, chunk}} ->
        emit_log(server, action_ref, chunk)
        collect_command_output(server, action_ref, port, acc <> chunk)

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        {:error, "Command failed with exit status #{status}.\n#{String.trim(acc)}"}
    after
      300_000 ->
        Port.close(port)
        {:error, "Command timed out."}
    end
  end

  defp emit_log(server, action_ref, chunk) do
    send(server, {:project_manager_log, action_ref, chunk})
  end

  defp port_cd_option(nil), do: []
  defp port_cd_option(cd), do: [cd: cd]

  defp derive_repo_name(repo_url) do
    repo_url
    |> String.trim()
    |> String.trim_trailing("/")
    |> Path.basename()
    |> String.replace_suffix(".git", "")
    |> case do
      "" -> "foundry-project"
      name -> name
    end
  end

  defp status_for_action({:open, project_root}) do
    %{
      state: @status_running,
      step: "installing_deps",
      message: "Installing project dependencies...",
      project_root: Path.expand(String.trim(project_root)),
      logs: "",
      last_error: nil
    }
  end

  defp status_for_action({:clone, repo_url, parent_dir}) do
    %{
      state: @status_running,
      step: "cloning",
      message: "Cloning repository...",
      project_root: Path.expand(Path.join(String.trim(parent_dir), derive_repo_name(repo_url))),
      logs: "",
      last_error: nil
    }
  end

  defp status_for_action({:new_project, folder_path, project_name}) do
    %{
      state: @status_running,
      step: "scaffolding",
      message: "Creating new project...",
      project_root: Path.join(Path.expand(String.trim(folder_path)), project_name),
      logs: "",
      last_error: nil
    }
  end

  defp default_status do
    %{
      state: @status_idle,
      step: nil,
      message: "Waiting for a project.",
      project_root: nil,
      logs: "",
      last_error: nil
    }
  end

  defp recent_entry(project_root, repo_url) do
    %{
      "root" => project_root,
      "label" => Path.basename(project_root),
      "repo_url" => repo_url
    }
  end

  defp prepend_recent(recent_projects, recent_entry) do
    [recent_entry | Enum.reject(recent_projects, &(&1["root"] == recent_entry["root"]))]
  end

  defp valid_recent_entry?(%{"root" => root}) when is_binary(root), do: File.dir?(root)
  defp valid_recent_entry?(_entry), do: false

  defp persisted_state_path do
    home_dir = System.get_env("FOUNDRY_HOME") || System.user_home!()
    Path.join([home_dir, ".foundry", "project_manager.json"])
  end

  defp load_persisted_state do
    path = persisted_state_path()

    with {:ok, body} <- File.read(path),
         {:ok, data} <- Jason.decode(body) do
      %{
        last_project_root: data["last_project_root"],
        recent_projects:
          (data["recent_projects"] || [])
          |> Enum.filter(&valid_recent_entry?/1)
          |> Enum.take(@recent_limit)
      }
    else
      _ -> %{last_project_root: nil, recent_projects: []}
    end
  end

  defp persist_state(last_project_root, recent_projects) do
    path = persisted_state_path()
    File.mkdir_p!(Path.dirname(path))

    payload = %{
      last_project_root: last_project_root,
      recent_projects: recent_projects
    }

    File.write!(path, Jason.encode!(payload))
  end

  defp append_log("", chunk), do: chunk
  defp append_log(existing, chunk), do: existing <> chunk

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp broadcast_status(status) do
    Phoenix.PubSub.broadcast(Foundry.PubSub, "project_manager", {:project_status, status})
  end
end

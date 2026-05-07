defmodule Foundry.PreviewServer do
  @moduledoc """
  Manages a dev server subprocess for live preview of reference projects.

  Spawns and monitors a server process (e.g., `mix phx.server`) from a manifest configuration.
  Provides start/stop events accessible via Foundry Studio UI.
  """
  use GenServer
  require Logger

  # State keys
  @state_idle :idle
  @state_starting :starting
  @state_running :running
  @state_stopping :stopping

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def get_status do
    GenServer.call(__MODULE__, :status, 5000)
  catch
    :exit, _ -> {:error, :not_started}
  end

  def start_preview(project_root) do
    GenServer.cast(__MODULE__, {:start, project_root})
  end

  def stop_preview do
    GenServer.cast(__MODULE__, :stop)
  end

  @impl true
  def init(_config) do
    {:ok,
     %{
       state: @state_idle,
       port: nil,
       project_root: nil,
       command: nil,
       env: [],
       port_num: nil,
       os_pid: nil
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      state: state.state,
      port: state.port_num,
      project_root: state.project_root,
      url:
        if(state.state == @state_running and state.port_num,
          do: "http://localhost:#{state.port_num}",
          else: nil
        )
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_cast({:start, project_root}, state) do
    case load_manifest_config(project_root) do
      {:ok, config} ->
        new_state = %{
          state
          | state: @state_starting,
            project_root: project_root,
            command: config[:command] || "mix phx.server",
            env: config[:env] || [],
            port_num: config[:port] || 4000
        }

        {:noreply, start_server_process(new_state)}

      {:error, reason} ->
        Logger.error("Failed to load manifest config: #{reason}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:stop, %{state: @state_idle} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast(:stop, state) do
    case state.port do
      nil ->
        {:noreply, %{state | state: @state_idle}}

      port ->
        # Send SIGTERM to the port
        Port.close(port)
        {:noreply, %{state | state: @state_stopping, port: nil}}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("Preview server exited with status: #{status}")

    {:noreply,
     %{
       state
       | state: @state_idle,
         port: nil,
         os_pid: nil
     }}
  end

  @impl true
  def handle_info({port, {:data, _data}}, %{port: port} = state) do
    # Ignore stdout/stderr from the port for now
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("PreviewServer ignoring message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private

  defp load_manifest_config(project_root) do
    manifest_path = Path.join(project_root, "manifest.exs")

    case File.read(manifest_path) do
      {:ok, content} ->
        try do
          config = Code.eval_string(content, []) |> elem(0)
          preview_server_config = Keyword.get(config, :preview_server, [])
          {:ok, preview_server_config}
        rescue
          e ->
            {:error, "Failed to parse manifest: #{inspect(e)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read manifest: #{reason}"}
    end
  end

  defp start_server_process(%{state: @state_starting} = state) do
    case start_port(state) do
      {:ok, port, os_pid} ->
        Logger.info(
          "Preview server started on port #{state.port_num} (PID: #{os_pid}) in #{state.project_root}"
        )

        %{state | state: @state_running, port: port, os_pid: os_pid}

      {:error, reason} ->
        Logger.error("Failed to start preview server: #{reason}")
        %{state | state: @state_idle, port: nil}
    end
  end

  defp start_port(state) do
    full_env =
      state.env
      |> Kernel.++(
        [
          {'MIX_ENV', 'dev'},
          {'PORT', '#{state.port_num}'}
        ]
      )
      |> Enum.map(fn {k, v} ->
        case k do
          k when is_binary(k) -> {String.to_charlist(k), String.to_charlist(v)}
          k when is_atom(k) -> {Atom.to_charlist(k), String.to_charlist(v)}
        end
      end)

    opts = [
      :stream,
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      cd: state.project_root,
      env: full_env
    ]

    try do
      port = Port.open({:spawn, state.command}, opts)
      # Extract OS PID from the port (implementation varies by platform)
      os_pid = extract_pid(port)
      {:ok, port, os_pid}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # Attempt to extract OS PID from port info
  defp extract_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> pid
      _ -> nil
    end
  end
end

defmodule Foundry.PreviewServer do
  @moduledoc """
  Manages a dev server subprocess for live preview of reference projects.

  Spawns and monitors a server process (e.g., `mix phx.server`) from a manifest configuration.
  Provides start/stop events accessible via Foundry Studio UI.
  """
  use GenServer
  require Logger
  @default_preview_port 4001
  @startup_check_delay_ms 250
  @startup_timeout_ms 10_000

  # State keys
  @state_idle :idle
  @state_starting :starting
  @state_running :running
  @state_stopping :stopping
  @state_failed :failed

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

  def preview_base_url(project_root) do
    case load_manifest_config(project_root) do
      {:ok, config} ->
        port = config[:port] || @default_preview_port
        "http://localhost:#{port}"

      {:error, _reason} ->
        "http://localhost:#{@default_preview_port}"
    end
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
       os_pid: nil,
       startup_started_at: nil,
       last_activity_at: nil,
       output: "",
       output_buffer: "",
       last_error: nil
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      state: state.state,
      port: state.port_num,
      project_root: state.project_root,
      url: if(state.port_num, do: "http://localhost:#{state.port_num}", else: nil),
      os_pid: state.os_pid,
      command: state.command,
      startup_started_at: state.startup_started_at,
      last_activity_at: state.last_activity_at,
      output: state.output,
      last_error: state.last_error
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
            port_num: config[:port] || @default_preview_port,
            startup_started_at: now_ms(),
            last_activity_at: now_ms(),
            output: "",
            output_buffer: "",
            last_error: nil
        }

        {:noreply, start_server_process(new_state)}

      {:error, reason} ->
        Logger.error("Failed to load manifest config: #{reason}")
        {:noreply, %{state | state: @state_failed, last_error: reason}}
    end
  end

  @impl true
  def handle_cast(:stop, %{state: @state_idle} = state) do
    {:noreply, state}
  end

  def handle_cast(:stop, %{state: @state_failed} = state) do
    {:noreply,
         %{
       state
       | state: @state_idle,
         output: "",
         output_buffer: "",
         last_error: nil,
         startup_started_at: nil,
         last_activity_at: nil
     }}
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

    {next_state, last_error} =
      cond do
        state.state == @state_stopping ->
          {@state_idle, nil}

        state.state == @state_starting and status == 0 ->
          {@state_failed, "Preview process exited before opening the HTTP port."}

        status == 0 ->
          {@state_idle, state.last_error}

        true ->
          {@state_failed, "Preview server exited with status #{status}"}
      end

    {:noreply,
     %{
         state
         | state: next_state,
           port: nil,
           os_pid: nil,
           startup_started_at: nil,
           last_activity_at: nil,
           last_error: last_error
     }}
  end

  def handle_info(:check_started, %{state: @state_starting} = state) do
    cond do
      preview_reachable?(state.port_num) ->
        {:noreply, %{state | state: @state_running, last_error: nil}}

      startup_timed_out?(state) ->
        if port_open?(state.port), do: Port.close(state.port)

        {:noreply,
         %{
           state
           | state: @state_failed,
             port: nil,
             os_pid: nil,
             startup_started_at: nil,
             last_activity_at: nil,
             last_error: "Preview server startup timed out after #{@startup_timeout_ms}ms"
         }}

      port_open?(state.port) ->
        Process.send_after(self(), :check_started, @startup_check_delay_ms)
        {:noreply, state}

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    next_state = append_output(state, data)

    case build_lock_error(data) do
      nil ->
        {:noreply, next_state}

      error ->
        if port_open?(next_state.port), do: Port.close(next_state.port)

        {:noreply,
         %{
           next_state
           | state: @state_failed,
             port: nil,
             os_pid: nil,
             startup_started_at: nil,
             last_activity_at: nil,
             last_error: error
         }}
    end
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
        Process.send_after(self(), :check_started, @startup_check_delay_ms)

        Logger.info(
          "Preview server started on port #{state.port_num} (PID: #{os_pid}) in #{state.project_root}"
        )

        %{state | port: port, os_pid: os_pid}

      {:error, reason} ->
        Logger.error("Failed to start preview server: #{reason}")
        %{
          state
          | state: @state_failed,
            port: nil,
            startup_started_at: nil,
            last_activity_at: nil,
            last_error: reason
        }
    end
  end

  defp start_port(state) do
    full_env =
      state.env
      |> Kernel.++([
        {~c"MIX_ENV", ~c"dev"},
        {~c"PORT", String.to_charlist("#{state.port_num}")}
      ])
      |> Enum.map(&normalize_env_entry/1)

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

  defp preview_reachable?(nil), do: false

  defp preview_reachable?(port_num) do
    case :gen_tcp.connect({127, 0, 0, 1}, port_num, [:binary, active: false], 100) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  end

  defp port_open?(nil), do: false
  defp port_open?(port), do: Port.info(port) != nil

  defp startup_timed_out?(%{startup_started_at: nil}), do: false

  defp startup_timed_out?(state) do
    now_ms() - (state.last_activity_at || state.startup_started_at) >= @startup_timeout_ms
  end

  defp append_output(state, data) do
    normalized = String.replace(data, "\r\n", "\n")
    combined = state.output_buffer <> normalized
    raw_output = state.output <> normalized

    {complete_lines, next_buffer} =
      if String.ends_with?(combined, "\n") do
        {String.split(combined, "\n", trim: true), ""}
      else
        case String.split(combined, "\n") do
          [] -> {[], ""}
          parts -> {Enum.drop(parts, -1), List.last(parts)}
        end
      end

    last_error =
      if Enum.any?(complete_lines, &String.contains?(String.downcase(&1), "error")) do
        List.last(complete_lines)
      else
        state.last_error
      end

    %{
      state
      | output: raw_output,
        output_buffer: next_buffer,
        last_activity_at: now_ms(),
        last_error: last_error
    }
  end

  defp build_lock_error(data) do
    if String.contains?(data, "Waiting for lock on the build directory") do
      case Regex.run(~r/held by process\s+(\d+)/, data) do
        [_, pid] ->
          "Preview build is blocked by another Mix process holding the build lock (PID #{pid})."

        _ ->
          "Preview build is blocked by another Mix process holding the build lock."
      end
    else
      nil
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp normalize_env_entry({key, value}) do
    {to_env_charlist(key), to_env_charlist(value)}
  end

  defp to_env_charlist(value) when is_list(value), do: value
  defp to_env_charlist(value) when is_binary(value), do: String.to_charlist(value)
  defp to_env_charlist(value) when is_atom(value), do: Atom.to_charlist(value)
  defp to_env_charlist(value), do: value |> to_string() |> String.to_charlist()
end

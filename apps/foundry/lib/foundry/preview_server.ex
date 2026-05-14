defmodule Foundry.PreviewServer.OutputCollector do
  @moduledoc false

  defstruct [:owner, :runner_pid]
end

defimpl Collectable, for: Foundry.PreviewServer.OutputCollector do
  def into(%Foundry.PreviewServer.OutputCollector{} = collector) do
    collector_fun = fn
      collector, {:cont, data} ->
        send(
          collector.owner,
          {:preview_output, collector.runner_pid, IO.iodata_to_binary(data)}
        )

        collector

      collector, :done ->
        collector

      _collector, :halt ->
        :ok
    end

    {collector, collector_fun}
  end
end

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
  @delay_to_sigkill_ms 1_000

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
       project_root: nil,
       command: nil,
       env: [],
       port_num: nil,
       os_pid: nil,
       startup_started_at: nil,
       last_activity_at: nil,
       output: "",
       output_buffer: "",
       last_error: nil,
       runner_pid: nil,
       runner_ref: nil,
       pending_terminal_state: nil
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
  def handle_cast({:start, _project_root}, %{state: state} = current_state)
      when state in [@state_starting, @state_running, @state_stopping] do
    {:noreply, current_state}
  end

  def handle_cast({:start, project_root}, state) do
    case load_manifest_config(project_root) do
      {:ok, config} ->
        with {:ok, command_spec} <- normalize_command(config[:command] || "mix phx.server") do
          new_state = %{
            state
            | state: @state_starting,
              project_root: project_root,
              command: command_spec.command,
              env: config[:env] || [],
              port_num: config[:port] || @default_preview_port,
              os_pid: nil,
              startup_started_at: now_ms(),
              last_activity_at: now_ms(),
              output: "",
              output_buffer: "",
              last_error: nil,
              pending_terminal_state: nil
          }

          {:noreply, start_server_process(new_state, command_spec)}
        else
          {:error, reason} ->
            Logger.error("Failed to normalize preview command: #{reason}")
            {:noreply, %{state | state: @state_failed, last_error: reason}}
        end

      {:error, reason} ->
        Logger.error("Failed to load manifest config: #{reason}")
        {:noreply, %{state | state: @state_failed, last_error: reason}}
    end
  end

  @impl true
  def handle_cast(:stop, %{state: @state_idle, runner_pid: nil} = state) do
    {:noreply, state}
  end

  def handle_cast(:stop, %{state: @state_failed, runner_pid: nil} = state) do
    {:noreply, reset_failed_state(state)}
  end

  def handle_cast(:stop, state) do
    stop_runner(state)

    {:noreply,
     %{
       state
       | state: @state_stopping,
         pending_terminal_state: @state_idle
     }}
  end

  @impl true
  def terminate(_reason, state) do
    stop_runner(state)
    :ok
  end

  @impl true
  def handle_info(:check_started, %{state: @state_starting} = state) do
    cond do
      preview_reachable?(state.port_num) ->
        {:noreply, %{state | state: @state_running, last_error: nil}}

      startup_timed_out?(state) ->
        stop_runner(state)

        {:noreply,
         %{
           state
           | state: @state_failed,
             startup_started_at: nil,
             last_activity_at: nil,
             last_error: startup_timeout_error(state),
             pending_terminal_state: @state_failed
         }}

      runner_alive?(state.runner_pid) ->
        Process.send_after(self(), :check_started, @startup_check_delay_ms)
        {:noreply, state}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:preview_output, runner_pid, data}, %{runner_pid: runner_pid} = state) do
    next_state = append_output(state, data)
    log_preview_output(data)

    case build_lock_error(data) do
      nil ->
        {:noreply, next_state}

      error ->
        stop_runner(next_state)

        {:noreply,
         %{
           next_state
           | state: @state_failed,
             startup_started_at: nil,
             last_activity_at: nil,
             last_error: error,
             pending_terminal_state: @state_failed
         }}
    end
  end

  def handle_info({:preview_output, _runner_pid, _data}, state) do
    {:noreply, state}
  end

  def handle_info({:preview_exit, runner_pid, exit_result}, %{runner_pid: runner_pid} = state) do
    Logger.info("Preview server exited with result: #{inspect(exit_result)}")
    {:noreply, finalize_runner_exit(state, exit_result)}
  end

  def handle_info({:preview_exit, _runner_pid, _exit_result}, state) do
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, ref, :process, runner_pid, reason},
        %{runner_ref: ref, runner_pid: runner_pid} = state
      ) do
    next_state =
      if state.runner_pid == nil do
        state
      else
        finalize_runner_exit(state, down_reason_to_exit_result(reason))
      end

    {:noreply, next_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("PreviewServer ignoring message: #{inspect(msg)}")
    {:noreply, state}
  end

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

  defp start_server_process(%{state: @state_starting} = state, command_spec) do
    case start_runner(self(), state, command_spec) do
      {:ok, runner_pid} ->
        runner_ref = Process.monitor(runner_pid)
        Process.send_after(self(), :check_started, @startup_check_delay_ms)

        Logger.info(
          "Preview server started on port #{state.port_num} with command #{command_spec.command} in #{state.project_root}"
        )

        %{state | runner_pid: runner_pid, runner_ref: runner_ref}

      {:error, reason} ->
        Logger.error("Failed to start preview server: #{reason}")

        %{
          state
          | state: @state_failed,
            startup_started_at: nil,
            last_activity_at: nil,
            last_error: reason
        }
    end
  end

  defp start_runner(owner, state, command_spec) do
    Task.start(fn ->
      run_preview_command(owner, state, command_spec)
    end)
  end

  defp run_preview_command(owner, state, command_spec) do
    collector = %Foundry.PreviewServer.OutputCollector{owner: owner, runner_pid: self()}

    opts = [
      cd: state.project_root,
      env: normalized_env(state),
      stderr_to_stdout: true,
      delay_to_sigkill: @delay_to_sigkill_ms,
      into: collector
    ]

    exit_result =
      try do
        case MuonTrap.cmd(command_spec.executable, command_spec.args, opts) do
          {_collector, status} -> normalize_exit_result(status)
          other -> normalize_exit_result(other)
        end
      rescue
        error -> {:error, Exception.message(error)}
      catch
        kind, reason -> {:error, Exception.format(kind, reason, __STACKTRACE__)}
      end

    send(owner, {:preview_exit, self(), exit_result})
  end

  defp normalized_env(state) do
    state.env
    |> Kernel.++([
      {"MIX_ENV", "dev"},
      {"PORT", Integer.to_string(state.port_num)}
    ])
    |> Enum.map(&normalize_env_entry/1)
  end

  defp normalize_command(command) when is_binary(command) do
    case OptionParser.split(command) do
      [] ->
        {:error, "Preview command is empty."}

      [executable | args] ->
        {:ok, %{command: command, executable: executable, args: args}}
    end
  end

  defp normalize_command(command) when is_list(command) do
    command
    |> Enum.map(&normalize_command_part/1)
    |> case do
      [] ->
        {:error, "Preview command is empty."}

      [executable | args] ->
        {:ok,
         %{
           command: Enum.join(Enum.map([executable | args], &inspect/1), " "),
           executable: executable,
           args: args
         }}
    end
  rescue
    _ ->
      {:error, "Preview command list must contain only string-like arguments."}
  end

  defp normalize_command(_command) do
    {:error, "Preview command must be a string or a list of arguments."}
  end

  defp normalize_command_part(part) when is_binary(part), do: part
  defp normalize_command_part(part) when is_atom(part), do: Atom.to_string(part)
  defp normalize_command_part(part) when is_list(part), do: List.to_string(part)
  defp normalize_command_part(part), do: to_string(part)

  defp finalize_runner_exit(state, exit_result) do
    {next_state, last_error} =
      cond do
        state.pending_terminal_state == @state_idle ->
          {@state_idle, nil}

        state.pending_terminal_state == @state_failed ->
          {@state_failed, state.last_error}

        state.state == @state_starting and exit_result == 0 ->
          {@state_failed, "Preview process exited before opening the HTTP port."}

        exit_result == 0 ->
          {@state_idle, state.last_error}

        is_integer(exit_result) ->
          {@state_failed, "Preview server exited with status #{exit_result}"}

        match?({:error, _}, exit_result) ->
          {:error, reason} = exit_result
          {@state_failed, reason}

        true ->
          {@state_failed, "Preview server exited unexpectedly"}
      end

    clear_runner_state(state, next_state, last_error)
  end

  defp clear_runner_state(state, next_state, last_error) do
    %{
      state
      | state: next_state,
        runner_pid: nil,
        runner_ref: nil,
        os_pid: nil,
        startup_started_at: nil,
        last_activity_at: nil,
        last_error: last_error,
        pending_terminal_state: nil
    }
  end

  defp reset_failed_state(state) do
    %{
      state
      | state: @state_idle,
        output: "",
        output_buffer: "",
        last_error: nil,
        startup_started_at: nil,
        last_activity_at: nil,
        pending_terminal_state: nil
    }
  end

  defp normalize_exit_result(status) when is_integer(status), do: status
  defp normalize_exit_result({:error, _reason} = error), do: error
  defp normalize_exit_result(:timeout), do: {:error, "Preview command timed out."}

  defp normalize_exit_result(other),
    do: {:error, "Preview command exited unexpectedly: #{inspect(other)}"}

  defp down_reason_to_exit_result(:normal), do: 0
  defp down_reason_to_exit_result(:shutdown), do: 0
  defp down_reason_to_exit_result({:shutdown, _}), do: 0
  defp down_reason_to_exit_result({:error, _reason} = error), do: error

  defp down_reason_to_exit_result(reason),
    do: {:error, "Preview command crashed: #{inspect(reason)}"}

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

  defp startup_timed_out?(%{startup_started_at: nil}), do: false

  defp startup_timed_out?(state) do
    now_ms() - (state.last_activity_at || state.startup_started_at) >= @startup_timeout_ms
  end

  defp runner_alive?(nil), do: false
  defp runner_alive?(pid), do: Process.alive?(pid)

  defp stop_runner(%{runner_pid: nil}), do: :ok

  defp stop_runner(%{runner_pid: runner_pid}) do
    if Process.alive?(runner_pid) do
      Process.exit(runner_pid, :shutdown)
    end

    :ok
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
      if state.state == @state_starting and
           Enum.any?(complete_lines, &String.contains?(String.downcase(&1), "error")) do
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

  defp log_preview_output(data) when is_binary(data) do
    data
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      cond do
        String.downcase(line) =~ ~r/error|exception|failed/ ->
          Logger.error("[IGAMING] #{line}")

        String.downcase(line) =~ ~r/warn/ ->
          Logger.warning("[IGAMING] #{line}")

        true ->
          Logger.debug("[IGAMING] #{line}")
      end
    end)
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

  defp startup_timeout_error(state) do
    base =
      "Preview HTTP port #{state.port_num} did not open within #{@startup_timeout_ms}ms after the last process output."

    cond do
      is_binary(state.last_error) and state.last_error != "" ->
        "#{base} Last detected error output: #{state.last_error}"

      last_output_line = last_output_line(state.output) ->
        "#{base} No explicit error was emitted. Last log line: #{last_output_line}"

      true ->
        "#{base} No process output was captured."
    end
  end

  defp last_output_line(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> List.last()
  end

  defp last_output_line(_output), do: nil

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp normalize_env_entry({key, value}) do
    {to_env_string(key), to_env_string(value)}
  end

  defp to_env_string(value) when is_binary(value), do: value
  defp to_env_string(value) when is_atom(value), do: Atom.to_string(value)
  defp to_env_string(value) when is_list(value), do: List.to_string(value)
  defp to_env_string(value), do: to_string(value)
end

defmodule Foundry.CodexProvider do
  @moduledoc """
  Spawns OpenAI Codex CLI as a subprocess and streams responses.

  Uses `codex exec --json` so the LiveView can consume structured events while
  Codex runs with the target project as its working root.
  """

  import Bitwise

  @default_timeout_ms 120_000

  @doc """
  Runs a conversation through Codex CLI.

  ## Options

    * `:system_prompt` - Foundry's system prompt
    * `:timeout_ms` - max wait time in milliseconds
    * `:model` - model override; nil uses Codex config/default
    * `:profile` - Codex profile override
    * `:project_root` - working directory for Codex
    * `:sandbox` - Codex sandbox mode, defaults to `workspace-write`
    * `:executable` - executable name/path, defaults to `codex`

  ## Returns

    `{:ok, text, metadata}` or `{:error, reason}`
  """
  def chat(messages, opts \\ []) do
    stream(messages, opts, fn _event -> :ok end)
  end

  @doc """
  Runs a conversation through Codex CLI and calls `on_event` as text arrives.

  Events are:

    * `{:delta, text}` - newly streamed assistant text
    * `{:trace, event}` - structured Codex JSON event
    * `{:result, text, metadata}` - final successful response
  """
  def stream(messages, opts \\ [], on_event) when is_function(on_event, 1) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    system_prompt = Keyword.get(opts, :system_prompt, "")
    project_root = Keyword.get(opts, :project_root, File.cwd!())
    executable = Keyword.get(opts, :executable, "codex")
    conversation_window = Keyword.get(opts, :conversation_window, :all)

    case find_executable(executable) do
      nil ->
        {:error, :not_installed}

      codex_path ->
        prompt_text = format_prompt(system_prompt, messages, conversation_window)
        codex_opts = build_codex_opts(prompt_text, opts)

        run_codex(codex_path, codex_opts, project_root, timeout_ms, on_event)
    end
  end

  defp find_executable(path) do
    if explicit_path?(path) do
      path
      |> expand_explicit_path()
      |> validate_executable_path()
    else
      System.find_executable(path) || bundled_codex_path()
    end
  end

  defp bundled_codex_path do
    path = "/Applications/Codex.app/Contents/Resources/codex"

    validate_executable_path(path)
  end

  defp explicit_path?(path) when is_binary(path) do
    Path.type(path) == :absolute or
      String.starts_with?(path, ["./", "../", "~/"])
  end

  defp expand_explicit_path("~/"), do: System.user_home!()

  defp expand_explicit_path(path) do
    if String.starts_with?(path, "~/") do
      Path.join(user_home(), String.trim_leading(path, "~/"))
    else
      Path.expand(path)
    end
  end

  defp user_home do
    System.get_env("HOME") || System.user_home!()
  end

  defp validate_executable_path(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} when (mode &&& 0o111) != 0 ->
        path

      _ ->
        nil
    end
  end

  defp format_prompt(system_prompt, messages, conversation_window) do
    conversation =
      messages
      |> take_conversation_window(conversation_window)
      |> Enum.map_join("\n\n", fn
        %{"role" => role, "content" => content} when role in ["user", "assistant"] ->
          "#{role}: #{content}"

        _other ->
          ""
      end)

    [
      "Use the following Foundry project context as authoritative guidance.",
      "",
      system_prompt,
      "",
      "Conversation:",
      conversation,
      "",
      "Prefer the supplied Foundry retrieval summary over shell discovery.",
      "",
      "Respond as the assistant to the latest user message."
    ]
    |> Enum.join("\n")
  end

  defp take_conversation_window(messages, :all), do: messages

  defp take_conversation_window(messages, window) when is_integer(window),
    do: Enum.take(messages, -window)

  defp take_conversation_window(messages, _window), do: messages

  defp build_codex_opts(prompt_text, opts) do
    base = [
      "exec",
      "--json",
      "--color",
      "never",
      "--ephemeral",
      "-c",
      "project_doc_max_bytes=0",
      "-s",
      Keyword.get(opts, :sandbox, "workspace-write")
    ]

    base =
      case Keyword.get(opts, :profile) do
        nil -> base
        "" -> base
        profile -> base ++ ["-p", profile]
      end

    base =
      case Keyword.get(opts, :model) do
        nil -> base
        "" -> base
        model -> base ++ ["-m", model]
      end

    base ++ ["-C", Keyword.fetch!(opts, :project_root), prompt_text]
  end

  defp run_codex(codex_path, codex_opts, project_root, timeout_ms, on_event) do
    args = Enum.map(codex_opts, &to_string/1)
    cmd = build_command(codex_path, args, project_root)

    IO.puts("[Codex] Command: #{String.slice(cmd, 0, 200)}")
    IO.puts("[Codex] Project root: #{project_root}")

    port =
      Port.open({:spawn, cmd}, [
        :stream,
        :exit_status,
        :binary
      ])

    result = collect_output(port, timeout_ms, on_event)

    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end

    result
  end

  defp build_command(codex_path, args, project_root) do
    args_str = Enum.map_join(args, " ", &shell_escape/1)

    inner =
      "cd #{shell_escape(project_root)} && #{shell_escape(codex_path)} #{args_str} </dev/null 2>&1"

    "sh -c #{shell_escape(inner)}"
  end

  defp shell_escape(arg) do
    escaped = String.replace(arg, "'", "'\\''")
    "'#{escaped}'"
  end

  defp collect_output(port, timeout_ms, on_event) do
    do_collect(port, [], "", [], MapSet.new(), timeout_ms, on_event)
  end

  defp do_collect(port, lines, buffer, streamed_chunks, seen_trace_lines, timeout_ms, on_event) do
    receive do
      {^port, {:data, data}} ->
        {complete_lines, next_buffer} = split_complete_lines(buffer <> data)

        {new_chunks, seen_trace_lines} =
          emit_stream_events(complete_lines, seen_trace_lines, on_event)

        do_collect(
          port,
          [data | lines],
          next_buffer,
          new_chunks ++ streamed_chunks,
          seen_trace_lines,
          timeout_ms,
          on_event
        )

      {^port, {:exit_status, 0}} ->
        parse_result(lines, buffer, streamed_chunks, seen_trace_lines, on_event)

      {^port, {:exit_status, code}} ->
        {:error, {:exit_code, code, parse_partial_result(lines, buffer)}}

      _other ->
        do_collect(port, lines, buffer, streamed_chunks, seen_trace_lines, timeout_ms, on_event)
    after
      timeout_ms ->
        case parse_result(lines, buffer, streamed_chunks, seen_trace_lines, on_event) do
          {:ok, _text, _metadata} = ok ->
            ok

          _ ->
            {:error,
             {:timeout, parse_partial_result(lines, buffer),
              parse_partial_metadata(lines, buffer)}}
        end
    end
  end

  defp split_complete_lines(data) do
    parts = String.split(data, "\n")
    {complete, [buffer]} = Enum.split(parts, -1)
    {complete, buffer}
  end

  defp emit_stream_events(lines, seen_trace_lines, on_event) do
    Enum.reduce(lines, {[], seen_trace_lines}, fn line, {chunks, seen_lines} ->
      seen_lines = emit_trace_event(line, seen_lines, on_event)

      case stream_delta(line) do
        nil ->
          {chunks, seen_lines}

        text ->
          on_event.({:delta, text})
          {[text | chunks], seen_lines}
      end
    end)
  end

  defp parse_result(lines, buffer, streamed_chunks, seen_trace_lines, on_event) do
    full_text = full_output(lines, buffer)
    emit_missing_trace_events(full_text, seen_trace_lines, on_event)

    case parse_json_events(full_text) do
      {:ok, result, metadata} ->
        on_event.({:result, result, metadata})
        {:ok, result, metadata}

      {:error, reason} ->
        {:error, reason}

      :error ->
        streamed_text = Enum.reverse(streamed_chunks) |> IO.iodata_to_binary()

        if streamed_text == "" do
          {:error, {:no_result_found, String.slice(full_text, 0, 1000)}}
        else
          metadata = %{}
          on_event.({:result, streamed_text, metadata})
          {:ok, streamed_text, metadata}
        end
    end
  end

  defp parse_partial_result(lines, buffer) do
    full_text = full_output(lines, buffer)

    case parse_json_events(full_text) do
      {:ok, result, _metadata} -> result
      {:error, reason} -> inspect(reason)
      :error -> full_text
    end
  end

  defp parse_partial_metadata(lines, buffer) do
    full_text = full_output(lines, buffer)

    case parse_json_events(full_text) do
      {:ok, _result, metadata} -> Map.put(metadata, :partial, true)
      _ -> %{partial: true}
    end
  end

  defp full_output(lines, buffer) do
    Enum.reverse([buffer | lines]) |> IO.iodata_to_binary()
  end

  defp parse_json_events(raw_output) do
    events =
      raw_output
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn line ->
        case Jason.decode(line) do
          {:ok, event} -> [event]
          _ -> []
        end
      end)

    metadata = extract_metadata(events)

    events
    |> Enum.reverse()
    |> Enum.find_value(:error, fn
      %{"type" => "item.completed", "item" => %{"type" => "agent_message", "text" => text}}
      when is_binary(text) ->
        {:ok, text, metadata}

      %{"type" => "turn.failed", "error" => error} ->
        {:error, {:turn_failed, error}}

      %{"type" => "error", "message" => message} ->
        {:error, {:codex_error, message}}

      _event ->
        nil
    end)
  end

  defp extract_metadata(events) do
    usage =
      events
      |> Enum.reverse()
      |> Enum.find_value(fn event ->
        case Map.get(event, "usage") do
          usage when is_map(usage) -> usage
          _ -> nil
        end
      end) || %{}

    %{
      usage:
        %{
          input_tokens: usage["input_tokens"] || usage["prompt_tokens"] || usage["inputTokens"],
          output_tokens:
            usage["output_tokens"] || usage["completion_tokens"] || usage["outputTokens"],
          total_tokens: usage["total_tokens"] || usage["total"] || usage["totalTokens"]
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, %{}] end)
    |> Map.new()
  end

  defp stream_delta(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "item.completed", "item" => %{"type" => "agent_message", "text" => text}}}
      when is_binary(text) ->
        text

      {:ok, %{"type" => "agent_message.delta", "delta" => text}} when is_binary(text) ->
        text

      {:ok, %{"type" => "item.delta", "delta" => %{"text" => text}}} when is_binary(text) ->
        text

      {:ok, %{"type" => "item.updated", "item" => %{"type" => "agent_message", "text" => text}}}
      when is_binary(text) ->
        text

      _ ->
        nil
    end
  end

  defp emit_trace_event(line, seen_trace_lines, on_event) do
    cond do
      MapSet.member?(seen_trace_lines, line) ->
        seen_trace_lines

      true ->
        case Jason.decode(line) do
          {:ok, event} when is_map(event) ->
            on_event.({:trace, event})
            MapSet.put(seen_trace_lines, line)

          _ ->
            seen_trace_lines
        end
    end
  end

  defp emit_missing_trace_events(full_text, seen_trace_lines, on_event) do
    full_text
    |> String.split("\n", trim: true)
    |> Enum.reduce(seen_trace_lines, fn line, seen_lines ->
      emit_trace_event(line, seen_lines, on_event)
    end)

    :ok
  end
end

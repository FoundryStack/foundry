defmodule Foundry.ClaudeCodeProvider do
  @moduledoc """
  Spawns Claude Code CLI as a subprocess and streams LLM responses.

  Claude Code acts as the inference engine with its own tools (Bash, Read, Grep, etc.).
  Foundry provides domain context via the system prompt.

  Uses `claude -p` headless mode with `--output-format stream-json` for streaming.
  No API key required — Claude Code uses browser OAuth authentication.

  See ADR-025 for the full specification.
  """

  @default_timeout_ms 120_000

  @doc """
  Runs a conversation through Claude Code CLI.

  ## Options

    * `:system_prompt` — Foundry's system prompt (AGENTS.md content, stack versions, etc.)
    * `:timeout_ms` — Max wait time in milliseconds (default: 120_000)
    * `:model` — Model override (nil = Claude Code default)
    * `:project_root` — Working directory for Claude Code's tools
    * `:mcp_config` — top-level Claude MCP server JSON used to ensure local registration
    * `:bypass_permissions` — pass `--dangerously-skip-permissions`, defaults to true

  ## Returns

    `{:ok, text, metadata}` — text response and metadata
    `{:error, reason}` — if Claude Code is not installed or fails
  """
  def chat(messages, opts \\ []) do
    stream(messages, opts, fn _event -> :ok end)
  end

  @doc """
  Runs a conversation through Claude Code CLI and calls `on_event` as text arrives.

  Events are:

    * `{:delta, text}` — newly streamed assistant text
    * `{:result, text, metadata}` — final successful response
  """
  def stream(messages, opts \\ [], on_event) when is_function(on_event, 1) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    system_prompt = Keyword.get(opts, :system_prompt, "")
    model = Keyword.get(opts, :model)
    project_root = Keyword.get(opts, :project_root, File.cwd!())

    case System.find_executable("claude") do
      nil ->
        {:error, :not_installed}

      claude_path ->
        prompt_text = format_conversation(messages)
        claude_opts = build_claude_opts(system_prompt, model, prompt_text, opts)

        with :ok <- ensure_mcp_registration(claude_path, project_root, opts) do
          run_claude(claude_path, claude_opts, project_root, timeout_ms, on_event)
        end
    end
  end

  defp format_conversation(messages) do
    messages
    |> Enum.map_join("\n\n", fn
      %{"role" => "user", "content" => content} ->
        "user: #{content}"

      %{"role" => "assistant", "content" => content} ->
        "assistant: #{content}"

      _other ->
        ""
    end)
  end

  defp build_claude_opts(system_prompt, model, prompt_text, opts) do
    bypass_permissions? = Keyword.get(opts, :bypass_permissions, true)

    base = [
      "-p",
      "--output-format",
      "stream-json",
      "--verbose",
      "--include-partial-messages",
      "--no-session-persistence"
    ]

    base =
      if bypass_permissions? do
        base ++ ["--dangerously-skip-permissions"]
      else
        base
      end

    base =
      if String.trim(system_prompt) != "" do
        base ++ ["--system-prompt", system_prompt]
      else
        base
      end

    base =
      if model do
        base ++ ["--model", model]
      else
        base
      end

    base ++ [prompt_text]
  end

  defp ensure_mcp_registration(claude_path, project_root, opts) do
    case Keyword.get(opts, :mcp_config) do
      nil ->
        :ok

      "" ->
        :ok

      mcp_config ->
        with {:ok, foundry_config} <- extract_foundry_config(mcp_config),
             false <- claude_mcp_registered?(claude_path, project_root) do
          register_foundry_mcp(claude_path, project_root, foundry_config)
        else
          true -> :ok
          {:error, _} = error -> error
        end
    end
  end

  defp extract_foundry_config(mcp_config) do
    with {:ok, decoded} <- Jason.decode(mcp_config),
         %{"foundry" => foundry_config} <- decoded do
      {:ok, Jason.encode!(foundry_config)}
    else
      _ -> {:error, :invalid_mcp_config}
    end
  end

  defp claude_mcp_registered?(claude_path, project_root) do
    case System.cmd(claude_path, ["mcp", "get", "foundry"],
           cd: project_root,
           env: [{"CLAUDECODE", ""}],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> true
      _ -> false
    end
  end

  defp register_foundry_mcp(claude_path, project_root, foundry_config) do
    case System.cmd(
           claude_path,
           ["mcp", "add-json", "-s", "local", "foundry", foundry_config],
           cd: project_root,
           env: [{"CLAUDECODE", ""}],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {output, code} ->
        {:error, {:mcp_registration_failed, code, output}}
    end
  end

  defp run_claude(claude_path, claude_opts, project_root, timeout_ms, on_event) do
    args = Enum.map(claude_opts, &to_string/1)
    cmd = build_command(claude_path, args, project_root)

    IO.puts("[ClaudeCode] Command: #{String.slice(cmd, 0, 200)}")
    IO.puts("[ClaudeCode] Project root: #{project_root}")

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

  defp build_command(claude_path, args, project_root) do
    args_str = Enum.map_join(args, " ", &shell_escape/1)

    # Claude Code's print mode expects stdin to be closed for non-interactive use.
    inner =
      "cd #{shell_escape(project_root)} && env -u CLAUDECODE #{shell_escape(claude_path)} #{args_str} </dev/null 2>&1"

    "sh -c #{shell_escape(inner)}"
  end

  defp shell_escape(arg) do
    escaped = String.replace(arg, "'", "'\\''")
    "'#{escaped}'"
  end

  defp collect_output(port, timeout_ms, on_event) do
    do_collect(port, [], "", [], timeout_ms, on_event)
  end

  defp do_collect(port, lines, buffer, streamed_chunks, timeout_ms, on_event) do
    receive do
      {^port, {:data, data}} ->
        {complete_lines, next_buffer} = split_complete_lines(buffer <> data)
        new_chunks = emit_stream_events(complete_lines, on_event)

        do_collect(
          port,
          [data | lines],
          next_buffer,
          new_chunks ++ streamed_chunks,
          timeout_ms,
          on_event
        )

      {^port, {:exit_status, 0}} ->
        parse_result(lines, buffer, streamed_chunks, on_event)

      {^port, {:exit_status, code}} ->
        {:error, {:exit_code, code, parse_partial_result(lines, buffer)}}

      _other ->
        do_collect(port, lines, buffer, streamed_chunks, timeout_ms, on_event)
    after
      timeout_ms ->
        case parse_result(lines, buffer, streamed_chunks, on_event) do
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

  defp emit_stream_events(lines, on_event) do
    Enum.flat_map(lines, fn line ->
      case stream_delta(line) do
        nil ->
          []

        text ->
          on_event.({:delta, text})
          [text]
      end
    end)
  end

  defp parse_result(lines, buffer, streamed_chunks, on_event) do
    full_text = full_output(lines, buffer)

    # Parse stream-json lines and extract the final result
    case parse_stream_json(full_text) do
      {:ok, result, metadata} ->
        on_event.({:result, result, metadata})
        {:ok, result, metadata}

      {:error, reason} ->
        {:error, {:parse_error, reason, full_text}}

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
    # Try to extract partial result from stream-json events
    case parse_stream_json(full_text) do
      {:ok, result, _} -> result
      _ -> full_text
    end
  end

  defp parse_partial_metadata(lines, buffer) do
    full_text = full_output(lines, buffer)

    case parse_stream_json(full_text) do
      {:ok, _result, metadata} -> Map.put(metadata, :partial, true)
      _ -> %{partial: true}
    end
  end

  defp full_output(lines, buffer) do
    Enum.reverse([buffer | lines]) |> IO.iodata_to_binary()
  end

  defp parse_stream_json(raw_output) do
    lines = String.split(raw_output, "\n", trim: true)

    # Find the result line (last line with type:result)
    lines
    |> Enum.reverse()
    |> Enum.find_value(:error, fn line ->
      case Jason.decode(line) do
        {:ok, %{"type" => "result", "subtype" => "success"} = event} ->
          result = Map.get(event, "result", "")
          metadata = extract_metadata(event)
          {:ok, result, metadata}

        {:ok, %{"type" => "result", "subtype" => subtype} = event} ->
          {:error, {String.to_atom(subtype), event}}

        {:ok, %{"type" => "assistant", "message" => %{"content" => content}}}
        when is_list(content) ->
          # Extract text from content parts
          text =
            content
            |> Enum.filter(fn part -> Map.get(part, "type") == "text" end)
            |> Enum.map_join("", fn part -> Map.get(part, "text", "") end)

          if text != "" do
            {:ok, text, %{}}
          else
            nil
          end

        {:ok, _} ->
          nil

        {:error, _} ->
          nil
      end
    end)
  end

  defp stream_delta(line) do
    case Jason.decode(line) do
      {:ok,
       %{
         "type" => "stream_event",
         "event" => %{
           "type" => "content_block_delta",
           "delta" => %{"type" => "text_delta", "text" => text}
         }
       }}
      when is_binary(text) ->
        text

      _ ->
        nil
    end
  end

  defp extract_metadata(event) do
    %{
      session_id: Map.get(event, "session_id"),
      duration_ms: Map.get(event, "duration_ms"),
      total_cost_usd: Map.get(event, "total_cost_usd"),
      num_turns: Map.get(event, "num_turns"),
      usage: Map.get(event, "usage")
    }
  end
end

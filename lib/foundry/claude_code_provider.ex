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

  ## Returns

    `{:ok, text, metadata}` — text response and metadata
    `{:error, reason}` — if Claude Code is not installed or fails
  """
  def chat(messages, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    system_prompt = Keyword.get(opts, :system_prompt, "")
    model = Keyword.get(opts, :model)
    project_root = Keyword.get(opts, :project_root, File.cwd!())

    case System.find_executable("claude") do
      nil ->
        {:error, :not_installed}

      claude_path ->
        prompt_text = format_conversation(messages)
        claude_opts = build_claude_opts(system_prompt, model, prompt_text)

        run_claude(claude_path, claude_opts, project_root, timeout_ms)
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

  defp build_claude_opts(system_prompt, model, prompt_text) do
    base = [
      "-p",
      prompt_text,
      "--output-format", "stream-json",
      "--verbose",
      "--include-partial-messages",
      "--no-session-persistence"
    ]

    base =
      if String.trim(system_prompt) != "" do
        base ++ ["--system-prompt", system_prompt]
      else
        base
      end

    if model do
      base ++ ["--model", model]
    else
      base
    end
  end

  defp run_claude(claude_path, claude_opts, project_root, timeout_ms) do
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

    result = collect_output(port, timeout_ms)

    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end

    result
  end

  defp build_command(claude_path, args, project_root) do
    args_str = Enum.map_join(args, " ", &shell_escape/1)

    cmd =
      case :os.type() do
        {:unix, :darwin} ->
          "script -q /dev/null #{claude_path} #{args_str}"

        {:unix, _} ->
          # Linux: script -q -c "command" /dev/null
          "script -q -c '#{claude_path} #{args_str}' /dev/null"

        _ ->
          # Windows: not supported
          "#{claude_path} #{args_str}"
      end

    # Use shell cd for working directory; redirect stderr to stdout to catch
    # Claude Code diagnostic output (it may write prompts to stderr)
    "cd #{shell_escape(project_root)} && #{cmd}"
  end

  defp shell_escape(arg) do
    # Simple shell escaping: wrap in single quotes, escape internal single quotes
    escaped = String.replace(arg, "'", "'\\''")
    "'#{escaped}'"
  end

  defp collect_output(port, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_collect(port, [], deadline)
  end

  defp do_collect(port, lines, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      partial = parse_partial_result(lines)
      {:error, {:timeout, partial}}
    else
      receive do
        {^port, {:data, data}} ->
          do_collect(port, [data | lines], deadline)

        {^port, {:exit_status, 0}} ->
          parse_result(lines)

        {^port, {:exit_status, code}} ->
          {:error, {:exit_code, code, parse_partial_result(lines)}}

        _other ->
          # Handle unexpected messages
          do_collect(port, lines, deadline)
      after
        remaining ->
          partial = parse_partial_result(lines)
          {:error, {:timeout, partial}}
      end
    end
  end

  defp parse_result(lines) do
    full_text = Enum.reverse(lines) |> IO.iodata_to_binary()

    # Parse stream-json lines and extract the final result
    case parse_stream_json(full_text) do
      {:ok, result, metadata} ->
        {:ok, result, metadata}

      {:error, reason} ->
        {:error, {:parse_error, reason, full_text}}

      :error ->
        {:error, {:no_result_found, String.slice(full_text, 0, 1000)}}
    end
  end

  defp parse_partial_result(lines) do
    full_text = Enum.reverse(lines) |> IO.iodata_to_binary()
    # Try to extract partial result from stream-json events
    case parse_stream_json(full_text) do
      {:ok, result, _} -> result
      _ -> full_text
    end
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

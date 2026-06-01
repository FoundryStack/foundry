defmodule Foundry.ClaudeCodeProvider do
  @moduledoc """
  Spawns Claude Code CLI as a subprocess and streams LLM responses.

  Claude Code acts as the inference engine with its own tools (Bash, Read, Grep, etc.).
  Foundry provides domain context via the system prompt.

  Uses `claude -p` headless mode with `--output-format stream-json` for streaming.
  No API key required — Claude Code uses browser OAuth authentication.

  See ADR-025 for the full specification.
  """

  require Logger

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
  Runs a conversation through Claude Code CLI and calls `on_event` as events arrive.

  Events:

    * `{:delta, text}` — incremental assistant text token
    * `{:trace, event}` — tool call or tool result (map with "type", "tool", "item" keys)
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
        claude_args = build_claude_args(system_prompt, model, prompt_text, opts)

        with :ok <- ensure_mcp_registration(claude_path, project_root, opts) do
          run_claude(claude_path, claude_args, project_root, timeout_ms, on_event)
        end
    end
  end

  defp format_conversation(messages) do
    Enum.map_join(messages, "\n\n", fn
      %{"role" => "user", "content" => content} -> "user: #{content}"
      %{"role" => "assistant", "content" => content} -> "assistant: #{content}"
      _other -> ""
    end)
  end

  defp build_claude_args(system_prompt, model, prompt_text, opts) do
    bypass? = Keyword.get(opts, :bypass_permissions, true)

    ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
    |> then(fn args -> if bypass?, do: args ++ ["--dangerously-skip-permissions"], else: args end)
    |> then(fn args ->
      if String.trim(system_prompt) != "",
        do: args ++ ["--system-prompt", system_prompt],
        else: args
    end)
    |> then(fn args -> if model, do: args ++ ["--model", model], else: args end)
    |> then(fn args -> args ++ [prompt_text] end)
  end

  defp ensure_mcp_registration(claude_path, project_root, opts) do
    case Keyword.get(opts, :mcp_config) do
      config when config in [nil, ""] ->
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
      {_output, 0} -> :ok
      {output, code} -> {:error, {:mcp_registration_failed, code, output}}
    end
  end

  defp run_claude(claude_path, claude_args, project_root, timeout_ms, on_event) do
    sh_bin = System.find_executable("sh") || "/bin/sh"
    env_bin = System.find_executable("env") || "/usr/bin/env"

    Logger.debug("[ClaudeCode] Spawning #{claude_path} in #{project_root}")

    # Port.open env: only merges — cannot remove inherited vars like CLAUDECODE.
    # Claude hangs if stdin is an open pipe, so we need </dev/null.
    # Spawn via sh -c with `env -i` to get a clean env and closed stdin.
    script = build_spawn_script(env_bin, claude_path, claude_args)

    port =
      Port.open({:spawn_executable, sh_bin}, [
        :stream,
        :exit_status,
        :binary,
        :stderr_to_stdout,
        {:args, ["-c", script]},
        {:cd, project_root}
      ])

    result = do_collect(port, [], "", [], timeout_ms, on_event)

    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end

    result
  end

  defp build_spawn_script(env_bin, claude_path, args) do
    env_vars =
      System.get_env()
      |> Map.delete("CLAUDECODE")
      |> Enum.map_join(" ", fn {k, v} -> "#{k}=#{shell_escape(v)}" end)

    args_str = Enum.map_join(args, " ", &shell_escape/1)
    "exec #{env_bin} -i #{env_vars} #{shell_escape(claude_path)} #{args_str} </dev/null 2>&1"
  end

  defp shell_escape(arg) do
    "'#{String.replace(arg, "'", "'\\''")}'"
  end

  defp do_collect(port, lines, buffer, text_chunks, timeout_ms, on_event) do
    receive do
      {^port, {:data, data}} ->
        {complete_lines, next_buffer} = split_lines(buffer <> data)
        new_chunks = dispatch_lines(complete_lines, on_event)
        do_collect(port, [data | lines], next_buffer, new_chunks ++ text_chunks, timeout_ms, on_event)

      {^port, {:exit_status, 0}} ->
        finalize(lines, buffer, text_chunks)

      {^port, {:exit_status, code}} ->
        {:error, {:exit_code, code, partial_text(lines, buffer)}}

      _other ->
        do_collect(port, lines, buffer, text_chunks, timeout_ms, on_event)
    after
      timeout_ms ->
        case finalize(lines, buffer, text_chunks) do
          {:ok, _, _} = ok -> ok
          _ -> {:error, {:timeout, partial_text(lines, buffer), partial_metadata(lines, buffer)}}
        end
    end
  end

  defp split_lines(data) do
    parts = String.split(data, "\n")
    {complete, [buffer]} = Enum.split(parts, -1)
    {complete, buffer}
  end

  defp dispatch_lines(lines, on_event) do
    Enum.flat_map(lines, fn line ->
      cond do
        text = text_delta(line) ->
          on_event.({:delta, text})
          [text]

        event = tool_event(line) ->
          on_event.({:trace, event})
          []

        true ->
          []
      end
    end)
  end

  defp text_delta(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "stream_event", "event" => %{"type" => "content_block_delta",
               "delta" => %{"type" => "text_delta", "text" => text}}}}
      when is_binary(text) -> text
      _ -> nil
    end
  end

  defp tool_event(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "assistant", "message" => %{"content" => content}}} when is_list(content) ->
        Enum.find_value(content, fn
          %{"type" => "tool_use", "id" => id, "name" => name, "input" => args} ->
            %{"provider" => "claude_code", "type" => "tool.call", "item_type" => "tool_call",
              "tool" => name, "message" => "Tool call: #{name}",
              "item" => %{"name" => name, "args" => args, "id" => id}}
          _ -> nil
        end)

      {:ok, %{"type" => "user", "message" => %{"content" => content}}} when is_list(content) ->
        Enum.find_value(content, fn
          %{"type" => "tool_result", "tool_use_id" => id, "content" => result} ->
            %{"provider" => "claude_code", "type" => "tool.result", "item_type" => "tool_call",
              "message" => "Tool completed",
              "item" => %{"status" => "ok", "id" => id, "output" => extract_text(result)}}
          _ -> nil
        end)

      _ -> nil
    end
  end

  defp extract_text(content) when is_binary(content), do: content

  defp extract_text(content) when is_list(content) do
    content
    |> Enum.filter(&(Map.get(&1, "type") == "text"))
    |> Enum.map_join("", &Map.get(&1, "text", ""))
  end

  defp extract_text(_), do: ""

  defp finalize(lines, buffer, text_chunks) do
    full = reassemble(lines, buffer)

    case parse_result_event(full) do
      {:ok, result, metadata} -> {:ok, result, metadata}
      {:error, _} = err -> err
      :error ->
        streamed = text_chunks |> Enum.reverse() |> IO.iodata_to_binary()
        if streamed == "",
          do: {:error, {:no_result_found, String.slice(full, 0, 1000)}},
          else: {:ok, streamed, %{}}
    end
  end

  defp partial_text(lines, buffer) do
    full = reassemble(lines, buffer)
    case parse_result_event(full) do
      {:ok, result, _} -> result
      _ -> full
    end
  end

  defp partial_metadata(lines, buffer) do
    full = reassemble(lines, buffer)
    case parse_result_event(full) do
      {:ok, _, metadata} -> Map.put(metadata, :partial, true)
      _ -> %{partial: true}
    end
  end

  defp reassemble(lines, buffer) do
    [buffer | lines] |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp parse_result_event(raw) do
    raw
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find_value(:error, fn line ->
      case Jason.decode(line) do
        {:ok, %{"type" => "result", "subtype" => "success"} = ev} ->
          {:ok, Map.get(ev, "result", ""), extract_metadata(ev)}

        {:ok, %{"type" => "result", "subtype" => subtype} = ev} ->
          {:error, {String.to_atom(subtype), ev}}

        _ -> nil
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

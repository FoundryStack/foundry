defmodule Foundry.ClaudeCodeProviderTest do
  use ExUnit.Case, async: false

  alias Foundry.ClaudeCodeProvider

  setup do
    original_path = System.get_env("PATH")
    original_claude_code = System.get_env("CLAUDECODE")
    original_stub_args_path = System.get_env("CLAUDE_STUB_ARGS_PATH")

    on_exit(fn ->
      restore_env("PATH", original_path)
      restore_env("CLAUDECODE", original_claude_code)
      restore_env("CLAUDE_STUB_ARGS_PATH", original_stub_args_path)
    end)
  end

  test "unsets CLAUDECODE, registers MCP once, and runs Claude print mode" do
    tmp_dir = make_tmp_dir!()
    executable = Path.join(tmp_dir, "claude")
    args_path = Path.join(tmp_dir, "args.txt")
    mcp_log_path = Path.join(tmp_dir, "mcp.log")
    write_claude_stub!(executable)

    System.put_env("PATH", tmp_dir <> ":" <> System.get_env("PATH", ""))
    System.put_env("CLAUDECODE", "1")
    System.put_env("CLAUDE_STUB_ARGS_PATH", args_path)
    System.put_env("CLAUDE_STUB_MCP_LOG_PATH", mcp_log_path)

    mcp_config =
      ~s({"foundry":{"command":"/tmp/foundry-mcp-stdio","env":{"BEARER_TOKEN":"test-token","FOUNDRY_MCP_HOST":"localhost"}}})

    assert {:ok, "claude-code-unset", %{}} =
             ClaudeCodeProvider.stream(
               [%{"role" => "user", "content" => "hello"}],
               [
                 system_prompt: "",
                 timeout_ms: 1_000,
                 project_root: tmp_dir,
                 mcp_config: mcp_config
               ],
               fn _event -> :ok end
             )

    args = File.read!(args_path)
    refute args =~ "--mcp-config"
    assert args =~ "--dangerously-skip-permissions"
    assert args =~ "--output-format"
    assert args =~ "stream-json"

    mcp_log = File.read!(mcp_log_path)
    assert mcp_log =~ "mcp add-json -s local foundry"

    assert mcp_log =~
             ~s({"command":"/tmp/foundry-mcp-stdio","env":{"BEARER_TOKEN":"test-token","FOUNDRY_MCP_HOST":"localhost"}})
  end

  test "emits deltas and trace events, returns final result from result event (not assistant event)" do
    tmp_dir = make_tmp_dir!()
    executable = Path.join(tmp_dir, "claude")

    # Stub that emits a multi-turn stream: text delta, tool call, tool result, final result
    File.write!(executable, """
    #!/bin/sh
    printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello "}}}'
    printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"world"}}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"ls"}}]}}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu1","content":"file.txt"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"intermediate text"}]}}'
    printf '%s\n' '{"type":"result","subtype":"success","result":"Final answer","session_id":"s1","duration_ms":1000,"total_cost_usd":0.01,"num_turns":2,"usage":{}}'
    """)
    File.chmod!(executable, 0o755)

    System.put_env("PATH", tmp_dir <> ":" <> System.get_env("PATH", ""))

    collector = fn event -> Process.put(:events, [event | (Process.get(:events) || [])]) end

    assert {:ok, "Final answer", metadata} =
             ClaudeCodeProvider.stream(
               [%{"role" => "user", "content" => "hello"}],
               [system_prompt: "", timeout_ms: 2_000, project_root: tmp_dir],
               collector
             )

    assert metadata.session_id == "s1"

    collected = Enum.reverse(Process.get(:events) || [])
    deltas = for {:delta, t} <- collected, do: t
    traces = for {:trace, e} <- collected, do: e

    assert Enum.join(deltas) == "Hello world"
    assert length(traces) == 2
    assert Enum.at(traces, 0)["type"] == "tool.call"
    assert Enum.at(traces, 0)["tool"] == "Bash"
    assert Enum.at(traces, 1)["type"] == "tool.result"
  end

  test "CLAUDECODE env var is unset in child process even when set in parent" do
    tmp_dir = make_tmp_dir!()
    executable = Path.join(tmp_dir, "claude")
    write_claude_stub!(executable)

    System.put_env("PATH", tmp_dir <> ":" <> System.get_env("PATH", ""))
    System.put_env("CLAUDECODE", "1")

    assert {:ok, "claude-code-unset", %{}} =
             ClaudeCodeProvider.stream(
               [%{"role" => "user", "content" => "hello"}],
               [system_prompt: "", timeout_ms: 1_000, project_root: tmp_dir],
               fn _event -> :ok end
             )
  end

  defp write_claude_stub!(path) do
    File.write!(path, """
    #!/bin/sh
    if [ "$1" = "mcp" ] && [ "$2" = "get" ] && [ "$3" = "foundry" ]; then
      exit 1
    fi

    if [ "$1" = "mcp" ] && [ "$2" = "add-json" ]; then
      if [ -n "$CLAUDE_STUB_MCP_LOG_PATH" ]; then
        printf '%s ' "$@" > "$CLAUDE_STUB_MCP_LOG_PATH"
      fi
      exit 0
    fi

    if [ -n "$CLAUDE_STUB_ARGS_PATH" ]; then
      printf '%s ' "$@" > "$CLAUDE_STUB_ARGS_PATH"
    fi

    if [ -n "$CLAUDECODE" ]; then
      echo "CLAUDECODE still set"
      exit 1
    fi

    printf '%s\n' '{"type":"result","subtype":"success","result":"claude-code-unset"}'
    """)

    File.chmod!(path, 0o755)
  end

  defp make_tmp_dir! do
    path =
      Path.join(System.tmp_dir!(), "claude-code-provider-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    path
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end

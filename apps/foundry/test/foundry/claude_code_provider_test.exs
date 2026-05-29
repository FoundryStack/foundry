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

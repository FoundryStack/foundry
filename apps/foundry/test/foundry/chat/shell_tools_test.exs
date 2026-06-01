defmodule Foundry.Chat.ShellToolsTest do
  use ExUnit.Case

  setup do
    # Create a temporary directory for testing
    tmp_dir = System.tmp_dir() <> "/foundry_test_#{System.unique_integer()}"
    File.mkdir_p!(tmp_dir)
    File.write!(tmp_dir <> "/test.txt", "test content")
    File.mkdir_p!(tmp_dir <> "/subdir")
    File.write!(tmp_dir <> "/subdir/nested.txt", "nested content")

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "all/0 returns tool schemas" do
    tools = Foundry.Chat.ShellTools.all()
    assert length(tools) == 3

    names = Enum.map(tools, & &1["name"])
    assert "read_file" in names
    assert "list_directory" in names
    assert "run_bash" in names
  end

  test "execute/3 reads a file", %{tmp_dir: tmp_dir} do
    result = Foundry.Chat.ShellTools.execute("read_file", %{"path" => "test.txt"}, tmp_dir)
    assert {:ok, "test content"} = result
  end

  test "execute/3 lists directory contents", %{tmp_dir: tmp_dir} do
    result = Foundry.Chat.ShellTools.execute("list_directory", %{"path" => "."}, tmp_dir)
    assert {:ok, content} = result
    assert String.contains?(content, "test.txt")
    assert String.contains?(content, "subdir")
  end

  test "execute/3 runs bash commands", %{tmp_dir: tmp_dir} do
    Application.put_env(:foundry, :shell_tools_policy, :open)
    result = Foundry.Chat.ShellTools.execute("run_bash", %{"command" => "ls"}, tmp_dir)
    assert {:ok, output} = result
    assert String.contains?(output, "test.txt")
  after
    Application.delete_env(:foundry, :shell_tools_policy)
  end

  test "execute/3 handles missing parameters" do
    result = Foundry.Chat.ShellTools.execute("read_file", %{}, ".")
    assert {:error, "Missing required parameter: path"} = result
  end

  test "execute/3 handles unknown tool" do
    result = Foundry.Chat.ShellTools.execute("unknown_tool", %{}, ".")
    assert {:error, "Unknown tool: unknown_tool"} = result
  end

  test "execute/3 rejects path traversal", %{tmp_dir: tmp_dir} do
    result = Foundry.Chat.ShellTools.execute("read_file", %{"path" => "../../../etc/passwd"}, tmp_dir)
    assert {:error, _} = result
  end

  test "execute/3 rejects non-allowlisted commands in allowlist mode", %{tmp_dir: tmp_dir} do
    Application.put_env(:foundry, :shell_tools_policy, :allowlist)
    result = Foundry.Chat.ShellTools.execute("run_bash", %{"command" => "curl http://example.com"}, tmp_dir)
    assert {:error, reason} = result
    assert String.contains?(reason, "not allowed")
  after
    Application.delete_env(:foundry, :shell_tools_policy)
  end

  test "execute/3 allows allowlisted commands", %{tmp_dir: tmp_dir} do
    Application.put_env(:foundry, :shell_tools_policy, :allowlist)
    result = Foundry.Chat.ShellTools.execute("run_bash", %{"command" => "ls"}, tmp_dir)
    assert {:ok, _output} = result
  after
    Application.delete_env(:foundry, :shell_tools_policy)
  end

  test "execute/3 allows arbitrary commands in open mode", %{tmp_dir: tmp_dir} do
    Application.put_env(:foundry, :shell_tools_policy, :open)
    result = Foundry.Chat.ShellTools.execute("run_bash", %{"command" => "curl http://example.com 2>&1 || echo 'curl not available'"}, tmp_dir)
    assert {:ok, _output} = result
  after
    Application.delete_env(:foundry, :shell_tools_policy)
  end

  test "execute/3 rejects commands with shell metacharacters", %{tmp_dir: tmp_dir} do
    Application.put_env(:foundry, :shell_tools_policy, :allowlist)
    result = Foundry.Chat.ShellTools.execute("run_bash", %{"command" => "ls && rm -rf /"}, tmp_dir)
    assert {:error, reason} = result
    assert String.contains?(reason, "not allowed")
  after
    Application.delete_env(:foundry, :shell_tools_policy)
  end
end

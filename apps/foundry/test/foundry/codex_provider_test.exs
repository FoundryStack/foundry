defmodule Foundry.CodexProviderTest do
  use ExUnit.Case, async: false

  alias Foundry.CodexProvider

  setup do
    original_home = System.get_env("HOME")
    original_path = System.get_env("PATH")
    original_stub_args_path = System.get_env("CODEX_STUB_ARGS_PATH")

    on_exit(fn ->
      restore_env("HOME", original_home)
      restore_env("PATH", original_path)
      restore_env("CODEX_STUB_ARGS_PATH", original_stub_args_path)
    end)
  end

  test "honors an explicit relative executable path" do
    tmp_dir = make_tmp_dir!()
    executable = Path.join(tmp_dir, "codex")
    write_codex_stub!(executable, "relative-ok")

    result =
      File.cd!(tmp_dir, fn ->
        CodexProvider.stream(
          [%{"role" => "user", "content" => "hello"}],
          [system_prompt: "", timeout_ms: 1_000, executable: "./codex", project_root: tmp_dir],
          fn _event -> :ok end
        )
      end)

    assert {:ok, "relative-ok", %{}} = result
  end

  test "expands a tilde-prefixed executable path before validation" do
    tmp_dir = make_tmp_dir!()
    bin_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(bin_dir)

    executable = Path.join(bin_dir, "codex")
    write_codex_stub!(executable, "home-ok")
    System.put_env("HOME", tmp_dir)

    assert {:ok, "home-ok", %{}} =
             CodexProvider.stream(
               [%{"role" => "user", "content" => "hello"}],
               [
                 system_prompt: "",
                 timeout_ms: 1_000,
                 executable: "~/bin/codex",
                 project_root: tmp_dir
               ],
               fn _event -> :ok end
             )
  end

  test "does not fall back when an explicit path is missing" do
    tmp_dir = make_tmp_dir!()

    assert {:error, :not_installed} =
             CodexProvider.stream(
               [%{"role" => "user", "content" => "hello"}],
               [
                 system_prompt: "",
                 timeout_ms: 1_000,
                 executable: Path.join(tmp_dir, "missing-codex"),
                 project_root: tmp_dir
               ],
               fn _event -> :ok end
             )
  end

  test "rejects non-executable regular files for explicit paths" do
    tmp_dir = make_tmp_dir!()
    executable = Path.join(tmp_dir, "codex")
    File.write!(executable, "#!/bin/sh\n")
    File.chmod!(executable, 0o644)

    assert {:error, :not_installed} =
             CodexProvider.stream(
               [%{"role" => "user", "content" => "hello"}],
               [
                 system_prompt: "",
                 timeout_ms: 1_000,
                 executable: executable,
                 project_root: tmp_dir
               ],
               fn _event -> :ok end
             )
  end

  test "bare executable names still resolve through PATH" do
    tmp_dir = make_tmp_dir!()
    executable = Path.join(tmp_dir, "codex")
    write_codex_stub!(executable, "path-ok")

    System.put_env("PATH", tmp_dir <> ":" <> System.get_env("PATH", ""))

    assert {:ok, "path-ok", %{}} =
             CodexProvider.stream(
               [%{"role" => "user", "content" => "hello"}],
               [system_prompt: "", timeout_ms: 1_000, executable: "codex", project_root: tmp_dir],
               fn _event -> :ok end
             )
  end

  test "bypasses Codex approvals and sandbox by default" do
    tmp_dir = make_tmp_dir!()
    executable = Path.join(tmp_dir, "codex")
    args_path = Path.join(tmp_dir, "args.txt")
    write_codex_stub!(executable, "bypass-ok")
    System.put_env("CODEX_STUB_ARGS_PATH", args_path)

    assert {:ok, "bypass-ok", %{}} =
             CodexProvider.stream(
               [%{"role" => "user", "content" => "hello"}],
               [
                 system_prompt: "",
                 timeout_ms: 1_000,
                 executable: executable,
                 project_root: tmp_dir
               ],
               fn _event -> :ok end
             )

    args = File.read!(args_path)
    assert args =~ "--dangerously-bypass-approvals-and-sandbox"
    refute args =~ " -s "
  end

  test "can still run with an explicit sandbox when bypass is disabled" do
    tmp_dir = make_tmp_dir!()
    executable = Path.join(tmp_dir, "codex")
    args_path = Path.join(tmp_dir, "args.txt")
    write_codex_stub!(executable, "sandbox-ok")
    System.put_env("CODEX_STUB_ARGS_PATH", args_path)

    assert {:ok, "sandbox-ok", %{}} =
             CodexProvider.stream(
               [%{"role" => "user", "content" => "hello"}],
               [
                 system_prompt: "",
                 timeout_ms: 1_000,
                 executable: executable,
                 project_root: tmp_dir,
                 bypass_approvals_and_sandbox: false,
                 sandbox: "read-only"
               ],
               fn _event -> :ok end
             )

    args = File.read!(args_path)
    refute args =~ "--dangerously-bypass-approvals-and-sandbox"
    assert args =~ " -s read-only "
  end

  defp write_codex_stub!(path, text) do
    File.write!(path, """
    #!/bin/sh
    if [ -n "$CODEX_STUB_ARGS_PATH" ]; then
      printf '%s ' "$@" > "$CODEX_STUB_ARGS_PATH"
    fi
    printf '%s\n' '{"type":"agent_message.delta","delta":"#{text}"}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"#{text}"}}'
    """)

    File.chmod!(path, 0o755)
  end

  defp write_codex_stub_with_full_text_event!(path) do
    File.write!(path, """
    #!/bin/sh
    printf '%s\\n' '{"type":"agent_message.delta","delta":"chunk1"}'
    printf '%s\\n' '{"type":"item.updated","item":{"type":"agent_message","text":"chunk1"}}'
    printf '%s\\n' '{"type":"agent_message.delta","delta":"chunk2"}'
    printf '%s\\n' '{"type":"item.completed","item":{"type":"agent_message","text":"chunk1chunk2"}}'
    """)

    File.chmod!(path, 0o755)
  end

  # Simulates real `codex exec --json` output: only item.completed, no incremental deltas
  defp write_codex_stub_only_completed!(path) do
    File.write!(path, """
    #!/bin/sh
    printf '%s\\n' '{"type":"item.completed","item":{"type":"agent_message","text":"hello world"}}'
    """)

    File.chmod!(path, 0o755)
  end

  defp make_tmp_dir! do
    path = Path.join(System.tmp_dir!(), "codex-provider-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end

  describe "streaming delta events" do
    # codex exec --json only emits item.completed (full text at end), no true incremental deltas.
    # We emit item.completed as a single delta so text appears rather than staying blank.
    # item.updated is NOT emitted as a delta (it's a duplicate accumulated snapshot, not a delta).
    test "emits agent_message.delta and item.completed as deltas, but not item.updated" do
      tmp_dir = make_tmp_dir!()
      executable = Path.join(tmp_dir, "codex")
      write_codex_stub_with_full_text_event!(executable)

      {:ok, collector} = Agent.start_link(fn -> [] end)

      on_event = fn
        {:delta, text} -> Agent.update(collector, &(&1 ++ [text]))
        _other -> :ok
      end

      {:ok, result, _metadata} =
        CodexProvider.stream(
          [%{"role" => "user", "content" => "hello"}],
          [system_prompt: "", timeout_ms: 1_000, executable: executable, project_root: tmp_dir],
          on_event
        )

      deltas = Agent.get(collector, & &1)
      Agent.stop(collector)

      # Stub emits: agent_message.delta("chunk1"), item.updated(full), agent_message.delta("chunk2"), item.completed(full)
      # Expected deltas: "chunk1", "chunk2", "chunk1chunk2" (item.updated skipped, item.completed included)
      assert deltas == ["chunk1", "chunk2", "chunk1chunk2"]
      assert result == "chunk1chunk2"
    end

    test "emits item.completed as a delta when no incremental deltas are present" do
      tmp_dir = make_tmp_dir!()
      executable = Path.join(tmp_dir, "codex")
      write_codex_stub_only_completed!(executable)

      {:ok, collector} = Agent.start_link(fn -> [] end)

      on_event = fn
        {:delta, text} -> Agent.update(collector, &(&1 ++ [text]))
        _other -> :ok
      end

      {:ok, result, _metadata} =
        CodexProvider.stream(
          [%{"role" => "user", "content" => "hello"}],
          [system_prompt: "", timeout_ms: 1_000, executable: executable, project_root: tmp_dir],
          on_event
        )

      deltas = Agent.get(collector, & &1)
      Agent.stop(collector)

      # codex exec --json only produces item.completed — it must be emitted as a delta
      assert deltas == ["hello world"]
      assert result == "hello world"
    end
  end

  defp restore_env(_key, nil), do: :ok
  defp restore_env(key, value), do: System.put_env(key, value)
end

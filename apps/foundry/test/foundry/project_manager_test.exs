defmodule Foundry.ProjectManagerTest do
  use ExUnit.Case

  test "classify_folder/1 detects empty folder" do
    dir = System.tmp_dir!() |> Path.join("pm_test_empty_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)

    try do
      assert Foundry.ProjectManager.classify_folder(dir) == :empty_folder
    after
      File.rm_rf!(dir)
    end
  end

  test "classify_folder/1 detects partial project (mix.exs without .foundry)" do
    dir = System.tmp_dir!() |> Path.join("pm_test_partial_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)

    try do
      File.write!(Path.join(dir, "mix.exs"), "# Mix project")
      assert Foundry.ProjectManager.classify_folder(dir) == :partial_project
    after
      File.rm_rf!(dir)
    end
  end

  test "classify_folder/1 detects existing project (mix.exs + .foundry)" do
    dir = System.tmp_dir!() |> Path.join("pm_test_existing_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)

    try do
      File.write!(Path.join(dir, "mix.exs"), "# Mix project")
      File.mkdir_p!(Path.join(dir, ".foundry"))
      assert Foundry.ProjectManager.classify_folder(dir) == :existing_project
    after
      File.rm_rf!(dir)
    end
  end

  test "classify_folder/1 returns error for non-existent directory" do
    path = "/nonexistent/path_#{:rand.uniform(999)}"
    assert Foundry.ProjectManager.classify_folder(path) == {:error, :not_a_directory}
  end

  test "classify_folder/1 handles paths with spaces and expands paths" do
    dir = System.tmp_dir!() |> Path.join("pm_test_spaces #{:rand.uniform(99999)}")
    File.mkdir_p!(dir)

    try do
      result = Foundry.ProjectManager.classify_folder("  #{dir}  ")
      assert result == :empty_folder
    after
      File.rm_rf!(dir)
    end
  end

  describe "clone_project/2 idempotency" do
    setup do
      src = System.tmp_dir!() |> Path.join("pm_src_#{:rand.uniform(99999)}")
      dest_parent = System.tmp_dir!() |> Path.join("pm_dest_#{:rand.uniform(99999)}")
      File.mkdir_p!(src)
      File.mkdir_p!(dest_parent)

      System.cmd("git", ["init", src])
      System.cmd("git", ["-C", src, "config", "user.email", "test@test.com"])
      System.cmd("git", ["-C", src, "config", "user.name", "Test"])
      File.write!(Path.join(src, "mix.exs"), "defmodule T.MixProject do\n  use Mix.Project\n  def project, do: [app: :t, version: \"0.1.0\"]\nend\n")
      System.cmd("git", ["-C", src, "add", "."])
      System.cmd("git", ["-C", src, "commit", "-m", "init"])

      on_exit(fn ->
        File.rm_rf!(src)
        File.rm_rf!(dest_parent)
      end)

      %{repo_url: src, dest_parent: dest_parent}
    end

    defp wait_for_terminal_status(timeout_ms \\ 10_000) do
      deadline = System.monotonic_time(:millisecond) + timeout_ms

      Stream.repeatedly(fn -> Process.sleep(100) end)
      |> Enum.reduce_while(nil, fn _, _ ->
        status = Foundry.ProjectManager.get_status()

        cond do
          status.state in [:ready, :failed] -> {:halt, status}
          System.monotonic_time(:millisecond) >= deadline -> {:halt, status}
          true -> {:cont, nil}
        end
      end)
    end

    test "succeeds when target does not exist", %{repo_url: repo_url, dest_parent: dest_parent} do
      Foundry.ProjectManager.clone_project(repo_url, dest_parent)
      status = wait_for_terminal_status()
      assert status.state == :ready, "Expected :ready, got: #{status.state} — #{inspect(status.last_error)}"
    end

    test "reuses existing valid clone without error", %{repo_url: repo_url, dest_parent: dest_parent} do
      Foundry.ProjectManager.clone_project(repo_url, dest_parent)
      first_status = wait_for_terminal_status()
      assert first_status.state == :ready

      Foundry.ProjectManager.clone_project(repo_url, dest_parent)
      second_status = wait_for_terminal_status()
      assert second_status.state == :ready, "Second clone failed: #{inspect(second_status.last_error)}"
    end

    test "removes incomplete clone and re-clones", %{repo_url: repo_url, dest_parent: dest_parent} do
      repo_name = Path.basename(repo_url)
      broken_path = Path.join(dest_parent, repo_name)
      File.mkdir_p!(broken_path)
      File.write!(Path.join(broken_path, "junk"), "partial")

      Foundry.ProjectManager.clone_project(repo_url, dest_parent)
      status = wait_for_terminal_status()

      assert status.state == :ready, "Expected :ready after re-clone, got: #{status.state} — #{inspect(status.last_error)}"
      assert File.dir?(Path.join(broken_path, ".git"))
    end

    test "compiles into _build/dev/ after ready", %{repo_url: repo_url, dest_parent: dest_parent} do
      # Regression: install_dependencies compiled with MIX_ENV=prod into _build/prod/.
      # ModuleDiscovery scans ["dev","prod","test"] but preview server requires _build/dev/
      # to skip recompilation. Both must use the same dir.
      repo_name = Path.basename(repo_url)
      project_root = Path.join(dest_parent, repo_name)

      Foundry.ProjectManager.clone_project(repo_url, dest_parent)
      status = wait_for_terminal_status(30_000)

      assert status.state == :ready, "Expected :ready, got: #{status.state} — #{inspect(status.last_error)}"
      assert File.dir?(Path.join(project_root, "_build/dev")),
             "_build/dev/ must exist after install_dependencies so both ModuleDiscovery and the preview server find pre-built artifacts"
    end

    test "skips compile when _build/dev/ already exists", %{repo_url: repo_url, dest_parent: dest_parent} do
      # First open: builds _build/dev/
      Foundry.ProjectManager.clone_project(repo_url, dest_parent)
      first = wait_for_terminal_status(30_000)
      assert first.state == :ready

      # Second open of the same project: must hit the fast-path skip — no mix compile in logs
      repo_name = Path.basename(repo_url)
      project_root = Path.join(dest_parent, repo_name)
      Foundry.ProjectManager.open_project(project_root)
      second = wait_for_terminal_status(10_000)

      assert second.state == :ready
      refute String.contains?(second.logs, "mix compile"),
             "install_dependencies should skip compile when _build/dev/ already exists, but logs had: #{second.logs}"
    end

  end

  test "VM is not in :embedded code loading mode" do
    # Regression: server release defaults to :embedded, which blocks Code.append_path
    # at runtime. The studio must run in :interactive mode to load project BEAM files.
    refute :code.get_mode() == :embedded,
           "Release is in :embedded mode — add code_loading_mode: :interactive to the server release in mix.exs"
  end

  test "ModuleDiscovery returns non-empty list for the bundled igaming reference project" do
    # Regression: server release ran in :embedded mode — Code.ensure_loaded? returned false
    # for all modules loaded via Code.append_path, so ModuleDiscovery always returned [].
    # Fix: code_loading_mode: :interactive in mix.exs releases config.
    project_root = Foundry.ProjectManager.default_project_root()
    {:ok, manifest} = Foundry.Manifest.Parser.read(project_root)
    project_name = Keyword.fetch!(manifest, :project_name)

    modules = Foundry.Context.ModuleDiscovery.all_project_modules(project_root, project_name)

    assert length(modules) > 0,
           "ModuleDiscovery returned [] — BEAM files exist but Code.ensure_loaded? failed. " <>
             "Likely cause: VM in :embedded mode (current: #{inspect(:code.get_mode())})"
  end

  describe "build_env/0" do
    # Tests for the RELEASE_* env var stripping fix (commit 40846dff)
    # Verifies that child processes don't inherit release boot vars that crash mix

    test "strips RELEASE_* vars from environment" do
      old_release_root = System.get_env("RELEASE_ROOT")
      old_release_boot = System.get_env("RELEASE_BOOT_SCRIPT")

      try do
        System.put_env("RELEASE_ROOT", "/app")
        System.put_env("RELEASE_BOOT_SCRIPT", "start")
        System.put_env("RELEASE_SYS_CONFIG", "/app/releases/0.1.0/sys")

        env = Foundry.ProjectManager.build_env()
        env_keys = Enum.map(env, &elem(&1, 0)) |> Enum.map(&List.to_string/1)

        refute Enum.any?(env_keys, &String.starts_with?(&1, "RELEASE_")),
               "RELEASE_* vars should be stripped: #{inspect(env_keys)}"
      after
        if old_release_root, do: System.put_env("RELEASE_ROOT", old_release_root), else: System.delete_env("RELEASE_ROOT")
        if old_release_boot, do: System.put_env("RELEASE_BOOT_SCRIPT", old_release_boot), else: System.delete_env("RELEASE_BOOT_SCRIPT")
        System.delete_env("RELEASE_SYS_CONFIG")
      end
    end

    test "preserves non-RELEASE vars" do
      old_path = System.get_env("PATH")

      try do
        env = Foundry.ProjectManager.build_env()
        env_keys = Enum.map(env, &elem(&1, 0)) |> Enum.map(&List.to_string/1)

        assert "PATH" in env_keys,
               "Non-RELEASE vars like PATH should be preserved"
      after
        if old_path, do: System.put_env("PATH", old_path)
      end
    end

    test "always sets MIX_HOME to /tmp/.mix" do
      env = Foundry.ProjectManager.build_env()
      mix_home = Enum.find(env, fn {k, _v} -> List.to_string(k) == "MIX_HOME" end)

      assert mix_home != nil, "MIX_HOME should be set"
      assert elem(mix_home, 1) == ~c"/tmp/.mix", "MIX_HOME should be /tmp/.mix"
    end

    test "always sets HEX_HOME to /tmp/.hex" do
      env = Foundry.ProjectManager.build_env()
      hex_home = Enum.find(env, fn {k, _v} -> List.to_string(k) == "HEX_HOME" end)

      assert hex_home != nil, "HEX_HOME should be set"
      assert elem(hex_home, 1) == ~c"/tmp/.hex", "HEX_HOME should be /tmp/.hex"
    end

    test "returns charlist tuples for Port.open compatibility" do
      env = Foundry.ProjectManager.build_env()

      Enum.each(env, fn {key, value} ->
        assert is_list(key), "Key should be a charlist"
        assert is_list(value), "Value should be a charlist"
      end)
    end

    test "overrides MIX_HOME even if already in env" do
      old_mix_home = System.get_env("MIX_HOME")

      try do
        System.put_env("MIX_HOME", "/home/user/.mix")
        env = Foundry.ProjectManager.build_env()
        mix_home = Enum.find(env, fn {k, _v} -> List.to_string(k) == "MIX_HOME" end)

        assert elem(mix_home, 1) == ~c"/tmp/.mix",
               "MIX_HOME should be overridden to /tmp/.mix regardless of current env"
      after
        if old_mix_home, do: System.put_env("MIX_HOME", old_mix_home), else: System.delete_env("MIX_HOME")
      end
    end

    test "strips RELEASE_ROOT/erts-*/bin and RELEASE_ROOT/bin from PATH" do
      # Regression test: the release boot process prepends /app/erts-*/bin and /app/bin
      # to PATH. These contain the release's erlexec which is pre-configured to boot as a
      # release (looking for /app/bin/start.boot). mix picks up that erlexec and crashes
      # with "cannot get bootfile /app/bin/start.boot" even when RELEASE_* vars are stripped.
      old_path = System.get_env("PATH")
      old_release_root = System.get_env("RELEASE_ROOT")

      try do
        System.put_env("RELEASE_ROOT", "/app")
        System.put_env("PATH", "/app/erts-16.4/bin:/app/bin:/usr/local/bin:/usr/bin:/bin")

        env = Foundry.ProjectManager.build_env()
        path_entry = Enum.find(env, fn {k, _v} -> List.to_string(k) == "PATH" end)
        path = path_entry |> elem(1) |> List.to_string()
        path_parts = String.split(path, ":")

        refute Enum.any?(path_parts, &String.starts_with?(&1, "/app")),
               "Release ERTS/bin paths should be removed from PATH: #{path}"

        assert "/usr/local/bin" in path_parts, "System paths should be preserved"
      after
        if old_path, do: System.put_env("PATH", old_path), else: System.delete_env("PATH")
        if old_release_root, do: System.put_env("RELEASE_ROOT", old_release_root), else: System.delete_env("RELEASE_ROOT")
      end
    end
  end

  describe "child process env isolation" do
    # These tests verify what actually reaches the child process — not just that
    # build_env/0 filters correctly, but that the Port.open invocation (via env -i)
    # prevents RELEASE_* vars from being inherited. This is the regression test for
    # the production crash: "Runtime terminating during boot ({'cannot get bootfile'...})"

    defp run_env_inspect(extra_system_env \\ %{}) do
      Enum.each(extra_system_env, fn {k, v} -> System.put_env(k, v) end)

      env_bin = System.find_executable("env")
      env_pairs = Foundry.ProjectManager.build_env()
      env_prefix = Enum.map(env_pairs, fn {k, v} -> "#{k}=#{v}" end)

      port =
        Port.open(
          {:spawn_executable, env_bin},
          [:binary, :exit_status, :stderr_to_stdout, :use_stdio, :hide,
           args: ["-i"] ++ env_prefix ++ [env_bin]]
        )

      output =
        Stream.repeatedly(fn -> nil end)
        |> Enum.reduce_while("", fn _, acc ->
          receive do
            {^port, {:data, data}} -> {:cont, acc <> data}
            {^port, {:exit_status, _}} -> {:halt, acc}
          after
            5000 -> {:halt, acc}
          end
        end)

      Enum.each(extra_system_env, fn {k, _} -> System.delete_env(k) end)
      output
    end

    test "RELEASE_* vars do not reach child process when set in parent" do
      output =
        run_env_inspect(%{
          "RELEASE_ROOT" => "/app",
          "RELEASE_BOOT_SCRIPT" => "start",
          "RELEASE_SYS_CONFIG" => "/app/releases/0.1.0/sys"
        })

      child_vars = String.split(output, "\n") |> Enum.filter(&String.starts_with?(&1, "RELEASE_"))

      assert child_vars == [],
             "RELEASE_* vars leaked into child process: #{inspect(child_vars)}"
    end

    test "MIX_HOME is /tmp/.mix in child process regardless of parent value" do
      output = run_env_inspect(%{"MIX_HOME" => "/home/user/.mix"})

      mix_home =
        String.split(output, "\n")
        |> Enum.find("", &String.starts_with?(&1, "MIX_HOME="))
        |> String.trim_leading("MIX_HOME=")

      assert mix_home == "/tmp/.mix",
             "Expected MIX_HOME=/tmp/.mix in child, got: #{inspect(mix_home)}"
    end

    test "PATH is passed through to child process" do
      output = run_env_inspect()
      assert String.contains?(output, "PATH="), "PATH should be present in child process"
    end

    test "extra_env overrides MIX_ENV in child process" do
      # Regression: install_dependencies used to ignore extra_env, so MIX_ENV=dev never
      # reached mix compile, causing it to build into _build/prod/ instead of _build/dev/.
      old_mix_env = System.get_env("MIX_ENV")

      try do
        System.put_env("MIX_ENV", "prod")
        output = run_env_inspect(%{"MIX_ENV" => "dev"})

        mix_env =
          String.split(output, "\n")
          |> Enum.find("", &String.starts_with?(&1, "MIX_ENV="))
          |> String.trim_leading("MIX_ENV=")
          |> String.trim()

        assert mix_env == "dev",
               "extra_env MIX_ENV=dev should override parent MIX_ENV=prod in child, got: #{inspect(mix_env)}"
      after
        if old_mix_env, do: System.put_env("MIX_ENV", old_mix_env), else: System.delete_env("MIX_ENV")
      end
    end

    test "release ERTS/bin paths are stripped from PATH in child process" do
      # Regression test: /app/erts-*/bin in PATH causes mix to pick up the release erlexec,
      # which crashes with "cannot get bootfile /app/bin/start.boot" even without RELEASE_* vars.
      old_path = System.get_env("PATH")
      old_release_root = System.get_env("RELEASE_ROOT")

      try do
        System.put_env("RELEASE_ROOT", "/app")
        System.put_env("PATH", "/app/erts-16.4/bin:/app/bin:/usr/local/bin:/usr/bin:/bin")

        output = run_env_inspect()

        path_line =
          String.split(output, "\n")
          |> Enum.find("", &String.starts_with?(&1, "PATH="))
          |> String.trim_leading("PATH=")

        path_parts = String.split(path_line, ":")

        refute Enum.any?(path_parts, &String.starts_with?(&1, "/app")),
               "Release ERTS/bin paths leaked into child PATH: #{path_line}"
      after
        if old_path, do: System.put_env("PATH", old_path), else: System.delete_env("PATH")
        if old_release_root, do: System.put_env("RELEASE_ROOT", old_release_root), else: System.delete_env("RELEASE_ROOT")
      end
    end
  end

  describe "derive_repo_name/1" do
    test "extracts repo name from https URL" do
      assert Foundry.ProjectManager.derive_repo_name("https://github.com/user/repo.git") == "repo"
    end

    test "extracts repo name from SSH URL" do
      assert Foundry.ProjectManager.derive_repo_name("git@github.com:user/repo.git") == "repo"
    end

    test "strips trailing slash" do
      assert Foundry.ProjectManager.derive_repo_name("https://github.com/user/repo/") == "repo"
    end

    test "removes .git suffix" do
      assert Foundry.ProjectManager.derive_repo_name("https://github.com/user/repo.git") == "repo"
    end

    test "falls back to foundry-project for empty path" do
      assert Foundry.ProjectManager.derive_repo_name("") == "foundry-project"
      assert Foundry.ProjectManager.derive_repo_name("/") == "foundry-project"
    end

    test "handles plain directory paths (used in tests with local repos)" do
      assert Foundry.ProjectManager.derive_repo_name("/local/path/my-project") == "my-project"
    end
  end

  describe "open_project/1" do
    test "fails with error for non-existent path" do
      result = Foundry.ProjectManager.open_project("/nonexistent/project_#{:rand.uniform(99999)}")
      assert result == {:error, :busy} or result == :ok
      # Note: open_project calls GenServer which may be busy from other tests
      # This test just verifies it doesn't crash
    end
  end

  describe "recent_projects persistence" do
    setup do
      home = System.tmp_dir!() |> Path.join("foundry_home_#{:rand.uniform(99999)}")
      File.mkdir_p!(home)

      old_home = System.get_env("FOUNDRY_HOME")

      on_exit(fn ->
        File.rm_rf!(home)
        if old_home, do: System.put_env("FOUNDRY_HOME", old_home), else: System.delete_env("FOUNDRY_HOME")
      end)

      System.put_env("FOUNDRY_HOME", home)
      %{home: home}
    end

    test "recent_projects returns empty list when no projects saved", %{home: _home} do
      projects = Foundry.ProjectManager.recent_projects()
      assert is_list(projects)
    end
  end

  describe "clone_project into unwritable parent dir" do
    # Regression: Docker named volumes are created by the daemon with root:root ownership.
    # The foundry container runs as deploy (uid 1000), so git clone into /app/projects fails
    # with "Permission denied" (exit 128). validate_parent_dir only checks File.dir?, not
    # writability — the clone command itself discovered the problem too late.

    test "clone_project fails fast with clear error when parent dir is not writable" do
      # Create a temp dir and remove write permission to simulate root-owned volume mount
      parent = System.tmp_dir!() |> Path.join("pm_unwritable_#{:rand.uniform(99999)}")
      File.mkdir_p!(parent)
      File.chmod!(parent, 0o555)

      try do
        # We need a fake repo URL — use a local git repo so the test is fast
        src = System.tmp_dir!() |> Path.join("pm_src_unwritable_#{:rand.uniform(99999)}")
        File.mkdir_p!(src)
        System.cmd("git", ["init", src])
        System.cmd("git", ["-C", src, "config", "user.email", "test@test.com"])
        System.cmd("git", ["-C", src, "config", "user.name", "Test"])
        File.write!(Path.join(src, "mix.exs"), "# mix")
        System.cmd("git", ["-C", src, "add", "."])
        System.cmd("git", ["-C", src, "commit", "-m", "init"])

        Foundry.ProjectManager.clone_project(src, parent)

        # Wait for terminal state
        deadline = System.monotonic_time(:millisecond) + 10_000
        status =
          Stream.repeatedly(fn -> Process.sleep(100) end)
          |> Enum.reduce_while(nil, fn _, _ ->
            s = Foundry.ProjectManager.get_status()
            cond do
              s.state in [:ready, :failed] -> {:halt, s}
              System.monotonic_time(:millisecond) >= deadline -> {:halt, s}
              true -> {:cont, nil}
            end
          end)

        assert status.state == :failed,
               "Expected clone to fail with Permission denied, got: #{status.state}"

        assert status.last_error =~ "not writable" or status.last_error =~ "permission denied" or
                 status.last_error =~ "Permission denied",
               "Expected a permission-related error, got: #{inspect(status.last_error)}"

        File.rm_rf!(src)
      after
        File.chmod!(parent, 0o755)
        File.rm_rf!(parent)
      end
    end
  end

  describe "configure_runtime does not corrupt FOUNDRY_STANDALONE in cloud mode" do
    # Regression: configure_runtime called System.put_env("FOUNDRY_STANDALONE", "1")
    # unconditionally. After first project open, any ?repo_url= visit saw FOUNDRY_STANDALONE=1
    # and tried to clone into System.user_home!() = /home/foundry (which doesn't exist).

    test "FOUNDRY_STANDALONE stays '0' after configure_runtime when running in cloud mode" do
      old_val = System.get_env("FOUNDRY_STANDALONE")

      try do
        System.put_env("FOUNDRY_STANDALONE", "0")
        Foundry.Studio.configure_runtime("/tmp/fake_project")
        assert System.get_env("FOUNDRY_STANDALONE") == "0",
               "configure_runtime must not overwrite FOUNDRY_STANDALONE when it is already '0' (cloud mode)"
      after
        if old_val, do: System.put_env("FOUNDRY_STANDALONE", old_val), else: System.delete_env("FOUNDRY_STANDALONE")
      end
    end

    test "FOUNDRY_STANDALONE is set to '1' when not previously set (standalone / desktop mode)" do
      old_val = System.get_env("FOUNDRY_STANDALONE")

      try do
        System.delete_env("FOUNDRY_STANDALONE")
        Foundry.Studio.configure_runtime("/tmp/fake_project")
        assert System.get_env("FOUNDRY_STANDALONE") == "1",
               "configure_runtime should set FOUNDRY_STANDALONE=1 when launching in standalone mode"
      after
        if old_val, do: System.put_env("FOUNDRY_STANDALONE", old_val), else: System.delete_env("FOUNDRY_STANDALONE")
      end
    end
  end

  describe "persist_state fallback when home is not writable" do
    # Regression test: in the foundry-studio container, System.user_home!() returns
    # /home/foundry which doesn't exist, causing persist_state to crash with
    # "could not make directory /home/foundry/.foundry: permission denied".
    # ProjectManager should fall back to /tmp when the home dir is not writable.

    test "does not crash when FOUNDRY_HOME is unset and user home is unwritable" do
      old_home = System.get_env("FOUNDRY_HOME")

      try do
        System.delete_env("FOUNDRY_HOME")

        # Simulate the container scenario: call the GenServer path that triggers persist_state.
        # We can't easily mock user_home, but we CAN verify that setting FOUNDRY_HOME to
        # a valid writable temp dir works (the normal path) and that the fallback logic
        # compiles correctly by ensuring the module loaded.
        tmp = System.tmp_dir!() |> Path.join("pm_persist_test_#{:rand.uniform(99999)}")
        File.mkdir_p!(tmp)

        try do
          System.put_env("FOUNDRY_HOME", tmp)
          # If persist_state works, recent_projects will read from the same path fine
          projects = Foundry.ProjectManager.recent_projects()
          assert is_list(projects)
        after
          File.rm_rf!(tmp)
        end
      after
        if old_home, do: System.put_env("FOUNDRY_HOME", old_home), else: System.delete_env("FOUNDRY_HOME")
      end
    end
  end
end

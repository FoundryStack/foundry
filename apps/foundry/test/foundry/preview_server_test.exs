defmodule Foundry.PreviewServerTest do
  use ExUnit.Case, async: false

  alias Foundry.PreviewServer

  setup do
    Application.ensure_all_started(:foundry)
    # Use a short timeout in tests so the "times out" test doesn't take 3 minutes.
    Application.put_env(:foundry, :preview_startup_timeout_ms, 10_000)
    on_exit(fn -> Application.delete_env(:foundry, :preview_startup_timeout_ms) end)
    PreviewServer.stop_preview()
    assert wait_for_state(:idle)

    project_root =
      Path.join(
        System.tmp_dir!(),
        "foundry-preview-server-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf(project_root)
    File.mkdir_p!(project_root)

    on_exit(fn ->
      PreviewServer.stop_preview()
      wait_for_state(:idle)
      File.rm_rf(project_root)
    end)

    {:ok, project_root: project_root}
  end

  test "starts preview process when manifest env entries are charlists", %{
    project_root: project_root
  } do
    File.write!(
      Path.join(project_root, "manifest.exs"),
      """
      [
        preview_server: [
          command: "sh -c 'echo preview booted'",
          env: [{~c"MIX_ENV", ~c"dev"}],
          port: 4101
        ]
      ]
      """
    )

    PreviewServer.start_preview(project_root)

    assert wait_for_last_error("Preview process exited before opening the HTTP port.", 200)
    assert {:ok, status} = PreviewServer.get_status()
    assert status.state == :failed
    assert status.port == 4101
    assert status.project_root == project_root
    assert status.url == "http://localhost:4101"
    assert status.output =~ "preview booted"
    assert status.last_error == "Preview process exited before opening the HTTP port."
  end

  test "reads preview base url from manifest config", %{project_root: project_root} do
    File.write!(
      Path.join(project_root, "manifest.exs"),
      """
      [
        preview_server: [
          command: "mix phx.server",
          port: 4202,
          env: []
        ]
      ]
      """
    )

    assert PreviewServer.preview_base_url(project_root) == "http://localhost:4202"
  end

  test "preview_base_url returns subdomain URL in cloud mode (FOUNDRY_STANDALONE=0)", %{
    project_root: project_root
  } do
    prev_standalone = System.get_env("FOUNDRY_STANDALONE")
    prev_host = System.get_env("PHX_HOST")

    try do
      System.put_env("FOUNDRY_STANDALONE", "0")
      System.put_env("PHX_HOST", "studio.example.com")
      assert PreviewServer.preview_base_url(project_root) == "https://preview.studio.example.com"
    after
      if prev_standalone, do: System.put_env("FOUNDRY_STANDALONE", prev_standalone), else: System.delete_env("FOUNDRY_STANDALONE")
      if prev_host, do: System.put_env("PHX_HOST", prev_host), else: System.delete_env("PHX_HOST")
    end
  end

  test "cloud mode ignores manifest port and always uses default preview port (4002)", %{
    project_root: project_root
  } do
    # Regression: manifest.exs with port: 4001 caused the preview server to bind on 4001
    # in cloud mode, but Caddy is hardwired to proxy preview.* to port 4002 — causing 502.
    # In cloud mode the manifest port must be ignored; the server must always use 4002.
    prev_standalone = System.get_env("FOUNDRY_STANDALONE")
    prev_host = System.get_env("PHX_HOST")

    try do
      System.put_env("FOUNDRY_STANDALONE", "0")
      System.put_env("PHX_HOST", "studio.example.com")

      File.write!(
        Path.join(project_root, "manifest.exs"),
        """
        [preview_server: [command: "mix phx.server", port: 4001]]
        """
      )

      # build_clean_env uses state.port_num which is set during start_cast.
      # Verify cloud mode env has PORT=4002, not PORT=4001.
      state = %{env: [], port_num: PreviewServer.cloud_preview_port()}
      env = PreviewServer.build_clean_env_for_test(state)
      assert Map.get(env, "PORT") == "4002",
             "In cloud mode PORT env must be 4002 so Phoenix binds on the Caddy-proxied port"

      assert PreviewServer.cloud_preview_port() == 4002,
             "cloud_preview_port/0 must return 4002 to match Caddy config"
    after
      if prev_standalone,
        do: System.put_env("FOUNDRY_STANDALONE", prev_standalone),
        else: System.delete_env("FOUNDRY_STANDALONE")

      if prev_host,
        do: System.put_env("PHX_HOST", prev_host),
        else: System.delete_env("PHX_HOST")
    end
  end

  test "build_clean_env sets MIX_ENV=dev so preview server reuses _build/dev compiled by install_dependencies" do
    # install_dependencies compiles into _build/dev/ (MIX_ENV=dev).
    # If build_clean_env passed a different MIX_ENV, mix phx.server would find an empty
    # _build/<other>/ and trigger a full recompile on every container start.
    state = %{env: [], port_num: 4001}
    env = PreviewServer.build_clean_env_for_test(state)
    assert Map.get(env, "MIX_ENV") == "dev",
           "build_clean_env must set MIX_ENV=dev to match the _build/dev/ artifacts from install_dependencies"
  end

  test "manifest env cannot override MIX_ENV away from dev without explicit intent" do
    # A manifest with no env entries must not accidentally inherit MIX_ENV=prod
    # from the container environment, which would send mix phx.server to _build/prod/.
    old = System.get_env("MIX_ENV")

    try do
      System.put_env("MIX_ENV", "prod")
      state = %{env: [], port_num: 4001}
      env = PreviewServer.build_clean_env_for_test(state)
      assert Map.get(env, "MIX_ENV") == "dev",
             "build_clean_env must force MIX_ENV=dev even when parent process has MIX_ENV=prod"
    after
      if old, do: System.put_env("MIX_ENV", old), else: System.delete_env("MIX_ENV")
    end
  end

  test "build_clean_env strips RELEASE_* variables and release PATH entries" do
    release_root = "/fake/release"

    System.put_env("RELEASE_ROOT", release_root)
    System.put_env("RELEASE_COOKIE", "supersecret")
    original_path = System.get_env("PATH", "")
    System.put_env("PATH", "#{release_root}/erts-14.0/bin:#{release_root}/bin:/usr/bin:/bin")

    state = %{env: [], port_num: 4001}

    try do
      env = PreviewServer.build_clean_env_for_test(state)

      refute Map.has_key?(env, "RELEASE_ROOT"), "RELEASE_ROOT should be stripped"
      refute Map.has_key?(env, "RELEASE_COOKIE"), "RELEASE_COOKIE should be stripped"

      path = Map.get(env, "PATH", "")
      refute String.contains?(path, "#{release_root}/erts-14.0/bin"),
             "release erts bin should be removed from PATH"

      refute String.contains?(path, "#{release_root}/bin"),
             "release bin should be removed from PATH"

      assert String.contains?(path, "/usr/bin"), "system PATH entries should be preserved"
    after
      System.delete_env("RELEASE_ROOT")
      System.delete_env("RELEASE_COOKIE")
      System.put_env("PATH", original_path)
    end
  end

  test "captures process output and exit failures", %{project_root: project_root} do
    File.write!(
      Path.join(project_root, "manifest.exs"),
      """
      [
        preview_server: [
          command: "sh -c 'echo booting; echo fatal error 1>&2; exit 3'",
          port: 4303,
          env: []
        ]
      ]
      """
    )

    PreviewServer.start_preview(project_root)

    assert wait_for_state(:failed)
    assert {:ok, status} = PreviewServer.get_status()
    assert status.state == :failed
    assert status.last_error == "Preview server exited with status 3"
    assert status.output =~ "booting"
    assert status.output =~ "fatal error"
  end

  test "times out when process never opens preview port", %{project_root: project_root} do
    File.write!(
      Path.join(project_root, "manifest.exs"),
      """
      [
        preview_server: [
          command: "sh -c 'echo waiting; sleep 11'",
          port: 4404,
          env: []
        ]
      ]
      """
    )

    PreviewServer.start_preview(project_root)

    assert wait_for_last_error(
             "Preview HTTP port 4404 did not open within 10000ms after the last process output. No explicit error was emitted. Last log line: waiting",
             500
           )

    assert {:ok, status} = PreviewServer.get_status()
    assert status.state == :failed
    assert status.output =~ "waiting"
  end

  test "preserves full output history across split port chunks", %{project_root: project_root} do
    File.write!(
      Path.join(project_root, "manifest.exs"),
      """
      [
        preview_server: [
          command: "sh -c 'printf first; sleep 1; echo second; echo third; sleep 11'",
          port: 4450,
          env: []
        ]
      ]
      """
    )

    PreviewServer.start_preview(project_root)

    assert wait_for_output("firstsecond\nthird\n", 400)
    assert {:ok, status} = PreviewServer.get_status()
    assert status.output =~ "firstsecond\nthird\n"
  end

  test "fails fast when build directory lock is detected", %{project_root: project_root} do
    File.write!(
      Path.join(project_root, "manifest.exs"),
      """
      [
        preview_server: [
          command: "sh -c 'echo Waiting for lock on the build directory \\(held by process 12939\\); sleep 11'",
          port: 4505,
          env: []
        ]
      ]
      """
    )

    PreviewServer.start_preview(project_root)

    assert wait_for_last_error(
             "Preview build is blocked by another Mix process holding the build lock (PID 12939).",
             200
           )

    assert {:ok, status} = PreviewServer.get_status()
    assert status.state == :failed
    assert status.output =~ "Waiting for lock on the build directory"
  end

  test "marks a clean early exit as failed when the HTTP port never opened", %{
    project_root: project_root
  } do
    File.write!(
      Path.join(project_root, "manifest.exs"),
      """
      [
        preview_server: [
          command: "sh -c 'echo finished; exit 0'",
          port: 4606,
          env: []
        ]
      ]
      """
    )

    PreviewServer.start_preview(project_root)

    assert wait_for_state(:failed)
    assert {:ok, status} = PreviewServer.get_status()
    assert status.state == :failed
    assert status.last_error == "Preview process exited before opening the HTTP port."
    assert status.output =~ "finished"
  end

  test "stop_preview terminates a long-running preview command and returns to idle", %{
    project_root: project_root
  } do
    File.write!(
      Path.join(project_root, "manifest.exs"),
      """
      [
        preview_server: [
          command: "sh -c 'echo booted; sleep 30'",
          port: 4707,
          env: []
        ]
      ]
      """
    )

    PreviewServer.start_preview(project_root)

    assert wait_for_output("booted\n", 100)
    PreviewServer.stop_preview()

    assert wait_for_state(:idle, 120)
    assert {:ok, status} = PreviewServer.get_status()
    assert status.state == :idle
    assert status.last_error == nil
  end

  test "cloud mode E2E: server process binds on 4002 even when manifest specifies port 4001", %{
    project_root: project_root
  } do
    # End-to-end regression for the cloud 502 bug:
    # manifest.exs declares port: 4001, but in cloud mode Caddy proxies to :4002.
    # Verify that start_preview respects cloud mode and the process actually opens 4002.
    prev_standalone = System.get_env("FOUNDRY_STANDALONE")
    prev_host = System.get_env("PHX_HOST")

    try do
      System.put_env("FOUNDRY_STANDALONE", "0")
      System.put_env("PHX_HOST", "studio.example.com")

      # Simulate a project whose manifest hardcodes port 4001 (like foundry-igaming).
      # The server command listens on $PORT — preview_server sets PORT=4002 in cloud mode.
      File.write!(
        Path.join(project_root, "manifest.exs"),
        """
        [preview_server: [command: "sh -c 'nc -l 0.0.0.0 $PORT'", port: 4001, env: []]]
        """
      )

      PreviewServer.start_preview(project_root)

      # Wait for running state — means :gen_tcp.connect to 4002 succeeded.
      assert wait_for_state(:running, 80),
             "Preview server did not reach :running state within 20s in cloud mode"

      assert {:ok, status} = PreviewServer.get_status()
      assert status.state == :running
      assert status.port == 4002, "Expected port 4002 in cloud mode, got #{status.port}"
    after
      if prev_standalone,
        do: System.put_env("FOUNDRY_STANDALONE", prev_standalone),
        else: System.delete_env("FOUNDRY_STANDALONE")

      if prev_host,
        do: System.put_env("PHX_HOST", prev_host),
        else: System.delete_env("PHX_HOST")
    end
  end

  defp wait_for_state(expected_state, attempts_left \\ 40)

  defp wait_for_state(_expected_state, 0), do: false

  defp wait_for_state(expected_state, attempts_left) do
    case PreviewServer.get_status() do
      {:ok, %{state: ^expected_state}} ->
        true

      _ ->
        Process.sleep(25)
        wait_for_state(expected_state, attempts_left - 1)
    end
  end

  defp wait_for_last_error(_expected_error, 0), do: false

  defp wait_for_last_error(expected_error, attempts_left) do
    case PreviewServer.get_status() do
      {:ok, %{last_error: ^expected_error}} ->
        true

      _ ->
        Process.sleep(25)
        wait_for_last_error(expected_error, attempts_left - 1)
    end
  end

  defp wait_for_output(_expected_output, 0), do: false

  defp wait_for_output(expected_output, attempts_left) do
    case PreviewServer.get_status() do
      {:ok, %{output: output}} ->
        if is_binary(output) and String.contains?(output, expected_output) do
          true
        else
          Process.sleep(25)
          wait_for_output(expected_output, attempts_left - 1)
        end

      _ ->
        Process.sleep(25)
        wait_for_output(expected_output, attempts_left - 1)
    end
  end
end

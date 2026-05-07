defmodule Foundry.PreviewServerTest do
  use ExUnit.Case, async: false

  alias Foundry.PreviewServer

  setup do
    Application.ensure_all_started(:foundry)
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

  test "starts preview process when manifest env entries are charlists", %{project_root: project_root} do
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

  test "marks a clean early exit as failed when the HTTP port never opened", %{project_root: project_root} do
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

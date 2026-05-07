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

  test "starts preview when manifest env entries are charlists", %{project_root: project_root} do
    File.write!(
      Path.join(project_root, "manifest.exs"),
      """
      [
        preview_server: [
          command: "cat",
          env: [{~c"MIX_ENV", ~c"dev"}],
          port: 4101
        ]
      ]
      """
    )

    PreviewServer.start_preview(project_root)

    assert wait_for_state(:running)
    assert {:ok, status} = PreviewServer.get_status()
    assert status.state == :running
    assert status.port == 4101
    assert status.project_root == project_root
    assert status.url == "http://localhost:4101"
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
end

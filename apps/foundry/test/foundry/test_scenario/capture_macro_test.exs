defmodule Foundry.TestScenario.CaptureMacroTest do
  use ExUnit.Case, async: false

  use Foundry.TestScenario

  describe "capture/1" do
    test "derives scenario metadata from the caller and writes the trace" do
      project_root = tmp_project_root()

      in_project_root(project_root, fn ->
        capture do
          send(self(), {:foundry_ash_event, %{node_id: "Demo.Page", action_kind: :entry}})
        end

        [trace_path] = trace_files(project_root)
        payload = decode_trace!(trace_path)

        assert payload["source_module"] == "Foundry.TestScenario.CaptureMacroTest"
        assert payload["describe_name"] == "capture/1"

        assert payload["test_name"] ==
                 "derives scenario metadata from the caller and writes the trace"

        assert payload["file"] =~ "capture_macro_test.exs"
        assert payload["line"] > 0

        assert payload["events"] == [
                 %{
                   "action_kind" => "entry",
                   "focus_node_id" => "Demo.Page",
                   "node_id" => "Demo.Page",
                   "provenance" => "executed",
                   "sequence" => 1,
                   "status" => "passed"
                 }
               ]
      end)
    end
  end

  defp tmp_project_root do
    path =
      Path.join(
        System.tmp_dir!(),
        "foundry_capture_macro_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf(path)
    File.mkdir_p!(path)
    path
  end

  defp in_project_root(project_root, fun) do
    original_cwd = File.cwd!()

    try do
      File.cd!(project_root)
      fun.()
    after
      File.cd!(original_cwd)
    end
  end

  defp trace_files(project_root) do
    Path.join([project_root, ".foundry", "scenario_traces", "*.json"])
    |> Path.wildcard()
  end

  defp decode_trace!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end
end

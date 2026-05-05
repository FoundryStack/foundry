defmodule Foundry.TestScenario.RuntimeCaptureTest do
  use ExUnit.Case, async: false

  alias Foundry.TestScenario.RuntimeCapture

  describe "capture/2" do
    test "preserves event order for large traces and writes one deterministic artifact" do
      project_root = tmp_project_root()
      context = scenario_context("large trace order")

      in_project_root(project_root, fn ->
        RuntimeCapture.capture(context, fn ->
          Enum.each(1..2_000, fn index ->
            RuntimeCapture.trace_node("Demo.Flow", %{
              kind: :action_execute,
              details: "event:#{index}"
            })
          end)
        end)

        [trace_path] = trace_files(project_root)
        payload = decode_trace!(trace_path)
        events = payload["events"]

        assert length(events) == 2_000
        assert hd(events)["sequence"] == 1
        assert hd(events)["details"] == "event:1"
        assert List.last(events)["sequence"] == 2_000
        assert List.last(events)["details"] == "event:2000"
      end)
    end

    test "replaces repeated captures for the same scenario without accumulating files" do
      project_root = tmp_project_root()
      context = scenario_context("deterministic replacement")

      in_project_root(project_root, fn ->
        RuntimeCapture.capture(context, fn ->
          RuntimeCapture.trace_node("Demo.Flow", %{details: "first"})
        end)

        RuntimeCapture.capture(context, fn ->
          RuntimeCapture.trace_node("Demo.Flow", %{details: "second"})
        end)

        [trace_path] = trace_files(project_root)
        payload = decode_trace!(trace_path)

        assert Enum.map(payload["events"], & &1["details"]) == ["second"]
      end)
    end

    test "restores outer capture state after nested capture blocks" do
      project_root = tmp_project_root()
      outer_context = scenario_context("outer capture", describe: "Outer capture")
      inner_context = scenario_context("inner capture", describe: "Inner capture", line: 22)

      in_project_root(project_root, fn ->
        RuntimeCapture.capture(outer_context, fn ->
          RuntimeCapture.trace_node("Demo.Outer", %{details: "outer:before"})

          RuntimeCapture.capture(inner_context, fn ->
            RuntimeCapture.trace_node("Demo.Inner", %{details: "inner"})
          end)

          RuntimeCapture.trace_node("Demo.Outer", %{details: "outer:after"})
        end)

        traces =
          trace_files(project_root)
          |> Enum.map(&decode_trace!/1)
          |> Enum.sort_by(& &1["scenario_id"])

        assert Enum.map(traces, & &1["scenario_id"]) == [
                 "Demo.RuntimeCaptureTest.inner_capture",
                 "Demo.RuntimeCaptureTest.outer_capture"
               ]

        assert Enum.map(Enum.at(traces, 0)["events"], & &1["details"]) == ["inner"]

        assert Enum.map(Enum.at(traces, 1)["events"], & &1["details"]) == [
                 "outer:before",
                 "outer:after"
               ]
      end)
    end

    test "does not leak trace state after exceptions" do
      project_root = tmp_project_root()
      failing_context = scenario_context("failing capture", describe: "Failing capture")

      recovery_context =
        scenario_context("recovery capture", describe: "Recovery capture", line: 33)

      in_project_root(project_root, fn ->
        assert_raise RuntimeError, "boom", fn ->
          RuntimeCapture.capture(failing_context, fn ->
            RuntimeCapture.trace_node("Demo.Failure", %{details: "before crash"})
            raise "boom"
          end)
        end

        RuntimeCapture.trace_node("Demo.Orphan", %{details: "outside capture"})

        RuntimeCapture.capture(recovery_context, fn ->
          RuntimeCapture.trace_node("Demo.Recovery", %{details: "after crash"})
        end)

        traces =
          trace_files(project_root)
          |> Enum.map(&decode_trace!/1)
          |> Enum.sort_by(& &1["scenario_id"])

        assert Enum.map(traces, & &1["scenario_id"]) == [
                 "Demo.RuntimeCaptureTest.failing_capture",
                 "Demo.RuntimeCaptureTest.recovery_capture"
               ]

        assert Enum.map(Enum.at(traces, 0)["events"], & &1["details"]) == ["before crash"]
        assert Enum.map(Enum.at(traces, 1)["events"], & &1["details"]) == ["after crash"]
      end)
    end
  end

  defp scenario_context(test_name, opts \\ []) do
    %{
      module: Demo.RuntimeCaptureTest,
      describe: Keyword.get(opts, :describe, "Runtime capture"),
      test: test_name,
      file: "test/runtime_capture_test.exs",
      line: Keyword.get(opts, :line, 11)
    }
  end

  defp tmp_project_root do
    path =
      Path.join(
        System.tmp_dir!(),
        "foundry_runtime_capture_#{System.unique_integer([:positive, :monotonic])}"
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

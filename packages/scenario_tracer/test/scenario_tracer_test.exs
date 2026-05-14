defmodule ScenarioTracerTest do
  use ExUnit.Case, async: true

  alias ExTracer.{Lookup, Step}
  alias ScenarioTracer.MixTask
  alias ScenarioTracer.TraceStore.JsonFile

  defmodule MockAdapter do
    @behaviour ExTracer.Adapter

    @impl true
    def expand_step(step, _lookup), do: [Map.put(step, :label, "#{step.label} expanded")]

    @impl true
    def classify_call(module_ast, :run, _args, alias_map, _lookup, opts) do
      module_name = expand_alias(module_ast, alias_map)

      if module_name == "Demo.Thing" do
        Step.new(%{
          type: :entry,
          kind: :action_execute,
          provenance: :executed,
          status: :passed,
          label: "Run thing",
          node_id: "Demo.Thing",
          focus_node_id: "Demo.Thing",
          line: opts[:line],
          test_name: opts[:test_name],
          test_kind: opts[:test_kind]
        })
      end
    end

    def classify_call(_module_ast, _fun, _args, _alias_map, _lookup, _opts), do: nil

    defp expand_alias({:__aliases__, _, parts}, alias_map) do
      short = Enum.join(parts, ".")
      Map.get(alias_map, short, short)
    end

    defp expand_alias(other, _alias_map), do: to_string(other)
  end

  defmodule MockTask do
    @behaviour ScenarioTracer.MixTask

    @impl true
    def project_root, do: Process.get(:scenario_tracer_project_root)

    @impl true
    def adapters, do: [ScenarioTracerTest.MockAdapter]

    @impl true
    def lookup_builder(_root, nodes, runtime) do
      %Lookup{
        by_id: Map.new(nodes, &{&1.id, &1}),
        aliases: %{"Thing" => "Demo.Thing"},
        runtime: runtime
      }
    end

    @impl true
    def node_source(_root), do: [%{id: "Demo.Thing", type: "resource"}]

    @impl true
    def trace_dir(root), do: Path.join(root, "traces")

    @impl true
    def frameworks, do: [ScenarioTracer.TestFrameworks.ExUnit]
  end

  setup do
    root = Path.join(System.tmp_dir!(), "scenario_tracer_#{System.unique_integer([:positive])}")
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "test"))
    Process.put(:scenario_tracer_project_root, root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "json trace store loads and sorts traces by capture time", %{root: root} do
    trace_dir = Path.join(root, "traces")
    File.mkdir_p!(trace_dir)

    older = %{
      scenario_id: "Demo.Sample.flow",
      test_name: "test old",
      captured_at: "2026-01-01T00:00:00Z",
      duration_ms: 5
    }

    newer = %{
      scenario_id: "Demo.Sample.flow",
      test_name: "property new",
      captured_at: "2026-01-02T00:00:00Z",
      duration_ms: 10
    }

    File.write!(Path.join(trace_dir, "older.json"), Jason.encode!(older))
    File.write!(Path.join(trace_dir, "newer.json"), Jason.encode!(newer))

    loaded = JsonFile.load(%{trace_dir: trace_dir})

    assert [%ExTracer.RuntimeTrace{test_name: "property new"}, %ExTracer.RuntimeTrace{test_name: "test old"}] =
             loaded["Demo.Sample.flow"]

    assert JsonFile.match(hd(loaded["Demo.Sample.flow"]), "new")
  end

  test "json trace collector writes one test payload per flush", %{root: root} do
    trace_dir = Path.join(root, "traces")
    {:ok, state} = ScenarioTracer.TraceCollector.JsonFile.start(%{trace_dir: trace_dir})

    :ok =
      ScenarioTracer.TraceCollector.JsonFile.record(state, %{
        scenario_id: "Demo.Sample.flow",
        test_name: "runs",
        captured_at: "2026-01-01T00:00:00Z"
      })

    :ok = ScenarioTracer.TraceCollector.JsonFile.flush(state)

    [path] = Path.wildcard(Path.join(trace_dir, "*.json"))
    assert File.exists?(path)
    assert {:ok, %{"scenario_id" => "Demo.Sample.flow", "events" => [%{"test_name" => "runs"}]}} = Jason.decode(File.read!(path))
  end

  test "mix task builds scenarios, coverage, performance, and reverse node index", %{root: root} do
    File.write!(
      Path.join(root, "test/demo_sample_test.exs"),
      """
      defmodule Demo.SampleTest do
        use ExUnit.Case, async: true

        alias Demo.Thing

        describe "happy path" do
          @scenario category: :compliance, compliance_links: ["RG-001"], tags: [:critical]

          test "runs thing" do
            Thing.run(:ok)
          end
        end
      end
      """
    )

    File.mkdir_p!(Path.join(root, "traces"))

    File.write!(
      Path.join(root, "traces/runtime.json"),
      Jason.encode!(%{
        scenario_id: "Demo.SampleTest.happy_path",
        test_name: "test runs thing",
        captured_at: "2026-01-02T00:00:00Z",
        duration_ms: 12,
        outcome: "passed"
      })
    )

    report = MixTask.run(MockTask, [:static_only])

    assert [%ExTracer.Scenario{} = scenario] = report.scenarios
    assert scenario.id == "Demo.SampleTest.happy_path"
    assert scenario.category == :compliance
    assert scenario.compliance_links == ["RG-001"]
    assert scenario.tags == [:critical]
    assert scenario.nodes == ["Demo.Thing"]
    assert scenario.graph_path == ["Demo.Thing"]

    assert report.coverage.total_nodes == 1
    assert report.coverage.covered_nodes == 1
    assert report.coverage.uncovered_node_ids == []
    assert report.node_index == %{"Demo.Thing" => ["Demo.SampleTest.happy_path"]}

    assert report.performance.total_test_duration_ms == 12
    assert {"Demo.SampleTest.happy_path", "test runs thing", 12} = hd(report.performance.slowest_tests)
  end

  test "static_only parses scenario tests without executing their bodies", %{root: root} do
    File.write!(
      Path.join(root, "test/demo_nonexecuted_test.exs"),
      """
      defmodule Demo.NonexecutedTest do
        use ExUnit.Case, async: true

        alias Demo.Thing

        describe "static only" do
          test "is discovered without being run" do
            raise "should not execute during static extraction"
            Thing.run(:ok)
          end
        end
      end
      """
    )

    report = MixTask.run(MockTask, [:static_only])

    assert Enum.any?(report.scenarios, &(&1.id == "Demo.NonexecutedTest.static_only"))
  end
end

defmodule ScenarioTracer do
  @moduledoc """
  Ready-to-use ExUnit and JSON-backed scenario tracing on top of `ExTracer`.

  ScenarioTracer wires together AST scanning, runtime trace collection, and report
  generation into a single Mix task abstraction. It captures test outcomes at runtime
  via an ExUnit formatter, stores them as JSON files, and re-plays them during
  extraction to produce living, coverage-annotated scenario documentation.

  ## Key modules

  - `ScenarioTracer.MixTask` — behaviour for building project-specific trace pipelines
  - `ScenarioTracer.ExUnitFormatter` — ExUnit event handler that records test outcomes
  - `ScenarioTracer.TraceCollector.JsonFile` — writes trace events to JSON files
  - `ScenarioTracer.TraceStore.JsonFile` — loads and indexes JSON trace files
  - `ScenarioTracer.TestFrameworks.ExUnit` — ExUnit block pattern definitions
  - `ScenarioTracer.TestFrameworks.StreamData` — StreamData property pattern definitions

  ## Quick example

  Add the formatter in `test/test_helper.exs`:

      ExUnit.configure(
        formatters: [ExUnit.CLIFormatter, ScenarioTracer.ExUnitFormatter],
        trace_dir: Path.join(File.cwd!(), "traces")
      )

  Implement a Mix task:

      defmodule Mix.Tasks.Scenarios.Extract do
        use Mix.Task
        @behaviour ScenarioTracer.MixTask

        def project_root, do: File.cwd!()
        def adapters, do: [MyApp.Tracer.ResourceAdapter]
        def frameworks, do: [ScenarioTracer.TestFrameworks.ExUnit]
        def trace_dir(root), do: Path.join(root, "traces")
        def node_source(root), do: MyApp.Tracer.NodeBuilder.build(root)
        def lookup_builder(root, nodes, runtime) do
          %ExTracer.Lookup{by_id: Map.new(nodes, &{&1.id, &1}), runtime: runtime}
        end

        def run(_args) do
          report = ScenarioTracer.MixTask.run(__MODULE__)
          IO.puts("Extracted \#{length(report.scenarios)} scenarios")
        end
      end

  See the [README](https://hexdocs.pm/scenario_tracer) for full usage.
  """
end

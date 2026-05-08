defmodule Mix.Tasks.Foundry.Scenarios.Extract do
  use Mix.Task

  alias Foundry.Context.GraphBuilder
  alias Foundry.Context.ScenarioCache
  alias Foundry.Context.Scenarios.Adapters
  alias Foundry.Context.Scenarios.ModuleIndex

  @shortdoc "Run tests with tracing and extract scenario data for Foundry UI"

  def run(args) do
    report = ScenarioTracer.MixTask.run(__MODULE__, args)
    ScenarioCache.update(report)
    report
  end

  def project_root, do: File.cwd!()

  def adapters do
    [
      Adapters.Page,
      Adapters.Rule,
      Adapters.Reactor,
      Adapters.Trigger,
      Adapters.Oban,
      Adapters.Ash
    ]
  end

  def lookup_builder(root, nodes, runtime), do: ModuleIndex.build(nodes, root, runtime)
  def node_source(root) do
    with {:ok, manifest} <- Foundry.Manifest.Parser.read(root) do
      {nodes, _edges} = GraphBuilder.build(root, manifest)
      nodes
    else
      _ -> []
    end
  end
  def trace_dir(root), do: Path.join(root, ".foundry/scenario_traces")

  def frameworks do
    [ScenarioTracer.TestFrameworks.ExUnit, ScenarioTracer.TestFrameworks.StreamData]
  end
end

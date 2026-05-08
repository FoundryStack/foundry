defmodule Foundry.Context.ScenarioExtractor do
  @moduledoc """
  Extracts Studio scenarios from executable test source.

  Real test and property bodies are the source of truth. `@scenario` metadata is
  optional and may refine category, compliance links, labels, or graph focus for
  traced steps, but it never creates a scenario on its own.
  """

  def extract(project_root, nodes) do
    task_module = build_task_module(project_root, nodes)

    try do
      task_module
      |> ScenarioTracer.MixTask.run([:static_only])
      |> Map.get(:scenarios, [])
    after
      :code.purge(task_module)
      :code.delete(task_module)
    end
  end

  defp build_task_module(project_root, nodes) do
    module = Module.concat(__MODULE__, "Task#{System.unique_integer([:positive, :monotonic])}")

    quoted =
      quote do
        @behaviour ScenarioTracer.MixTask

        @impl true
        def project_root, do: unquote(project_root)

        @impl true
        def adapters do
          [
            Foundry.Context.Scenarios.Adapters.Page,
            Foundry.Context.Scenarios.Adapters.Rule,
            Foundry.Context.Scenarios.Adapters.Reactor,
            Foundry.Context.Scenarios.Adapters.Trigger,
            Foundry.Context.Scenarios.Adapters.Oban,
            Foundry.Context.Scenarios.Adapters.Ash
          ]
        end

        @impl true
        def lookup_builder(root, nodes, runtime),
          do: Foundry.Context.Scenarios.ModuleIndex.build(nodes, root, runtime)

        @impl true
        def node_source(_root), do: unquote(Macro.escape(nodes))

        @impl true
        def trace_dir(root), do: Path.join(root, ".foundry/scenario_traces")

        @impl true
        def frameworks do
          [ScenarioTracer.TestFrameworks.ExUnit, ScenarioTracer.TestFrameworks.StreamData]
        end
      end

    {:module, ^module, _, _} = Module.create(module, quoted, Macro.Env.location(__ENV__))
    module
  end
end

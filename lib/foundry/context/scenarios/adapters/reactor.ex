defmodule Foundry.Context.Scenarios.Adapters.Reactor do
  @moduledoc false

  @behaviour ExTracer.Adapter

  alias ExTracer.FlowExpander
  alias ExTracer.FlowSummary
  alias Foundry.Context.Scenarios.ModuleIndex

  @impl true
  def expand_step(step, lookup) do
    case Map.get(lookup.by_id, step.node_id || "") do
      %{type: type} = node when type in ["transfer", "reactor"] ->
        if String.ends_with?(step.module_function || "", ".run") do
          expand_pipeline_step(step, node)
        else
          []
        end

      _ ->
        []
    end
  end

  @impl true
  def classify_call(module_ast, fun, args, alias_map, lookup, opts) do
    Foundry.Context.Scenarios.CallClassifier.classify_ast_call(
      module_ast,
      fun,
      args,
      alias_map,
      lookup,
      opts
    )
  end

  @impl true
  def focus_for_helper(_module_name, _helper_name, _lookup), do: nil

  defp expand_pipeline_step(step, node) do
    steps = Map.get(node, :steps, [])

    Enum.map(steps, fn pipeline_step ->
      focus_node_id =
        ModuleIndex.resolve_pipeline_focus(node.id, pipeline_step, node.type) || node.id

      FlowSummary.expanded_step(step, %{
        type: :reaction,
        kind: ModuleIndex.pipeline_step_kind(pipeline_step),
        status: FlowSummary.normalized_status(step, :potential),
        label:
          ModuleIndex.pipeline_step_label(
            node.id,
            pipeline_step,
            Map.get(pipeline_step, :description) || Map.get(pipeline_step, "description")
          ),
        node_id: ModuleIndex.pipeline_step_target_node_id(node.id, pipeline_step) || node.id,
        focus_node_id: focus_node_id,
        details: ModuleIndex.pipeline_step_description(pipeline_step),
        source_snippet: ModuleIndex.pipeline_step_snippet(pipeline_step)
      })
    end) ++ FlowExpander.maybe_assert_result_step(step)
  end
end

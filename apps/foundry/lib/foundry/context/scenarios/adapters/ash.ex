defmodule Foundry.Context.Scenarios.Adapters.Ash do
  @moduledoc false

  @behaviour ExTracer.Adapter

  alias ExTracer.FlowExpander
  alias ExTracer.FlowSummary
  alias Foundry.Context.Scenarios.ModuleIndex

  @impl true
  def expand_step(step, lookup) do
    case Map.get(lookup.by_id, step.node_id || "") do
      %{type: "resource"} = node -> expand_resource_step(step, node)
      _ -> []
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

  defp expand_resource_step(step, node) do
    case {step.kind, step.action} do
      {:action_execute, action} when is_binary(action) ->
        case ModuleIndex.find_action(node, action) do
          nil ->
            FlowExpander.maybe_assert_result_step(step)

          action_entry ->
            [
              FlowSummary.expanded_step(step, %{
                type: :reaction,
                kind: :action_execute,
                status: FlowSummary.normalized_status(step, :passed),
                label: "Execute #{List.last(String.split(node.id, "."))}.#{action}",
                details:
                  Map.get(action_entry, :description) || Map.get(action_entry, "description"),
                source_snippet:
                  Map.get(action_entry, :description) || Map.get(action_entry, "description"),
                focus_node_id: step.focus_node_id || step.node_id
              })
              | FlowExpander.maybe_assert_result_step(step)
            ]
        end

      {:action_prepare, _action} ->
        FlowExpander.maybe_assert_result_step(step)

      _ ->
        []
    end
  end
end

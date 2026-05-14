defmodule ExTracer.RuntimeNormalizer do
  @moduledoc false

  alias ExTracer.{ActionSemantics, FlowExpander, FlowSummary, RuntimeTrace, Utils}
  def normalize(nil, _test_case, _lookup, _adapters), do: []

  def normalize(%RuntimeTrace{} = runtime_trace, test_case, lookup, adapters) do
    steps =
      runtime_trace.events
      |> Enum.sort_by(&Map.get(&1, "sequence", 0))
      |> Enum.map(fn event ->
        node_id = ActionSemantics.canonical_graph_node_id(Map.get(event, "node_id"))
        action = infer_runtime_action(event, node_id, lookup)

        focus_node_id =
          ActionSemantics.infer_focus_node_id(
            Map.get(event, "focus_node_id"),
            node_id,
            action,
            lookup
          )

        FlowSummary.build_step(%{
          type: ActionSemantics.normalize_atom(Map.get(event, "type"), :reaction),
          kind:
            ActionSemantics.normalize_atom(
              Map.get(event, "action_kind") || Map.get(event, "kind"),
              :observation
            ),
          label: Map.get(event, "label") || runtime_label(event),
          node_id: node_id,
          focus_node_id: focus_node_id,
          focus_targets:
            event
            |> Map.get("focus_targets")
            |> Utils.normalize_string_list()
            |> Enum.map(&ActionSemantics.canonical_graph_node_id/1),
          emits: Utils.normalize_string_list(Map.get(event, "emits")),
          reacts_to: Map.get(event, "reacts_to"),
          action: action,
          actor: Map.get(event, "actor"),
          provenance: :executed,
          status: ActionSemantics.normalize_atom(Map.get(event, "status"), :passed),
          module_function: Map.get(event, "module_function"),
          source_snippet: Map.get(event, "source_snippet"),
          result: Utils.normalize_optional_string(Map.get(event, "result")),
          details: Utils.normalize_optional_string(Map.get(event, "details")),
          line: Map.get(event, "line") || test_case.line,
          test_name: test_case.name,
          test_kind: test_case.kind,
          capture_origin: Utils.normalize_optional_string(Map.get(event, "capture_origin"))
        })
      end)

    steps
    |> FlowExpander.maybe_expand_automatic_runtime_steps(lookup, adapters)
    |> FlowSummary.collapse_duplicate_runtime_steps()
  end

  defp runtime_label(event) do
    case Map.get(event, "action") do
      nil ->
        "Execute #{List.last(String.split(Map.get(event, "node_id") || "node", "."))}"

      action ->
        "Execute #{List.last(String.split(Map.get(event, "node_id") || "node", "."))}.#{action}"
    end
  end

  defp infer_runtime_action(event, node_id, lookup) do
    ActionSemantics.infer_action(
      node_id,
      Map.get(event, "action"),
      Map.get(event, "action_kind") || Map.get(event, "kind"),
      lookup
    )
  end
end

defmodule ExTracer.RuntimeNormalizer do
  @moduledoc false

  alias ExTracer.{FlowExpander, FlowSummary, RuntimeTrace, Utils}
  def normalize(nil, _test_case, _lookup, _adapters), do: []

  def normalize(%RuntimeTrace{} = runtime_trace, test_case, lookup, adapters) do
    steps =
      runtime_trace.events
      |> Enum.sort_by(&Map.get(&1, "sequence", 0))
      |> Enum.map(fn event ->
        node_id = canonical_graph_node_id(Map.get(event, "node_id"))
        action = infer_runtime_action(event, node_id, lookup)
        focus_node_id = infer_focus_node_id(event, node_id, action, lookup)

        FlowSummary.build_step(%{
          type: normalize_runtime_atom(Map.get(event, "type"), :reaction),
          kind: normalize_runtime_atom(Map.get(event, "action_kind") || Map.get(event, "kind"), :observation),
          label: Map.get(event, "label") || runtime_label(event),
          node_id: node_id,
          focus_node_id: focus_node_id,
          focus_targets:
            event
            |> Map.get("focus_targets")
            |> Utils.normalize_string_list()
            |> Enum.map(&canonical_graph_node_id/1),
          emits: Utils.normalize_string_list(Map.get(event, "emits")),
          reacts_to: Map.get(event, "reacts_to"),
          action: action,
          actor: Map.get(event, "actor"),
          provenance: :executed,
          status: normalize_runtime_atom(Map.get(event, "status"), :passed),
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

  def normalize_runtime_atom(nil, default), do: default
  def normalize_runtime_atom(value, _default) when is_atom(value), do: value

  def normalize_runtime_atom(value, default) when is_binary(value) do
    case value do
      "entry" -> :entry
      "reaction" -> :reaction
      "assertion" -> :assertion
      "observation" -> :observation
      "command" -> :command
      "event" -> :event
      "job" -> :job
      "action_prepare" -> :action_prepare
      "action_execute" -> :action_execute
      "trigger_receive" -> :trigger_receive
      "job_enqueue" -> :job_enqueue
      "job_execute" -> :job_execute
      "read" -> :read
      "create" -> :create
      "update" -> :update
      "destroy" -> :destroy
      "write" -> :write
      "rule_check" -> :rule_check
      "assert_result" -> :assert_result
      "passed" -> :passed
      "failed" -> :failed
      "short_circuit" -> :short_circuit
      "matched" -> :matched
      _ -> default
    end
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
    case Utils.normalize_optional_string(Map.get(event, "action")) do
      nil -> infer_action_from_kind(Map.get(event, "action_kind") || Map.get(event, "kind"), node_id, lookup)
      action -> action
    end
  end

  defp infer_action_from_kind(kind, node_id, lookup) when is_binary(node_id) do
    action_type =
      kind
      |> normalize_runtime_atom(nil)
      |> case do
        :create -> "create"
        :update -> "update"
        :destroy -> "destroy"
        :read -> "read"
        :write -> "create"
        _ -> nil
      end

    infer_action_name(node_id, action_type, lookup)
  end

  defp infer_action_from_kind(_kind, _node_id, _lookup), do: nil

  defp infer_focus_node_id(event, node_id, action, lookup) do
    event
    |> Map.get("focus_node_id")
    |> canonical_graph_node_id()
    |> case do
      nil -> focus_from_action(node_id, action, lookup)
      focus -> focus_from_existing(focus, node_id, action, lookup)
    end
  end

  defp focus_from_existing(focus, node_id, action, lookup) do
    cond do
      String.contains?(focus, ":action:") ->
        focus

      action ->
        focus_from_action(node_id || focus, action, lookup)

      true ->
        focus
    end
  end

  defp focus_from_action(nil, _action, _lookup), do: nil
  defp focus_from_action(node_id, nil, _lookup), do: node_id

  defp focus_from_action(node_id, action, lookup) do
    build_action_focus(node_id, action, lookup) || "#{node_id}:action:#{action}"
  end

  defp infer_action_name(node_id, action_type, lookup) do
    with %{actions: actions} when is_list(actions) <- Map.get(lookup.by_id, node_id),
         normalized_type when is_binary(normalized_type) <- action_type do
      actions
      |> Enum.filter(fn action ->
        action
        |> Map.get(:type)
        |> Utils.normalize_name() == normalized_type
      end)
      |> case do
        [%{name: name}] -> to_string(name)
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  defp canonical_graph_node_id(nil), do: nil

  defp canonical_graph_node_id(graph_id) do
    graph_id = Utils.stringify(graph_id)

    cond do
      String.contains?(graph_id, ":action:") ->
        [base, action] = String.split(graph_id, ":action:", parts: 2)
        canonical_graph_node_id(base) <> ":action:" <> action

      String.contains?(graph_id, ":step:") ->
        [base, step] = String.split(graph_id, ":step:", parts: 2)
        canonical_graph_node_id(base) <> ":step:" <> step

      true ->
        String.replace_suffix(graph_id, ".Version", "")
    end
  end

  defp build_action_focus(node_id, action_name, lookup) do
    with %{actions: actions} when is_list(actions) <- Map.get(lookup.by_id, node_id),
         normalized_action when is_binary(normalized_action) <- Utils.normalize_name(action_name),
         true <- Enum.any?(actions, &(Utils.normalize_name(Map.get(&1, :name)) == normalized_action)) do
      "#{node_id}:action:#{action_name}"
    else
      _ -> nil
    end
  end
end

defmodule ExTracer.RuntimeNormalizer do
  @moduledoc false

  alias ExTracer.{FlowExpander, FlowSummary, RuntimeTrace, Utils}

  def normalize(nil, _test_case, _lookup, _adapters), do: []

  def normalize(%RuntimeTrace{} = runtime_trace, test_case, lookup, adapters) do
    steps =
      runtime_trace.events
      |> Enum.sort_by(&Map.get(&1, "sequence", 0))
      |> Enum.map(fn event ->
        FlowSummary.build_step(%{
          type: normalize_runtime_atom(Map.get(event, "type"), :reaction),
          kind: normalize_runtime_atom(Map.get(event, "action_kind") || Map.get(event, "kind"), :observation),
          label: Map.get(event, "label") || runtime_label(event),
          node_id: Map.get(event, "node_id"),
          focus_node_id: Map.get(event, "focus_node_id") || Map.get(event, "node_id"),
          focus_targets: Utils.normalize_string_list(Map.get(event, "focus_targets")),
          emits: Utils.normalize_string_list(Map.get(event, "emits")),
          reacts_to: Map.get(event, "reacts_to"),
          action: Map.get(event, "action"),
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
end

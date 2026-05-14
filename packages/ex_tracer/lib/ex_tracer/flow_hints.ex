defmodule ExTracer.FlowHints do
  @moduledoc false

  alias ExTracer.ModuleIndex
  alias ExTracer.Utils

  def merge_flow_hints(flow, []), do: flow

  def merge_flow_hints(flow, hints) do
    flow
    |> Enum.with_index()
    |> Enum.map(fn {step, index} ->
      case Enum.at(hints, index) do
        nil -> step
        hint -> merge_flow_hint(step, hint)
      end
    end)
  end

  def normalize_flow_hints(nil, _lookup), do: []
  def normalize_flow_hints(flow, _lookup) when flow in [%{}, []], do: []

  def normalize_flow_hints(flow, lookup) when is_list(flow) do
    flow
    |> Enum.with_index()
    |> Enum.map(fn {step, index} -> normalize_flow_hint(step, index, lookup) end)
    |> Enum.reject(&is_nil/1)
  end

  def normalize_flow_hints(_flow, _lookup), do: []

  def infer_flow_type(0), do: :entry
  def infer_flow_type(_index), do: :reaction

  defp merge_flow_hint(step, hint) do
    base_focus_targets = Map.get(step, :focus_targets, [])
    hinted_focus_targets = Map.get(hint, :focus_targets, [])

    merged_targets =
      hinted_focus_targets
      |> Enum.reduce(base_focus_targets, fn target, acc ->
        if compatible_focus_target?(step, target), do: acc ++ [target], else: acc
      end)
      |> Enum.uniq()

    step
    |> Utils.maybe_put(:id, Map.get(hint, :id))
    |> Utils.maybe_put(:type, Map.get(hint, :type))
    |> Utils.maybe_put(:kind, Map.get(hint, :kind))
    |> Utils.maybe_put(:label, Map.get(hint, :label))
    |> Utils.maybe_put(:actor, Map.get(hint, :actor))
    |> Utils.maybe_put(:details, Map.get(hint, :details))
    |> Utils.maybe_put(:provenance, Map.get(hint, :provenance))
    |> Utils.maybe_put(:status, Map.get(hint, :status))
    |> Utils.maybe_put(:module_function, Map.get(hint, :module_function))
    |> Utils.maybe_put(:source_snippet, Map.get(hint, :source_snippet))
    |> Utils.maybe_put(:result, Map.get(hint, :result))
    |> Utils.maybe_put(:emits, Utils.non_empty_list(Map.get(hint, :emits)))
    |> Utils.maybe_put(:reacts_to, Map.get(hint, :reacts_to))
    |> Utils.maybe_put(:focus_node_id, compatible_focus(step, Map.get(hint, :focus_node_id)))
    |> Map.put(:focus_targets, merged_targets)
  end

  defp compatible_focus(step, hinted_focus) do
    if compatible_focus_target?(step, hinted_focus), do: hinted_focus, else: step.focus_node_id
  end

  defp compatible_focus_target?(_step, nil), do: false

  defp compatible_focus_target?(step, target) do
    target_base = Utils.base_node_id(target)
    step_base = Utils.base_node_id(step.node_id)
    step_focus_base = Utils.base_node_id(step.focus_node_id)

    target_base in Enum.reject(
      [step_base, step_focus_base | Enum.map(step.focus_targets, &Utils.base_node_id/1)],
      &is_nil/1
    )
  end

  defp normalize_flow_hint(step, index, lookup) when is_map(step) do
    node_id =
      step
      |> Utils.first_present([:node_id, :node])
      |> ModuleIndex.resolve_optional_node_id(lookup)

    focus_node_id =
      step
      |> Utils.first_present([:focus_node_id, :graph_node, :graph_node_id])
      |> ModuleIndex.normalize_focus_override(node_id, lookup)
      |> Kernel.||(
        ModuleIndex.resolve_step_focus(
          node_id,
          Utils.first_present(step, [:step_name, :focus_step_name]),
          lookup
        )
      )
      |> Kernel.||(node_id)

    %{
      id:
        Utils.normalize_optional_string(Utils.first_present(step, [:id])) || "step-#{index + 1}",
      type: Utils.first_present(step, [:type]) || infer_flow_type(index),
      kind: Utils.first_present(step, [:kind]),
      provenance: Utils.first_present(step, [:provenance]),
      status: Utils.first_present(step, [:status]),
      label: Utils.normalize_optional_string(Utils.first_present(step, [:label])),
      node_id: node_id,
      focus_node_id: focus_node_id,
      focus_targets: ModuleIndex.explicit_focus_targets(step, lookup),
      emits: Utils.normalize_string_list(Utils.first_present(step, [:emits])),
      reacts_to: Utils.normalize_optional_string(Utils.first_present(step, [:reacts_to])),
      action: Utils.normalize_optional_string(Utils.first_present(step, [:action])),
      actor: Utils.normalize_optional_string(Utils.first_present(step, [:actor])),
      module_function:
        Utils.normalize_optional_string(Utils.first_present(step, [:module_function])),
      source_snippet:
        Utils.normalize_optional_string(Utils.first_present(step, [:source_snippet])),
      result: Utils.normalize_optional_string(Utils.first_present(step, [:result])),
      details: Utils.normalize_optional_string(Utils.first_present(step, [:details]))
    }
  end

  defp normalize_flow_hint(_step, _index, _lookup), do: nil
end

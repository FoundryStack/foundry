defmodule ExTracer.FlowSummary do
  @moduledoc false

  alias ExTracer.Step
  alias ExTracer.Utils

  def attach_focus_targets(steps) do
    steps
    |> Enum.with_index()
    |> Enum.map(fn {step, index} ->
      next_focus =
        steps
        |> Enum.at(index + 1)
        |> case do
          nil -> []
          next_step -> [next_step.focus_node_id || next_step.node_id] |> Enum.reject(&is_nil/1)
        end

      merged_focus_targets =
        (Map.get(step, :focus_targets, []) ++ next_focus)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      %{step | focus_targets: merged_focus_targets}
    end)
  end

  def assign_step_ids(steps) do
    Enum.with_index(steps, 1)
    |> Enum.map(fn {step, index} -> %{step | id: "step-#{index}"} end)
  end

  def summarize_evidence(flow) do
    %{
      executed_steps: Enum.count(flow, &(&1.provenance == :executed)),
      expanded_steps: Enum.count(flow, &(&1.provenance == :expanded)),
      branch_steps: Enum.count(flow, &(&1.provenance == :branch)),
      passed_steps: Enum.count(flow, &(&1.status == :passed)),
      failed_steps: Enum.count(flow, &(&1.status == :failed)),
      short_circuit_steps: Enum.count(flow, &(&1.status == :short_circuit))
    }
  end

  def collapse_duplicate_runtime_steps(steps) do
    steps
    |> Enum.reduce([], fn step, acc ->
      case acc do
        [previous | rest] ->
          if duplicate_runtime_step?(previous, step) do
            [merge_runtime_steps(previous, step) | rest]
          else
            [step | acc]
          end

        _ ->
          [step | acc]
      end
    end)
    |> Enum.reverse()
  end

  def derive_flow_summaries(flow) do
    path_flow =
      Enum.reject(flow, fn step ->
        step.provenance == :branch and step.kind == :assert_result
      end)

    nodes =
      path_flow
      |> Enum.flat_map(fn step ->
        [step.node_id, step.focus_node_id | Enum.map(step.focus_targets, &Utils.base_node_id/1)]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Utils.base_node_id/1)
      |> Enum.uniq()

    graph_path =
      path_flow
      |> Enum.flat_map(&step_graph_nodes/1)
      |> Enum.reject(&is_nil/1)
      |> Utils.distinct_consecutive()

    {nodes, graph_path}
  end

  def build_step(attrs) do
    assertion_context = Map.get(attrs, :assertion_context)

    Step.new(%{
      id: nil,
      type: Map.get(attrs, :type, :reaction),
      kind: Map.get(attrs, :kind),
      provenance: Map.get(attrs, :provenance, :executed),
      status: Map.get(attrs, :status) || Map.get(assertion_context || %{}, :status),
      label: Map.get(attrs, :label),
      node_id: Map.get(attrs, :node_id),
      focus_node_id: Map.get(attrs, :focus_node_id),
      focus_targets: Map.get(attrs, :focus_targets, []),
      emits: Map.get(attrs, :emits, []),
      reacts_to: Map.get(attrs, :reacts_to),
      action: Map.get(attrs, :action),
      actor: Map.get(attrs, :actor),
      module_function: Map.get(attrs, :module_function),
      source_snippet: Map.get(attrs, :source_snippet),
      result: Map.get(attrs, :result) || Map.get(assertion_context || %{}, :result),
      details: Map.get(attrs, :details),
      line: Map.get(attrs, :line),
      test_name: Map.get(attrs, :test_name),
      test_kind: Map.get(attrs, :test_kind),
      assertion_context: assertion_context,
      capture_origin: Map.get(attrs, :capture_origin)
    })
  end

  def expanded_step(step, attrs) do
    Step.new(%{
      id: nil,
      type: Map.get(attrs, :type, :reaction),
      kind: Map.get(attrs, :kind),
      provenance: Map.get(attrs, :provenance, :expanded),
      status: Map.get(attrs, :status),
      label: Map.get(attrs, :label),
      node_id: Map.get(attrs, :node_id, step.node_id),
      focus_node_id: Map.get(attrs, :focus_node_id, step.focus_node_id || step.node_id),
      focus_targets: Map.get(attrs, :focus_targets, []),
      emits: Map.get(attrs, :emits, []),
      reacts_to: Map.get(attrs, :reacts_to),
      action: Map.get(attrs, :action, step.action),
      actor: Map.get(attrs, :actor, step.actor),
      module_function: Map.get(attrs, :module_function, step.module_function),
      source_snippet: Map.get(attrs, :source_snippet),
      result: Map.get(attrs, :result, step.result),
      details: Map.get(attrs, :details),
      line: Map.get(attrs, :line, step.line),
      test_name: step.test_name,
      test_kind: step.test_kind,
      capture_origin: step.capture_origin
    })
  end

  def normalized_status(step, fallback), do: step.status || fallback

  def runtime_step_operation(nil), do: nil

  def runtime_step_operation(module_function) when is_binary(module_function) do
    module_function
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.split("/")
    |> List.first()
  end

  def merge_runtime_steps(previous, current) do
    merged_focus_targets =
      (Map.get(previous, :focus_targets, []) ++ Map.get(current, :focus_targets, []))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    merged_emits =
      (Map.get(previous, :emits, []) ++ Map.get(current, :emits, []))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    %{
      current
      | focus_targets: merged_focus_targets,
        emits: merged_emits,
        reacts_to: Map.get(current, :reacts_to) || Map.get(previous, :reacts_to),
        action: Map.get(current, :action) || Map.get(previous, :action),
        actor: Map.get(current, :actor) || Map.get(previous, :actor),
        module_function:
          Map.get(current, :module_function) || Map.get(previous, :module_function),
        source_snippet: Map.get(current, :source_snippet) || Map.get(previous, :source_snippet),
        result: Map.get(current, :result) || Map.get(previous, :result),
        details: Map.get(current, :details) || Map.get(previous, :details),
        line: Map.get(current, :line) || Map.get(previous, :line),
        status: merged_runtime_status(previous.status, current.status)
    }
  end

  def merged_runtime_status(:failed, _), do: :failed
  def merged_runtime_status(_, :failed), do: :failed
  def merged_runtime_status(:short_circuit, _), do: :short_circuit
  def merged_runtime_status(_, :short_circuit), do: :short_circuit
  def merged_runtime_status(_previous, current), do: current

  defp duplicate_runtime_step?(left, right), do: runtime_step_key(left) == runtime_step_key(right)

  defp runtime_step_key(step) do
    {
      step.provenance,
      step.type,
      step.node_id,
      step.focus_node_id,
      step.kind,
      step.action || runtime_step_operation(step.module_function) || step.label,
      step.module_function,
      step.line,
      step.source_snippet,
      step.capture_origin,
      step.test_name
    }
  end

  defp step_graph_nodes(step) do
    [step.focus_node_id || step.node_id | List.wrap(step.focus_targets)]
    |> Enum.reject(&is_nil/1)
    |> case do
      [first | rest] ->
        [first | Enum.reject(rest, &(&1 == first))]

      [] ->
        []
    end
  end
end

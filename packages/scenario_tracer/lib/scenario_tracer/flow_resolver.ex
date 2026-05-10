defmodule ScenarioTracer.FlowResolver do
  @moduledoc false

  @spec resolve([struct()], [struct()], map(), [module()]) :: %{
          resolved_flow: [struct()],
          diagnostics: map()
        }
  def resolve(static_flow, runtime_flow, _lookup, _adapters) do
    cond do
      runtime_flow == [] ->
        %{
          resolved_flow: static_flow,
          diagnostics: %{mode: :static_fallback, matched_steps: 0, inferred_steps: 0}
        }

      static_flow == [] ->
        %{
          resolved_flow: runtime_flow,
          diagnostics: %{mode: :runtime_only, matched_steps: 0, inferred_steps: 0}
        }

      true ->
        matches = match_runtime_steps(runtime_flow, static_flow)

        resolved_flow =
          runtime_flow
          |> Enum.with_index()
          |> Enum.flat_map(fn {runtime_step, runtime_index} ->
            static_index = Map.get(matches.by_runtime, runtime_index)

            merged_step =
              case static_index do
                nil -> runtime_step
                index -> merge_steps(Enum.at(static_flow, index), runtime_step)
              end

            [merged_step | inferred_static_segment(static_flow, matches, runtime_index)]
          end)

        %{
          resolved_flow: resolved_flow,
          diagnostics: %{
            mode: :runtime_enriched,
            matched_steps: map_size(matches.by_runtime),
            inferred_steps:
              Enum.count(resolved_flow, &(&1.provenance in [:expanded, :branch])) -
                Enum.count(runtime_flow, &(&1.provenance in [:expanded, :branch]))
          }
        }
    end
  end

  defp match_runtime_steps(runtime_flow, static_flow) do
    runtime_flow
    |> Enum.with_index()
    |> Enum.reduce(%{by_runtime: %{}, by_static: %{}, used_static: MapSet.new()}, fn {step, index},
                                                                                     acc ->
      case find_static_match(step, static_flow, acc.used_static) do
        nil ->
          acc

        static_index ->
          %{
            by_runtime: Map.put(acc.by_runtime, index, static_index),
            by_static: Map.put(acc.by_static, static_index, index),
            used_static: MapSet.put(acc.used_static, static_index)
          }
      end
    end)
  end

  defp find_static_match(runtime_step, static_flow, used_static) do
    static_flow
    |> Enum.with_index()
    |> Enum.reject(fn {_static_step, index} -> MapSet.member?(used_static, index) end)
    |> Enum.map(fn {static_step, index} -> {match_rank(runtime_step, static_step), index} end)
    |> Enum.reject(fn {rank, _index} -> is_nil(rank) end)
    |> Enum.min_by(fn {rank, _index} -> rank end, fn -> nil end)
    |> case do
      nil -> nil
      {_rank, index} -> index
    end
  end

  defp match_rank(runtime_step, static_step) do
    runtime_key = merge_step_key(runtime_step)
    static_key = merge_step_key(static_step)

    cond do
      static_key == runtime_key ->
        {0, 0}

      compatible_step_match?(runtime_step, static_step) ->
        {1, compatibility_penalty(runtime_step, static_step)}

      true ->
        nil
    end
  end

  defp compatible_step_match?(runtime_step, static_step) do
    Map.get(runtime_step, :type) == Map.get(static_step, :type) and
      Map.get(runtime_step, :kind) == Map.get(static_step, :kind) and
      Map.get(runtime_step, :node_id) == Map.get(static_step, :node_id) and
      (Map.get(runtime_step, :focus_node_id) || Map.get(runtime_step, :node_id)) ==
        (Map.get(static_step, :focus_node_id) || Map.get(static_step, :node_id))
  end

  defp compatibility_penalty(runtime_step, static_step) do
    runtime_action = Map.get(runtime_step, :action)
    static_action = Map.get(static_step, :action)

    cond do
      runtime_action == static_action -> 0
      is_nil(runtime_action) or is_nil(static_action) -> 1
      true -> 2
    end
  end

  defp inferred_static_segment(static_flow, %{by_static: by_static}, runtime_index) do
    current_static_index = matched_static_index(by_static, runtime_index)
    next_static_index = matched_static_index(by_static, runtime_index + 1)

    if is_nil(current_static_index) do
      []
    else
      start_index = current_static_index + 1

      end_index =
        if(is_nil(next_static_index), do: length(static_flow) - 1, else: next_static_index - 1)

      if start_index > end_index do
        []
      else
        segment = Enum.slice(static_flow, start_index..end_index)

        if is_nil(next_static_index) do
          Enum.reject(segment, &matchable_static_step?/1)
        else
          segment
        end
      end
    end
  end

  defp matched_static_index(by_static, runtime_index) do
    Enum.find_value(by_static, fn {static_index, matched_runtime_index} ->
      if matched_runtime_index == runtime_index, do: static_index, else: nil
    end)
  end

  defp matchable_static_step?(step), do: step.provenance == :executed

  defp merge_steps(static_step, runtime_step) do
    %{
      static_step
      | provenance: runtime_step.provenance,
        status: runtime_step.status || static_step.status,
        label: runtime_step.label || static_step.label,
        focus_node_id: preferred_focus_node_id(static_step, runtime_step),
        focus_targets:
          if(runtime_step.focus_targets in [nil, []],
            do: static_step.focus_targets,
            else: runtime_step.focus_targets
          ),
        action: runtime_step.action || static_step.action,
        module_function: runtime_step.module_function || static_step.module_function,
        result: runtime_step.result || static_step.result,
        details: runtime_step.details || static_step.details,
        capture_origin: runtime_step.capture_origin || static_step.capture_origin
    }
  end

  defp preferred_focus_node_id(static_step, runtime_step) do
    runtime_focus = runtime_step.focus_node_id || runtime_step.node_id
    static_focus = static_step.focus_node_id || static_step.node_id

    cond do
      is_nil(runtime_focus) ->
        static_focus

      is_nil(static_focus) ->
        runtime_focus

      runtime_focus == runtime_step.node_id and static_focus != static_step.node_id ->
        static_focus

      true ->
        runtime_focus
    end
  end

  defp merge_step_key(step) do
    {
      Map.get(step, :type),
      Map.get(step, :kind),
      Map.get(step, :action),
      Map.get(step, :focus_node_id) || Map.get(step, :node_id),
      Map.get(step, :node_id)
    }
  end
end

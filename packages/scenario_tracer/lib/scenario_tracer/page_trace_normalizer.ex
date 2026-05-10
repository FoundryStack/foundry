defmodule ScenarioTracer.PageTraceNormalizer do
  @moduledoc false

  alias ScenarioTracer.{PageActionResolver, PageTraceSemantics}

  def normalize([], _lookup) do
    %{
      static_flow: [],
      runtime_flow: [],
      raw_flow: [],
      raw_test_flows: [],
      static_test_flows: [],
      runtime_test_flows: [],
      resolved_test_flows: [],
      test_flows: [],
      canonical_flow: []
    }
  end

  def normalize([first | _] = test_flows, lookup) when is_map(first) do
    normalized_inputs = normalize_test_flow_inputs(test_flows)

    if PageTraceSemantics.page_flow?(normalized_inputs, lookup) do
      normalized_resolved_test_flows =
        normalized_inputs
        |> Enum.map(&normalize_resolved_test_flow(&1, lookup))
        |> Enum.reject(&(&1.resolved_flow == []))

      canonical_flow = choose_canonical_flow(normalized_resolved_test_flows)

      build_result(normalized_inputs, normalized_resolved_test_flows, canonical_flow)
    else
      build_result(
        normalized_inputs,
        normalized_inputs,
        flatten_resolved_test_flows(normalized_inputs)
      )
    end
  end

  def normalize(flow, lookup) do
    flow
    |> Enum.reduce({[], %{}}, fn step, {ordered_names, grouped} ->
      test_name = step.test_name

      names =
        if Map.has_key?(grouped, test_name) do
          ordered_names
        else
          [test_name | ordered_names]
        end

      entry =
        Map.get(grouped, test_name, %{
          test_name: test_name,
          static_flow: [],
          runtime_flow: [],
          resolved_flow: []
        })

      updated_entry = %{entry | resolved_flow: [step | entry.resolved_flow]}

      {names, Map.put(grouped, test_name, updated_entry)}
    end)
    |> then(fn {ordered_names, grouped} ->
      ordered_names
      |> Enum.reverse()
      |> Enum.map(fn test_name ->
        entry = Map.fetch!(grouped, test_name)
        %{entry | resolved_flow: Enum.reverse(entry.resolved_flow)}
      end)
    end)
    |> normalize(lookup)
  end

  defp normalize_test_flow_inputs(test_flows) do
    Enum.map(test_flows, fn test_flow ->
      %{
        test_name: Map.fetch!(test_flow, :test_name),
        static_flow: Map.get(test_flow, :static_flow, []),
        runtime_flow: Map.get(test_flow, :runtime_flow, []),
        resolved_flow: Map.get(test_flow, :resolved_flow) || Map.get(test_flow, :flow, [])
      }
    end)
  end

  defp normalize_resolved_test_flow(test_flow, lookup) do
    normalized_wrapped_flow =
      test_flow.resolved_flow
      |> PageTraceSemantics.wrap_flow(lookup)
      |> PageTraceSemantics.collapse_duplicate_mount_cycles()
      |> PageTraceSemantics.meaningful_wrappers()
      |> resolve_exact_actions(lookup)

    Map.merge(test_flow, %{
      resolved_flow: PageTraceSemantics.strip_wrappers(normalized_wrapped_flow),
      semantic_keys: Enum.map(normalized_wrapped_flow, &PageTraceSemantics.semantic_key/1),
      exact_actions:
        Enum.count(normalized_wrapped_flow, &PageTraceSemantics.exact_action_candidate?/1)
    })
  end

  defp resolve_exact_actions(wrapped_flow, lookup) do
    {resolved, _active_page} =
      Enum.map_reduce(wrapped_flow, nil, fn %{step: step} = wrapped, active_page ->
        cond do
          PageTraceSemantics.page_node?(step.node_id, lookup) ->
            {wrapped, step.node_id}

          is_binary(active_page) ->
            {%{wrapped | step: PageActionResolver.resolve_step(step, active_page, lookup)},
             active_page}

          true ->
            {wrapped, active_page}
        end
      end)

    resolved
  end

  defp build_result(inputs, normalized_resolved_test_flows, canonical_flow) do
    raw_test_flows =
      Enum.map(inputs, fn %{
                            test_name: test_name,
                            static_flow: static_flow,
                            runtime_flow: runtime_flow
                          } ->
        %{
          test_name: test_name,
          flow: if(runtime_flow == [], do: static_flow, else: runtime_flow)
        }
      end)

    static_test_flows = Enum.map(inputs, &Map.take(&1, [:test_name, :static_flow]))
    runtime_test_flows = Enum.map(inputs, &Map.take(&1, [:test_name, :runtime_flow]))

    resolved_test_flows =
      Enum.map(normalized_resolved_test_flows, fn test_flow ->
        %{test_name: test_flow.test_name, flow: test_flow.resolved_flow}
      end)

    %{
      static_flow: flatten_keyed_test_flows(static_test_flows, :static_flow),
      runtime_flow: flatten_keyed_test_flows(runtime_test_flows, :runtime_flow),
      raw_flow: flatten_test_flows(raw_test_flows),
      raw_test_flows: raw_test_flows,
      static_test_flows: rekey_test_flows(static_test_flows, :static_flow),
      runtime_test_flows: rekey_test_flows(runtime_test_flows, :runtime_flow),
      resolved_test_flows: resolved_test_flows,
      test_flows: resolved_test_flows,
      canonical_flow: canonical_flow
    }
  end

  defp choose_canonical_flow([]), do: []

  defp choose_canonical_flow(test_flows) do
    test_flows
    |> Enum.uniq_by(& &1.semantic_keys)
    |> Enum.max_by(&canonical_score/1, fn -> %{resolved_flow: []} end)
    |> Map.get(:resolved_flow, [])
  end

  defp canonical_score(%{semantic_keys: keys, exact_actions: exact_actions}),
    do: {length(keys), exact_actions}

  defp flatten_resolved_test_flows(test_flows) do
    Enum.flat_map(test_flows, & &1.resolved_flow)
  end

  defp flatten_keyed_test_flows(test_flows, key) do
    Enum.flat_map(test_flows, &Map.get(&1, key, []))
  end

  defp flatten_test_flows(test_flows) do
    Enum.flat_map(test_flows, & &1.flow)
  end

  defp rekey_test_flows(test_flows, key) do
    Enum.map(test_flows, fn %{test_name: test_name} = test_flow ->
      %{test_name: test_name, flow: Map.get(test_flow, key, [])}
    end)
  end
end

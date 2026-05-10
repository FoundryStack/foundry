defmodule ScenarioTracer.PageTraceNormalizer do
  @moduledoc false

  alias ScenarioTracer.{PageActionResolver, PageTraceSemantics}

  def normalize([], _lookup),
    do: %{raw_flow: [], raw_test_flows: [], test_flows: [], canonical_flow: []}

  def normalize([%{flow: _} | _] = test_flows, lookup) do
    if PageTraceSemantics.page_flow?(test_flows, lookup) do
      raw_test_flows = normalize_test_flow_inputs(test_flows)

      test_flows =
        raw_test_flows
        |> Enum.map(&normalize_test_flow(&1, lookup))
        |> Enum.reject(&(&1.flow == []))

      canonical_flow = choose_canonical_flow(test_flows)

      %{
        raw_flow: flatten_test_flows(raw_test_flows),
        raw_test_flows: raw_test_flows,
        test_flows: Enum.map(test_flows, &Map.take(&1, [:test_name, :flow])),
        canonical_flow: canonical_flow
      }
    else
      normalized = normalize_test_flow_inputs(test_flows)

      %{
        raw_flow: flatten_test_flows(normalized),
        raw_test_flows: normalized,
        test_flows: normalized,
        canonical_flow: flatten_test_flows(normalized)
      }
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

      {names, Map.update(grouped, test_name, [step], &[step | &1])}
    end)
    |> then(fn {ordered_names, grouped} ->
      ordered_names
      |> Enum.reverse()
      |> Enum.map(fn test_name ->
        %{test_name: test_name, flow: grouped |> Map.fetch!(test_name) |> Enum.reverse()}
      end)
    end)
    |> normalize(lookup)
  end

  defp normalize_test_flow_inputs(test_flows) do
    Enum.map(test_flows, fn %{test_name: test_name, flow: flow} ->
      %{test_name: test_name, flow: flow}
    end)
  end

  defp normalize_test_flow(%{test_name: test_name, flow: flow}, lookup) do
    normalized_wrapped_flow =
      flow
      |> PageTraceSemantics.wrap_flow(lookup)
      |> PageTraceSemantics.collapse_duplicate_mount_cycles()
      |> PageTraceSemantics.meaningful_wrappers()
      |> resolve_exact_actions(lookup)

    %{
      test_name: test_name,
      flow: PageTraceSemantics.strip_wrappers(normalized_wrapped_flow),
      semantic_keys: Enum.map(normalized_wrapped_flow, &PageTraceSemantics.semantic_key/1),
      exact_actions:
        Enum.count(normalized_wrapped_flow, &PageTraceSemantics.exact_action_candidate?/1)
    }
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

  defp choose_canonical_flow([]), do: []

  defp choose_canonical_flow(test_flows) do
    test_flows
    |> Enum.uniq_by(& &1.semantic_keys)
    |> Enum.max_by(&canonical_score/1, fn -> %{flow: []} end)
    |> Map.get(:flow, [])
  end

  defp canonical_score(%{semantic_keys: keys, exact_actions: exact_actions}),
    do: {length(keys), exact_actions}

  defp flatten_test_flows(test_flows) do
    Enum.flat_map(test_flows, & &1.flow)
  end
end

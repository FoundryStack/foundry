defmodule ScenarioTracer.MixTask do
  @moduledoc """
  Base orchestration for trace capture plus static/rich scenario extraction.
  """

  @callback project_root() :: String.t()
  @callback adapters() :: [module()]
  @callback lookup_builder(String.t(), [map()], map()) :: ExTracer.Lookup.t()
  @callback node_source(String.t()) :: [map()]
  @callback trace_dir(String.t()) :: String.t()
  @callback frameworks() :: [module()]

  alias ExTracer.{
    CallTracer,
    CoverageReport,
    FlowExpander,
    FlowHints,
    FlowSummary,
    ModuleIndex,
    PerformanceReport,
    Report,
    RuntimeNormalizer,
    TestScanner
  }

  alias ScenarioTracer.FlowResolver

  def run(mod, args \\ []) do
    started = System.monotonic_time(:millisecond)
    project_root = mod.project_root()
    trace_dir = mod.trace_dir(project_root)
    nodes = mod.node_source(project_root)
    runtime = ScenarioTracer.TraceStore.JsonFile.load(%{trace_dir: trace_dir})
    lookup = mod.lookup_builder(project_root, nodes, runtime)
    adapters = mod.adapters()

    {mix_test_args, static_only?} = normalize_args(args)

    if not static_only? do
      _ = Mix.Task.run("test", mix_test_args)
    end

    scenarios =
      project_root
      |> Path.join("test/**/*.{ex,exs}")
      |> Path.wildcard()
      |> Enum.flat_map(&extract_file(&1, mod.frameworks(), lookup, adapters))
      |> Enum.uniq_by(&{&1.id, &1.source_file})

    duration_ms = System.monotonic_time(:millisecond) - started

    %Report{
      extracted_at: DateTime.utc_now(),
      duration_ms: duration_ms,
      scenarios: scenarios,
      coverage: build_coverage(nodes, scenarios),
      performance: build_performance(runtime, duration_ms),
      node_index: build_node_index(scenarios),
      warnings: []
    }
  end

  defp extract_file(file_path, frameworks, lookup, adapters) do
    with {:ok, content} <- File.read(file_path),
         {:ok, ast} <- Code.string_to_quoted(content) do
      alias_map = extract_alias_map(ast)
      source_module = extract_module_name(ast)

      Enum.flat_map(frameworks, fn framework ->
        TestScanner.extract_from_ast(
          ast,
          source_module,
          file_path,
          alias_map,
          framework,
          fn describe_name,
             body,
             source_module,
             file_path,
             alias_map,
             metadata_attrs,
             test_kinds ->
            scenario_id = TestScanner.generate_scenario_id(source_module, describe_name)
            scenario_meta = TestScanner.extract_scenario_metadata(body, metadata_attrs)

            traced_tests =
              body
              |> TestScanner.extract_test_blocks(test_kinds)
              |> Enum.map(fn test_block ->
                executed_flow =
                  CallTracer.collect_executed_trace(test_block, alias_map, lookup, adapters)

                page_fallback_flow =
                  (
                    page_test_flow_module =
                      Module.concat(Foundry.Context.Scenarios, PageTestFlow)

                    if Code.ensure_loaded?(page_test_flow_module) do
                      apply(page_test_flow_module, :infer_static_flow, [
                        test_block,
                        alias_map,
                        lookup
                      ])
                    else
                      []
                    end
                  )

                flow =
                  (executed_flow ++ page_fallback_flow)
                  |> Enum.sort_by(&{&1.line || test_block.line || 0, step_sort_weight(&1)})
                  |> Enum.flat_map(&FlowExpander.expand_step(&1, lookup, adapters))

                runtime_trace =
                  lookup.runtime
                  |> Map.get(scenario_id, [])
                  |> Enum.find(&ScenarioTracer.TraceStore.JsonFile.match(&1, test_block.name))

                %{
                  static_flow: flow,
                  executed_flow: executed_flow,
                  runtime_trace: runtime_trace,
                  test_case: %{
                    name: test_block.name,
                    kind: test_block.kind,
                    file: file_path,
                    line: test_block.line
                  }
                }
              end)
              |> Enum.filter(&(Enum.any?(&1.static_flow) or not is_nil(&1.runtime_trace)))

            if traced_tests == [] do
              []
            else
              flow_hints = FlowHints.normalize_flow_hints(Map.get(scenario_meta, :flow), lookup)

              traced_test_flows =
                traced_tests
                |> Enum.map(fn traced_test ->
                  runtime_flow =
                    RuntimeNormalizer.normalize(
                      traced_test.runtime_trace,
                      traced_test.test_case,
                      lookup,
                      adapters
                    )

                  resolved =
                    FlowResolver.resolve(
                      traced_test.static_flow,
                      runtime_flow,
                      lookup,
                      adapters
                    )

                  %{
                    test_name: traced_test.test_case.name,
                    static_flow: traced_test.static_flow,
                    runtime_flow: runtime_flow,
                    resolved_flow: resolved.resolved_flow
                  }
                end)

              normalized_page_flow =
                ScenarioTracer.PageTraceNormalizer.normalize(traced_test_flows, lookup)

              flow =
                normalized_page_flow.canonical_flow
                |> FlowHints.merge_flow_hints(flow_hints)
                |> materialize_flow()

              static_flow = materialize_flow(normalized_page_flow.static_flow)
              runtime_flow = materialize_flow(normalized_page_flow.runtime_flow)
              raw_flow = materialize_flow(normalized_page_flow.raw_flow)
              raw_test_flows = materialize_test_flows(normalized_page_flow.raw_test_flows)
              static_test_flows = materialize_test_flows(normalized_page_flow.static_test_flows)
              runtime_test_flows = materialize_test_flows(normalized_page_flow.runtime_test_flows)

              resolved_test_flows =
                materialize_test_flows(normalized_page_flow.resolved_test_flows)

              test_flows = resolved_test_flows

              {nodes, graph_path} = FlowSummary.derive_flow_summaries(flow)

              has_runtime =
                Enum.any?(traced_tests, fn traced_test ->
                  not is_nil(traced_test.runtime_trace)
                end)

              [
                %ExTracer.Scenario{
                  id: scenario_id,
                  name: to_string(describe_name),
                  category: infer_category(scenario_meta, traced_tests),
                  level: infer_level(traced_tests, flow, lookup),
                  source_file: file_path,
                  source_module: source_module,
                  evidence_mode: if(has_runtime, do: :runtime, else: :static),
                  trace_status: if(has_runtime, do: :present, else: :missing),
                  nodes: nodes,
                  graph_path: graph_path,
                  compliance_links:
                    ExTracer.Utils.normalize_string_list(
                      Map.get(scenario_meta, :compliance_links)
                    ),
                  flow: flow,
                  static_flow: static_flow,
                  runtime_flow: runtime_flow,
                  raw_flow: raw_flow,
                  raw_test_flows: raw_test_flows,
                  static_test_flows: static_test_flows,
                  runtime_test_flows: runtime_test_flows,
                  resolved_test_flows: resolved_test_flows,
                  test_flows: test_flows,
                  evidence_summary: FlowSummary.summarize_evidence(flow),
                  tests: Enum.map(traced_tests, & &1.test_case),
                  tags: TestScanner.normalize_tags(Map.get(scenario_meta, :tags) || [])
                }
              ]
            end
          end
        )
      end)
    else
      _ -> []
    end
  end

  defp infer_category(meta, traced_tests) do
    cond do
      category = Map.get(meta, :category) ->
        category

      Enum.any?(ExTracer.Utils.normalize_string_list(Map.get(meta, :compliance_links))) ->
        :compliance

      Enum.any?(traced_tests, &(&1.test_case.kind == :property)) ->
        :property

      true ->
        :invariant
    end
  end

  defp infer_level(traced_tests, flow, lookup) do
    traced_tests
    |> Enum.flat_map(&Map.get(&1, :executed_flow, []))
    |> Enum.map(&ModuleIndex.entry_point_level(&1, lookup))
    |> Enum.reject(&is_nil/1)
    |> highest_level()
    |> case do
      nil -> infer_page_level(flow, lookup)
      level -> level
    end
  end

  defp step_sort_weight(%{provenance: :expanded}), do: 1
  defp step_sort_weight(_step), do: 0

  defp highest_level(levels) do
    cond do
      :webhook in levels -> :webhook
      :job in levels -> :job
      :transfer in levels -> :transfer
      :reactor in levels -> :reactor
      :action in levels -> :action
      :rule in levels -> :rule
      true -> nil
    end
  end

  defp infer_page_level(flow, lookup) do
    if Enum.any?(flow, fn step ->
         step.node_id &&
           match?(
             %{type: "page"},
             Map.get(lookup.by_id, ExTracer.Utils.base_node_id(step.node_id))
           )
       end) do
      :page
    end
  end

  defp extract_alias_map(ast) do
    Macro.prewalk(ast, %{}, fn
      {:alias, _meta, args} = node, acc ->
        entries =
          case args do
            [{:__aliases__, _, parts}] ->
              [{List.last(parts) |> to_string(), Enum.join(parts, ".")}]

            [{:__aliases__, _, parts}, [as: {:__aliases__, _, as_parts}]] ->
              [{Enum.join(as_parts, "."), Enum.join(parts, ".")}]

            _ ->
              []
          end

        {node, Enum.into(entries, acc)}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp extract_module_name({:defmodule, _meta, [{:__aliases__, _am, parts}, _body]}),
    do: Enum.join(parts, ".")

  defp extract_module_name({:__block__, _meta, forms}) do
    Enum.find_value(forms, fn
      {:defmodule, _, [{:__aliases__, _, parts}, _]} -> Enum.join(parts, ".")
      _ -> nil
    end) || "UnknownModule"
  end

  defp extract_module_name(_), do: "UnknownModule"

  defp build_coverage(nodes, scenarios) do
    covered = scenarios |> Enum.flat_map(& &1.nodes) |> Enum.uniq()
    total = length(nodes)
    covered_count = Enum.count(nodes, &(&1.id in covered))

    %CoverageReport{
      total_nodes: total,
      covered_nodes: covered_count,
      coverage_pct: if(total == 0, do: 0.0, else: covered_count / total * 100.0),
      uncovered_node_ids: Enum.reject(Enum.map(nodes, & &1.id), &(&1 in covered)),
      coverage_by_type:
        nodes
        |> Enum.group_by(& &1.type)
        |> Map.new(fn {type, typed} ->
          typed_ids = Enum.map(typed, & &1.id)
          type_covered = Enum.count(typed_ids, &(&1 in covered))
          {type, if(typed == [], do: 0.0, else: type_covered / length(typed) * 100.0)}
        end)
    }
  end

  defp build_performance(runtime, extraction_duration_ms) do
    traces = runtime |> Map.values() |> List.flatten()
    durations = Enum.map(traces, &(&1.duration_ms || 0))
    ordered = Enum.sort_by(traces, &(&1.duration_ms || 0), :desc)

    %PerformanceReport{
      total_test_duration_ms: Enum.sum(durations),
      slowest_tests:
        Enum.map(Enum.take(ordered, 10), &{&1.scenario_id, &1.test_name, &1.duration_ms}),
      fastest_tests:
        Enum.map(
          Enum.take(Enum.reverse(ordered), 10),
          &{&1.scenario_id, &1.test_name, &1.duration_ms}
        ),
      avg_duration_ms:
        if(durations == [], do: 0.0, else: Enum.sum(durations) / length(durations)),
      extraction_duration_ms: extraction_duration_ms
    }
  end

  defp build_node_index(scenarios) do
    Enum.reduce(scenarios, %{}, fn scenario, acc ->
      Enum.reduce(scenario.nodes, acc, fn node_id, inner ->
        Map.update(inner, node_id, [scenario.id], &[scenario.id | &1])
      end)
    end)
  end

  defp materialize_flow(flow) do
    flow
    |> FlowSummary.assign_step_ids()
    |> FlowSummary.attach_focus_targets()
  end

  defp materialize_test_flows(test_flows) do
    Enum.map(test_flows, fn %{test_name: test_name, flow: flow} ->
      %{test_name: test_name, flow: materialize_flow(flow)}
    end)
  end

  defp normalize_args(args) do
    static_only? =
      Enum.any?(args, fn
        :static_only -> true
        "--static-only" -> true
        _ -> false
      end)

    mix_test_args =
      Enum.reject(args, fn
        :static_only -> true
        "--static-only" -> true
        _ -> false
      end)

    {mix_test_args, static_only?}
  end
end

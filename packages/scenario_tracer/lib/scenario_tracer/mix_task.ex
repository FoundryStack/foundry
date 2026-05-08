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

  alias ExTracer.{CallTracer, CoverageReport, FlowExpander, FlowHints, FlowSummary, PerformanceReport, Report, TestScanner}

  def run(mod, args \\ []) do
    started = System.monotonic_time(:millisecond)
    project_root = mod.project_root()
    trace_dir = mod.trace_dir(project_root)
    nodes = mod.node_source(project_root)
    runtime = ScenarioTracer.TraceStore.JsonFile.load(%{trace_dir: trace_dir})
    lookup = mod.lookup_builder(project_root, nodes, runtime)
    adapters = mod.adapters()

    if args != [:static_only] do
      _ = Mix.Task.run("test", args)
    end

    scenarios =
      project_root
      |> Path.join("test/**/*.{ex,exs}")
      |> Path.wildcard()
      |> Enum.flat_map(&extract_file(&1, mod.frameworks(), lookup, adapters))

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
        TestScanner.extract_from_ast(ast, source_module, file_path, alias_map, framework, fn describe_name,
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
              executed_flow = CallTracer.collect_executed_trace(test_block, alias_map, lookup, adapters)
              flow = Enum.flat_map(executed_flow, &FlowExpander.expand_step(&1, lookup, adapters))
              runtime_trace = lookup.runtime |> Map.get(scenario_id, []) |> Enum.find(&ScenarioTracer.TraceStore.JsonFile.match(&1, test_block.name))
              runtime_flow = runtime_steps_from_trace(runtime_trace, test_block)
              merged_flow = merge_runtime_flow(flow, runtime_flow)

              %{
                flow: merged_flow,
                executed_flow: executed_flow,
                runtime_trace: runtime_trace,
                test_case: %{name: test_block.name, kind: test_block.kind, file: file_path, line: test_block.line}
              }
            end)
            |> Enum.filter(&(Enum.any?(&1.flow) or not is_nil(&1.runtime_trace)))

          if traced_tests == [] do
            []
          else
            flow_hints = FlowHints.normalize_flow_hints(Map.get(scenario_meta, :flow), lookup)

            flow =
              traced_tests
              |> Enum.flat_map(& &1.flow)
              |> FlowSummary.assign_step_ids()
              |> FlowSummary.attach_focus_targets()
              |> FlowHints.merge_flow_hints(flow_hints)

            {nodes, graph_path} = FlowSummary.derive_flow_summaries(flow)

            has_runtime = Enum.any?(traced_tests, &not is_nil(&1.runtime_trace))

            [
              %ExTracer.Scenario{
                id: scenario_id,
                name: to_string(describe_name),
                category: infer_category(scenario_meta, traced_tests),
                level: infer_level(traced_tests, lookup),
                source_file: file_path,
                source_module: source_module,
                evidence_mode: if(has_runtime, do: :runtime, else: :static),
                trace_status: if(has_runtime, do: :present, else: :missing),
                nodes: nodes,
                graph_path: graph_path,
                compliance_links: ExTracer.Utils.normalize_string_list(Map.get(scenario_meta, :compliance_links)),
                flow: flow,
                evidence_summary: FlowSummary.summarize_evidence(flow),
                tests: Enum.map(traced_tests, & &1.test_case),
                tags: TestScanner.normalize_tags(Map.get(scenario_meta, :tags) || [])
              }
            ]
          end
        end)
      end)
    else
      _ -> []
    end
  end

  defp infer_category(meta, traced_tests) do
    cond do
      category = Map.get(meta, :category) -> category
      Enum.any?(ExTracer.Utils.normalize_string_list(Map.get(meta, :compliance_links))) -> :compliance
      Enum.any?(traced_tests, &(&1.test_case.kind == :property)) -> :property
      true -> :invariant
    end
  end

  defp infer_level(traced_tests, lookup) do
    _ = {traced_tests, lookup}
    nil
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
      coverage_by_type: nodes |> Enum.group_by(& &1.type) |> Map.new(fn {type, typed} ->
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
      slowest_tests: Enum.map(Enum.take(ordered, 10), &{&1.scenario_id, &1.test_name, &1.duration_ms}),
      fastest_tests: Enum.map(Enum.take(Enum.reverse(ordered), 10), &{&1.scenario_id, &1.test_name, &1.duration_ms}),
      avg_duration_ms: if(durations == [], do: 0.0, else: Enum.sum(durations) / length(durations)),
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

  defp runtime_steps_from_trace(nil, _test_block), do: []

  defp runtime_steps_from_trace(trace, test_block) when is_map(trace) do
    events = Map.get(trace, :events) || Map.get(trace, "events") || []
    Enum.map(events, fn event ->
      node_id = Map.get(event, :node_id) || Map.get(event, "node_id")
      focus_node_id = Map.get(event, :focus_node_id) || Map.get(event, "focus_node_id") || node_id
      action_kind = Map.get(event, :action_kind) || Map.get(event, "action_kind")
      status = Map.get(event, :status) || Map.get(event, "status") || :passed

      FlowSummary.build_step(%{
        node_id: node_id,
        focus_node_id: focus_node_id,
        kind: action_kind,
        provenance: :executed,
        status: status,
        test_name: test_block.name,
        test_kind: test_block.kind,
        capture_origin: :runtime_trace
      })
    end)
  end

  defp merge_runtime_flow([], runtime_flow), do: runtime_flow

  defp merge_runtime_flow(static_flow, runtime_flow) do
    static_node_keys = MapSet.new(static_flow, &{&1.node_id, &1.kind})
    extra = Enum.reject(runtime_flow, &MapSet.member?(static_node_keys, {&1.node_id, &1.kind}))
    static_flow ++ extra
  end
end

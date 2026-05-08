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

              %{
                flow: flow,
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

            static_flow =
              traced_tests
              |> Enum.flat_map(& &1.flow)
              |> FlowSummary.assign_step_ids()
              |> FlowSummary.attach_focus_targets()
              |> FlowHints.merge_flow_hints(flow_hints)

            overlay_flow =
              traced_tests
              |> Enum.flat_map(& &1.executed_flow)
              |> FlowSummary.assign_step_ids()
              |> FlowSummary.attach_focus_targets()

            runtime_flow =
              traced_tests
              |> Enum.flat_map(
                &RuntimeNormalizer.normalize(&1.runtime_trace, &1.test_case, lookup, adapters)
              )
              |> FlowSummary.assign_step_ids()
              |> FlowSummary.attach_focus_targets()

            flow =
              if runtime_flow == [] do
                static_flow
              else
                merge_runtime_with_static(static_flow, runtime_flow)
              end
              |> maybe_compact_page_flow(lookup)
              |> FlowSummary.assign_step_ids()
              |> FlowSummary.attach_focus_targets()

            _overlay =
              if runtime_flow == [] do
                overlay_flow
              else
                merge_runtime_with_static(overlay_flow, runtime_flow)
              end

            {nodes, graph_path} = FlowSummary.derive_flow_summaries(flow)
            has_runtime = runtime_flow != []

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
    traced_tests
    |> Enum.flat_map(&Map.get(&1, :executed_flow, []))
    |> Enum.map(&ModuleIndex.entry_point_level(&1, lookup))
    |> Enum.reject(&is_nil/1)
    |> highest_level()
  end

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

  defp merge_runtime_with_static(static_flow, runtime_flow) do
    cond do
      runtime_flow == [] ->
        static_flow

      static_flow == [] ->
        runtime_flow

      true ->
        do_merge_runtime_with_static(static_flow, runtime_flow)
    end
  end

  defp do_merge_runtime_with_static(static_flow, runtime_flow) do
    do_merge_runtime_with_static(static_flow, runtime_flow, [], MapSet.new())
  end

  defp do_merge_runtime_with_static([], [], acc, _seen_keys), do: Enum.reverse(acc)

  defp do_merge_runtime_with_static([], [runtime_step | rest], acc, seen_keys) do
    runtime_key = merge_step_key(runtime_step)
    do_merge_runtime_with_static([], rest, [runtime_step | acc], MapSet.put(seen_keys, runtime_key))
  end

  defp do_merge_runtime_with_static([static_step | rest], [], acc, seen_keys) do
    static_key = merge_step_key(static_step)

    if MapSet.member?(seen_keys, static_key) do
      do_merge_runtime_with_static(rest, [], acc, seen_keys)
    else
      do_merge_runtime_with_static(rest, [], [static_step | acc], MapSet.put(seen_keys, static_key))
    end
  end

  defp do_merge_runtime_with_static(
         [static_step | static_rest] = static_flow,
         [runtime_step | runtime_rest] = runtime_flow,
         acc,
         seen_keys
       ) do
    static_key = merge_step_key(static_step)
    runtime_key = merge_step_key(runtime_step)

    cond do
      static_key == runtime_key ->
        do_merge_runtime_with_static(
          static_rest,
          runtime_rest,
          [merge_steps(static_step, runtime_step) | acc],
          MapSet.put(seen_keys, static_key)
        )

      runtime_key in Enum.map(static_rest, &merge_step_key/1) ->
        if MapSet.member?(seen_keys, static_key) do
          do_merge_runtime_with_static(static_rest, runtime_flow, acc, seen_keys)
        else
          do_merge_runtime_with_static(
            static_rest,
            runtime_flow,
            [static_step | acc],
            MapSet.put(seen_keys, static_key)
          )
        end

      true ->
        do_merge_runtime_with_static(
          static_flow,
          runtime_rest,
          [runtime_step | acc],
          MapSet.put(seen_keys, runtime_key)
        )
    end
  end

  defp merge_steps(static_step, runtime_step) do
    %{
      static_step
      | provenance: runtime_step.provenance,
        status: runtime_step.status || static_step.status,
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

  defp maybe_compact_page_flow(flow, lookup) do
    if page_flow?(flow, lookup) do
      flow
      |> chunk_flow_by_test_name()
      |> Enum.map(&collapse_initial_duplicate_page_cycle(&1, lookup))
      |> compact_page_chunks()
      |> Enum.flat_map(& &1)
      |> Enum.map(&%{&1 | focus_targets: []})
      |> refine_page_action_focus(lookup)
    else
      flow
    end
  end

  defp page_flow?([first | _], lookup), do: page_node?(first.node_id, lookup)
  defp page_flow?([], _lookup), do: false

  defp page_node?(node_id, lookup) when is_binary(node_id) do
    case Map.get(lookup.by_id, node_id) do
      %{type: type} when type in ["page", :page, "live_page", :live_page] -> true
      _ -> false
    end
  end

  defp page_node?(_, _lookup), do: false

  defp chunk_flow_by_test_name(flow) do
    flow
    |> Enum.chunk_by(& &1.test_name)
    |> Enum.reject(&(&1 == []))
  end

  defp collapse_initial_duplicate_page_cycle([first | _] = chunk, lookup) do
    if page_node?(first.node_id, lookup) do
      do_collapse_initial_duplicate_page_cycle(chunk)
    else
      chunk
    end
  end

  defp collapse_initial_duplicate_page_cycle([], _lookup), do: []

  defp do_collapse_initial_duplicate_page_cycle(chunk) do
    max_cycle = div(length(chunk), 2)

    case max_cycle do
      cycle_size when cycle_size < 1 ->
        chunk

      _ ->
        case Enum.find(1..max_cycle, fn cycle_size ->
               repeated_initial_cycle?(chunk, cycle_size)
             end) do
          nil ->
            chunk

          cycle_size ->
            chunk
            |> Enum.take(cycle_size)
            |> Kernel.++(Enum.drop(chunk, cycle_size * 2))
            |> do_collapse_initial_duplicate_page_cycle()
        end
    end
  end

  defp repeated_initial_cycle?(chunk, cycle_size) when cycle_size > 0 do
    leading = Enum.take(chunk, cycle_size)
    repeated = chunk |> Enum.drop(cycle_size) |> Enum.take(cycle_size)

    leading != [] and repeated != [] and
      Enum.map(leading, &page_compaction_step_key/1) ==
        Enum.map(repeated, &page_compaction_step_key/1)
  end

  defp compact_page_chunks(chunks) do
    Enum.reduce(chunks, [], fn chunk, acc ->
      cond do
        Enum.any?(acc, &same_page_chunk?(&1, chunk)) ->
          acc

        Enum.any?(acc, &page_chunk_prefix?(chunk, &1)) ->
          acc

        true ->
          acc
          |> Enum.reject(&page_chunk_prefix?(&1, chunk))
          |> Kernel.++([chunk])
      end
    end)
  end

  defp same_page_chunk?(left, right) do
    Enum.map(left, &page_compaction_step_key/1) == Enum.map(right, &page_compaction_step_key/1)
  end

  defp page_chunk_prefix?(prefix, full) when length(prefix) <= length(full) do
    prefix_keys = Enum.map(prefix, &page_compaction_step_key/1)
    full_keys = full |> Enum.take(length(prefix)) |> Enum.map(&page_compaction_step_key/1)
    prefix_keys == full_keys
  end

  defp page_chunk_prefix?(_prefix, _full), do: false

  defp page_compaction_step_key(step) do
    {
      Map.get(step, :type),
      Map.get(step, :kind),
      Map.get(step, :action),
      Map.get(step, :focus_node_id) || Map.get(step, :node_id),
      Map.get(step, :node_id)
    }
  end

  defp refine_page_action_focus(flow, lookup) do
    {refined, _active_page} =
      Enum.map_reduce(flow, nil, fn step, active_page ->
        cond do
          page_node?(step.node_id, lookup) ->
            {step, step.node_id}

          is_binary(active_page) ->
            {refine_page_step(step, active_page, lookup), active_page}

          true ->
            {step, active_page}
        end
      end)

    refined
  end

  defp refine_page_step(step, page_node_id, lookup) do
    with %{calls_actions: calls_actions} when is_list(calls_actions) <- Map.get(lookup.by_id, page_node_id),
         step_action_type when not is_nil(step_action_type) <- page_step_action_type(step),
         [match] <- Enum.filter(calls_actions, &page_action_match?(&1, step, step_action_type)) do
      action_name = Map.get(match, "action_name") || Map.get(match, :action_name)

      %{
        step
        | action: step.action || normalize_action_name(action_name),
          focus_node_id: refined_page_focus(step, action_name)
      }
    else
      _ -> step
    end
  end

  defp page_step_action_type(step) do
    case step.kind do
      :read -> :read
      "read" -> :read
      :create -> :create
      "create" -> :create
      :update -> :update
      "update" -> :update
      :destroy -> :destroy
      "destroy" -> :destroy
      _ -> nil
    end
  end

  defp page_action_match?(action, step, step_action_type) do
    resource = Map.get(action, "resource") || Map.get(action, :resource)
    action_type = Map.get(action, "action") || Map.get(action, :action)

    resource == step.node_id and action_type == step_action_type
  end

  defp refined_page_focus(step, action_name) do
    normalized_action = normalize_action_name(action_name)

    cond do
      is_nil(normalized_action) ->
        step.focus_node_id

      step.focus_node_id in [nil, step.node_id] ->
        "#{step.node_id}:action:#{normalized_action}"

      true ->
        step.focus_node_id
    end
  end

  defp normalize_action_name(nil), do: nil
  defp normalize_action_name(action_name) when is_atom(action_name), do: Atom.to_string(action_name)
  defp normalize_action_name(action_name) when is_binary(action_name), do: action_name

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

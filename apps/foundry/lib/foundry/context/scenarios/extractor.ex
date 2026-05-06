defmodule Foundry.Context.Scenarios.Extractor do
  @moduledoc false

  alias Foundry.Context.ScenarioEntry
  alias Foundry.Context.Scenarios.CallTracer
  alias Foundry.Context.Scenarios.FlowExpander
  alias Foundry.Context.Scenarios.FlowHints
  alias Foundry.Context.Scenarios.FlowSummary
  alias Foundry.Context.Scenarios.ModuleIndex
  alias Foundry.Context.Scenarios.RuntimeNormalizer
  alias Foundry.Context.Scenarios.RuntimeTraceStore
  alias Foundry.Context.Scenarios.TestScanner
  alias Foundry.Context.Scenarios.Utils

  def extract(project_root, nodes) do
    test_dir = Path.join(project_root, "test")

    if File.dir?(test_dir) do
      runtime_lookup = RuntimeTraceStore.load(project_root)
      lookup = ModuleIndex.build(nodes, project_root, runtime_lookup)

      test_dir
      |> Path.join("**/*.{exs,ex}")
      |> Path.wildcard()
      |> Enum.flat_map(&extract_file(&1, lookup))
    else
      []
    end
  end

  defp extract_file(file_path, lookup) do
    with {:ok, content} <- File.read(file_path),
         {:ok, ast} <- Code.string_to_quoted(content) do
      alias_map = ModuleIndex.extract_alias_map(ast)
      source_module = ModuleIndex.extract_module_name(ast)

      ast
      |> TestScanner.extract_from_ast(source_module, file_path, alias_map, fn
        describe_name, body, source_module, file_path, alias_map ->
          extract_scenarios_from_describe(
            describe_name,
            body,
            source_module,
            file_path,
            alias_map,
            lookup
          )
      end)
      |> List.flatten()
    else
      _ -> []
    end
  end

  defp extract_scenarios_from_describe(
         describe_name,
         body,
         source_module,
         file_path,
         alias_map,
         lookup
       ) do
    scenario_id = TestScanner.generate_scenario_id(source_module, describe_name)
    scenario_meta = TestScanner.extract_scenario_metadata(body)

    traced_tests =
      body
      |> TestScanner.extract_test_blocks()
      |> Enum.map(&trace_test_block(&1, alias_map, lookup, file_path, scenario_id))
      |> Enum.filter(&(Enum.any?(&1.flow) or not is_nil(&1.runtime_trace)))

    if traced_tests == [] do
      []
    else
      flow_hints =
        FlowHints.normalize_flow_hints(Utils.first_present(scenario_meta, [:flow]), lookup)

      static_flow =
        traced_tests
        |> Enum.flat_map(& &1.flow)
        |> FlowSummary.assign_step_ids()
        |> FlowSummary.attach_focus_targets()
        |> FlowHints.merge_flow_hints(flow_hints)

      executed_overlay_flow =
        traced_tests
        |> Enum.flat_map(& &1.executed_flow)
        |> FlowSummary.assign_step_ids()
        |> FlowSummary.attach_focus_targets()

      runtime_flow =
        traced_tests
        |> Enum.flat_map(&RuntimeNormalizer.normalize(&1.runtime_trace, &1.test_case, lookup))
        |> FlowSummary.assign_step_ids()
        |> FlowSummary.attach_focus_targets()

      flow = if(runtime_flow == [], do: static_flow, else: runtime_flow)
      overlay_flow = if(runtime_flow == [], do: executed_overlay_flow, else: runtime_flow)

      if flow == [] do
        []
      else
        {nodes, graph_path} = FlowSummary.derive_flow_summaries(overlay_flow)

        [
          %ScenarioEntry{
            id: scenario_id,
            name: describe_name,
            category: infer_category(scenario_meta, traced_tests),
            level: infer_level(traced_tests, lookup),
            source_file: file_path,
            source_module: source_module,
            evidence_mode: if(runtime_flow == [], do: :static, else: :runtime),
            trace_status: if(runtime_flow == [], do: :missing, else: :captured),
            nodes: nodes,
            graph_path: graph_path,
            compliance_links:
              Utils.normalize_string_list(Utils.first_present(scenario_meta, [:compliance_links])),
            flow: flow,
            evidence_summary: FlowSummary.summarize_evidence(flow),
            tests: Enum.map(traced_tests, & &1.test_case),
            tags: TestScanner.normalize_tags(Utils.first_present(scenario_meta, [:tags]) || [])
          }
        ]
      end
    end
  end

  defp trace_test_block(test_block, alias_map, lookup, file_path, scenario_id) do
    executed_flow = CallTracer.collect_executed_trace(test_block, alias_map, lookup)
    flow = Enum.flat_map(executed_flow, &FlowExpander.expand_step(&1, lookup))

    %{
      flow: flow,
      executed_flow: executed_flow,
      entry_points: Enum.map(executed_flow, &entry_point_from_step/1),
      runtime_trace: RuntimeTraceStore.lookup(lookup.runtime, scenario_id, test_block.name),
      test_case: %{
        name: test_block.name,
        kind: test_block.kind,
        file: file_path,
        line: test_block.line
      }
    }
  end

  defp entry_point_from_step(step) do
    step
    |> Map.take([:node_id, :focus_node_id, :action, :module_function, :kind, :line, :test_name])
    |> Map.put(:provenance, :executed)
  end

  defp infer_category(scenario_meta, traced_tests) do
    cond do
      category = Utils.first_present(scenario_meta, [:category]) ->
        category

      scenario_meta
      |> Utils.first_present([:compliance_links])
      |> Utils.normalize_string_list()
      |> Enum.any?() ->
        :compliance

      Enum.any?(traced_tests, &(&1.test_case.kind == :property)) ->
        :property

      true ->
        :invariant
    end
  end

  defp infer_level(traced_tests, lookup) do
    entry_points =
      traced_tests
      |> Enum.flat_map(&Map.get(&1, :entry_points, []))

    levels =
      entry_points
      |> Enum.map(&ModuleIndex.entry_point_level(&1, lookup))
      |> Enum.reject(&is_nil/1)

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
end

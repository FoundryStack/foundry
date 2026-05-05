defmodule Foundry.Context.ScenarioExtractor do
  @moduledoc """
  Extracts Studio scenarios from executable test source.

  Real test and property bodies are the source of truth. `@scenario` metadata is
  optional and may refine category, compliance links, labels, or graph focus for
  traced steps, but it never creates a scenario on its own.
  """

  alias Foundry.Context.ScenarioEntry

  @ash_funs ~w(get read read_one create update destroy)a
  @ash_changeset_funs ~w(for_create for_update for_read for_destroy)a
  @code_globs ["lib/**/*.{ex,exs}", "apps/*/lib/**/*.{ex,exs}"]

  def extract(project_root, nodes) do
    test_dir = Path.join(project_root, "test")

    if File.dir?(test_dir) do
      node_lookup = build_node_lookup(nodes, build_code_lookup(project_root))
      runtime_lookup = load_runtime_trace_lookup(project_root)

      test_dir
      |> Path.join("**/*.{exs,ex}")
      |> Path.wildcard()
      |> Enum.flat_map(&extract_file(&1, node_lookup, runtime_lookup))
    else
      []
    end
  end

  defp extract_file(file_path, node_lookup, runtime_lookup) do
    with {:ok, content} <- File.read(file_path),
         {:ok, ast} <- Code.string_to_quoted(content) do
      alias_map = extract_alias_map(ast)
      source_module = extract_module_name(ast)
      extract_from_ast(ast, source_module, file_path, alias_map, node_lookup, runtime_lookup)
    else
      _ -> []
    end
  end

  defp extract_module_name({:defmodule, _meta, [{:__aliases__, _am, parts}, _body]}),
    do: Enum.join(parts, ".")

  defp extract_module_name({:__block__, _meta, forms}) do
    forms
    |> Enum.find_value(fn
      {:defmodule, _, [{:__aliases__, _, parts}, _]} -> Enum.join(parts, ".")
      _ -> nil
    end)
    |> Kernel.||("UnknownModule")
  end

  defp extract_module_name(_), do: "UnknownModule"

  defp extract_from_ast(ast, source_module, file_path, alias_map, node_lookup, runtime_lookup) do
    Macro.prewalk(ast, [], fn
      {:describe, _meta, [describe_name, [do: body]]} = node, acc ->
        {node,
         acc ++
           extract_scenarios_from_describe(
             describe_name,
             body,
             source_module,
             file_path,
             alias_map,
             node_lookup,
             runtime_lookup
           )}

      {:describe, _meta, [describe_name, body]} = node, acc ->
        {node,
         acc ++
           extract_scenarios_from_describe(
             describe_name,
             body,
             source_module,
             file_path,
             alias_map,
             node_lookup,
             runtime_lookup
           )}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp extract_scenarios_from_describe(
         describe_name,
         body,
         source_module,
         file_path,
         alias_map,
         node_lookup,
         runtime_lookup
       ) do
    scenario_id = generate_scenario_id(source_module, describe_name)
    scenario_meta = extract_scenario_metadata(body)

    traced_tests =
      body
      |> extract_test_blocks()
      |> Enum.map(
        &trace_test_block(&1, alias_map, node_lookup, file_path, scenario_id, runtime_lookup)
      )
      |> Enum.filter(&(Enum.any?(&1.flow) or not is_nil(&1.runtime_trace)))

    if traced_tests == [] do
      []
    else
      flow_hints = normalize_flow_hints(first_present(scenario_meta, [:flow]), node_lookup)

      static_flow =
        traced_tests
        |> Enum.flat_map(& &1.flow)
        |> assign_step_ids()
        |> attach_focus_targets()
        |> merge_flow_hints(flow_hints)

      executed_overlay_flow =
        traced_tests
        |> Enum.flat_map(& &1.executed_flow)
        |> assign_step_ids()
        |> attach_focus_targets()

      runtime_flow =
        traced_tests
        |> Enum.flat_map(&runtime_flow_for_test(&1, scenario_id, node_lookup))
        |> assign_step_ids()
        |> attach_focus_targets()

      flow = if(runtime_flow == [], do: static_flow, else: runtime_flow)
      overlay_flow = if(runtime_flow == [], do: executed_overlay_flow, else: runtime_flow)

      if flow == [] do
        []
      else
        {nodes, graph_path} = derive_flow_summaries(overlay_flow)

        [
          %ScenarioEntry{
            id: scenario_id,
            name: describe_name,
            category: infer_category(scenario_meta, traced_tests),
            level: infer_level(traced_tests, node_lookup),
            source_file: file_path,
            source_module: source_module,
            evidence_mode: if(runtime_flow == [], do: :static, else: :runtime),
            trace_status: if(runtime_flow == [], do: :missing, else: :captured),
            expansion_mode: if(runtime_flow == [], do: :hybrid, else: :runtime),
            nodes: nodes,
            graph_path: graph_path,
            compliance_links:
              normalize_string_list(first_present(scenario_meta, [:compliance_links])),
            flow: flow,
            evidence_summary: summarize_evidence(flow),
            entry_points: Enum.flat_map(traced_tests, &Map.get(&1, :entry_points, [])),
            tests: Enum.map(traced_tests, & &1.test_case),
            tags: normalize_tags(first_present(scenario_meta, [:tags]) || [])
          }
        ]
      end
    end
  end

  defp trace_test_block(
         test_block,
         alias_map,
         node_lookup,
         file_path,
         scenario_id,
         runtime_lookup
       ) do
    executed_flow =
      test_block
      |> collect_executed_trace(alias_map, node_lookup)

    flow =
      executed_flow
      |> Enum.flat_map(&expand_step(&1, node_lookup))

    %{
      flow: flow,
      executed_flow: executed_flow,
      entry_points: Enum.map(executed_flow, &entry_point_from_step/1),
      runtime_trace:
        lookup_runtime_trace(
          runtime_lookup,
          scenario_id,
          test_block.name
        ),
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

  defp runtime_flow_for_test(%{runtime_trace: nil}, _scenario_id, _node_lookup), do: []

  defp runtime_flow_for_test(
         %{runtime_trace: runtime_trace, test_case: test_case},
         _scenario_id,
         node_lookup
       ) do
    steps =
      runtime_trace
      |> Map.get("events", [])
      |> Enum.sort_by(&Map.get(&1, "sequence", 0))
      |> Enum.map(fn event ->
        %{
          id: nil,
          type: normalize_runtime_atom(Map.get(event, "type"), :reaction),
          kind: normalize_runtime_atom(Map.get(event, "kind"), :observation),
          label: Map.get(event, "label") || runtime_label(event),
          node_id: Map.get(event, "node_id"),
          focus_node_id: Map.get(event, "focus_node_id") || Map.get(event, "node_id"),
          focus_targets: normalize_string_list(Map.get(event, "focus_targets")),
          emits: normalize_string_list(Map.get(event, "emits")),
          reacts_to: Map.get(event, "reacts_to"),
          action: Map.get(event, "action"),
          actor: Map.get(event, "actor"),
          provenance: :executed,
          status: normalize_runtime_atom(Map.get(event, "status"), :passed),
          module_function: Map.get(event, "module_function"),
          source_snippet: Map.get(event, "source_snippet"),
          result: normalize_optional_string(Map.get(event, "result")),
          details: normalize_optional_string(Map.get(event, "details")),
          line: Map.get(event, "line") || test_case.line,
          test_name: test_case.name,
          test_kind: test_case.kind,
          capture_origin: normalize_optional_string(Map.get(event, "capture_origin"))
        }
      end)

    steps
    |> maybe_expand_automatic_runtime_steps(node_lookup)
    |> collapse_duplicate_runtime_steps()
  end

  defp maybe_expand_automatic_runtime_steps(steps, node_lookup) do
    Enum.flat_map(steps, fn step ->
      if Map.get(step, :capture_origin) == "automatic" do
        expand_step(step, node_lookup)
      else
        [step]
      end
    end)
  end

  defp runtime_label(event) do
    case Map.get(event, "action") do
      nil ->
        "Execute #{List.last(String.split(Map.get(event, "node_id") || "node", "."))}"

      action ->
        "Execute #{List.last(String.split(Map.get(event, "node_id") || "node", "."))}.#{action}"
    end
  end

  defp normalize_runtime_atom(nil, default), do: default

  defp normalize_runtime_atom(value, _default) when is_atom(value), do: value

  defp normalize_runtime_atom(value, default) when is_binary(value) do
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

  defp collect_executed_trace(test_block, alias_map, node_lookup) do
    block_statements(test_block.block)
    |> Enum.flat_map(fn statement ->
      collect_statement_steps(statement, alias_map, node_lookup, test_block)
    end)
  end

  defp collect_statement_steps(
         {:assert, meta, [assertion_ast]},
         alias_map,
         node_lookup,
         test_block
       ) do
    line = meta[:line] || test_block.line

    case assertion_ast do
      {:=, _match_meta, [pattern, expr]} ->
        collect_call_steps(
          expr,
          alias_map,
          node_lookup,
          test_block,
          line,
          infer_assertion_context(pattern)
        )

      expr ->
        collect_call_steps(
          expr,
          alias_map,
          node_lookup,
          test_block,
          line,
          infer_assertion_context(expr)
        )
    end
  end

  defp collect_statement_steps({:=, meta, [_lhs, expr]}, alias_map, node_lookup, test_block) do
    collect_call_steps(
      expr,
      alias_map,
      node_lookup,
      test_block,
      meta[:line] || test_block.line,
      nil
    )
  end

  defp collect_statement_steps(statement, alias_map, node_lookup, test_block) do
    collect_call_steps(statement, alias_map, node_lookup, test_block, test_block.line, nil)
  end

  defp collect_call_steps(
         ast,
         alias_map,
         node_lookup,
         test_block,
         default_line,
         assertion_context
       ) do
    Macro.prewalk(ast, [], fn
      {:|>, meta, [left, {{:., _, [module_ast, fun]}, _call_meta, args}]} = node, acc ->
        step =
          infer_call_step(
            module_ast,
            fun,
            [left | args || []],
            alias_map,
            node_lookup,
            default_line,
            meta[:line] || default_line,
            test_block.name,
            test_block.kind,
            assertion_context
          )

        {node, if(step, do: acc ++ [step], else: acc)}

      {{:., meta, [module_ast, fun]}, _call_meta, args} = node, acc ->
        step =
          infer_call_step(
            module_ast,
            fun,
            args || [],
            alias_map,
            node_lookup,
            default_line,
            meta[:line] || default_line,
            test_block.name,
            test_block.kind,
            assertion_context
          )

        {node, if(step, do: acc ++ [step], else: acc)}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp infer_call_step(
         module_ast,
         fun,
         args,
         alias_map,
         node_lookup,
         _default_line,
         line,
         test_name,
         test_kind,
         assertion_context
       ) do
    module_name = resolve_module_name(module_ast, alias_map)
    fun_name = to_string(fun)

    cond do
      module_name == "Reactor" and fun == :run ->
        infer_reactor_run_step(
          args,
          alias_map,
          node_lookup,
          line,
          test_name,
          test_kind,
          assertion_context
        )

      module_name == "Ash" and fun in @ash_funs ->
        infer_ash_step(
          fun_name,
          args,
          alias_map,
          node_lookup,
          line,
          test_name,
          test_kind,
          assertion_context
        )

      module_name == "Ash.Changeset" and fun in @ash_changeset_funs ->
        infer_changeset_step(
          fun_name,
          args,
          alias_map,
          node_lookup,
          line,
          test_name,
          test_kind,
          assertion_context
        )

      is_nil(module_name) ->
        nil

      resolved_node = resolve_node_id(module_name, node_lookup) ->
        infer_module_step(
          module_name,
          resolved_node,
          fun_name,
          node_lookup,
          line,
          test_name,
          test_kind,
          assertion_context
        )

      true ->
        nil
    end
  end

  defp infer_ash_step(
         fun_name,
         [resource_ast | rest],
         alias_map,
         node_lookup,
         line,
         test_name,
         test_kind,
         assertion_context
       ) do
    resource_name = resolve_module_name(resource_ast, alias_map)
    node_id = resolve_node_id(resource_name, node_lookup)

    if node_id do
      {action, arg_payload} = extract_ash_action(rest)

      focus_node_id =
        case action do
          nil -> node_id
          action_name -> build_action_focus(node_id, action_name, node_lookup)
        end

      build_step(%{
        type: if(fun_name in ["get", "read", "read_one"], do: :observation, else: :entry),
        kind: ash_kind(fun_name),
        label: ash_step_label(fun_name, node_id, action),
        node_id: node_id,
        focus_node_id: focus_node_id,
        focus_targets: [],
        emits: [],
        reacts_to: nil,
        action: action,
        actor: nil,
        module_function: "Ash.#{fun_name}",
        source_snippet: short_call_snippet("Ash", fun_name, arg_payload),
        details: nil,
        line: line,
        test_name: test_name,
        test_kind: test_kind,
        assertion_context: assertion_context
      })
    end
  end

  defp infer_ash_step(_, _, _, _, _, _, _, _), do: nil

  defp infer_reactor_run_step(
         [target_module_ast | _rest] = args,
         alias_map,
         node_lookup,
         line,
         test_name,
         test_kind,
         assertion_context
       ) do
    target_module_name = resolve_module_name(target_module_ast, alias_map)
    target_node_id = resolve_node_id(target_module_name, node_lookup)

    if target_node_id do
      infer_module_step(
        target_module_name,
        target_node_id,
        "run",
        node_lookup,
        line,
        test_name,
        test_kind,
        Map.put(
          assertion_context || %{},
          :source_snippet,
          short_call_snippet("Reactor", "run", args)
        )
      )
    end
  end

  defp infer_reactor_run_step(_, _, _, _, _, _, _), do: nil

  defp infer_changeset_step(
         fun_name,
         [resource_ast | rest],
         alias_map,
         node_lookup,
         line,
         test_name,
         test_kind,
         assertion_context
       ) do
    resource_name = resolve_module_name(resource_ast, alias_map)
    node_id = resolve_node_id(resource_name, node_lookup)

    if node_id do
      action =
        case rest do
          [action_ast | _] -> extract_action_name(action_ast)
          _ -> nil
        end

      focus_node_id =
        case action do
          nil -> node_id
          action_name -> build_action_focus(node_id, action_name, node_lookup)
        end

      build_step(%{
        type: :entry,
        kind: :action_prepare,
        label: changeset_step_label(fun_name, node_id, action),
        node_id: node_id,
        focus_node_id: focus_node_id,
        focus_targets: [],
        emits: [],
        reacts_to: nil,
        action: action,
        actor: nil,
        module_function: "Ash.Changeset.#{fun_name}",
        source_snippet: short_call_snippet("Ash.Changeset", fun_name, rest),
        details: "Only action preparation executed",
        line: line,
        test_name: test_name,
        test_kind: test_kind,
        assertion_context: assertion_context
      })
    end
  end

  defp infer_changeset_step(_, _, _, _, _, _, _, _), do: nil

  defp infer_module_step(
         module_name,
         node_id,
         fun_name,
         node_lookup,
         line,
         test_name,
         test_kind,
         assertion_context
       ) do
    node = Map.get(node_lookup.by_id, node_id)
    short_name = List.last(String.split(node_id, "."))

    {type, kind, action} =
      cond do
        match?(%{type: "rule"}, node) and fun_name == "evaluate" ->
          {:assertion, :rule_check, "evaluate"}

        match?(%{type: "job"}, node) and fun_name == "perform" ->
          {:job, :job_execute, fun_name}

        fun_name == "handle_webhook" ->
          {:entry, :trigger_receive, fun_name}

        fun_name == "run" and match?(%{type: type} when type in ["transfer", "reactor"], node) ->
          {:entry, :action_execute, fun_name}

        true ->
          {:entry, :action_execute, fun_name}
      end

    build_step(%{
      type: type,
      kind: kind,
      label: infer_module_label(type, short_name, fun_name),
      node_id: node_id,
      focus_node_id: infer_module_focus(node_id, node, fun_name, node_lookup),
      focus_targets: [],
      emits: [],
      reacts_to: nil,
      action: action,
      actor: nil,
      module_function: "#{module_name}.#{fun_name}",
      source_snippet:
        Map.get(assertion_context || %{}, :source_snippet) ||
          short_call_snippet(module_name, fun_name, []),
      details: nil,
      line: line,
      test_name: test_name,
      test_kind: test_kind,
      assertion_context: assertion_context
    })
  end

  defp build_step(attrs) do
    assertion_context = Map.get(attrs, :assertion_context)

    %{
      id: nil,
      type: Map.get(attrs, :type, :reaction),
      kind: Map.get(attrs, :kind),
      provenance: Map.get(attrs, :provenance, :executed),
      status: Map.get(assertion_context || %{}, :status),
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
      result: Map.get(assertion_context || %{}, :result),
      details: Map.get(attrs, :details),
      line: Map.get(attrs, :line),
      test_name: Map.get(attrs, :test_name),
      test_kind: Map.get(attrs, :test_kind)
    }
  end

  defp expand_step(step, node_lookup) do
    node = Map.get(node_lookup.by_id, step.node_id || "")

    expanded =
      cond do
        node == nil ->
          []

        node.type == "rule" ->
          expand_rule_step(step, node, node_lookup)

        node.type in ["transfer", "reactor"] and
            String.ends_with?(step.module_function || "", ".run") ->
          expand_pipeline_step(step, node)

        node.type == "trigger" and
            String.ends_with?(step.module_function || "", ".handle_webhook") ->
          expand_with_chain_step(step, node, node_lookup)

        node.type == "job" and String.ends_with?(step.module_function || "", ".perform") ->
          expand_job_step(step, node, node_lookup)

        node.type == "resource" ->
          expand_resource_step(step, node)

        true ->
          []
      end

    [step | expanded]
  end

  defp expand_resource_step(step, node) do
    case {step.kind, step.action} do
      {:action_execute, action} when is_binary(action) ->
        case find_action(node, action) do
          nil ->
            maybe_assert_result_step(step)

          action_entry ->
            [
              expanded_step(step, %{
                type: :reaction,
                kind: :action_execute,
                status: normalized_status(step, :passed),
                label: "Execute #{List.last(String.split(node.id, "."))}.#{action}",
                details:
                  Map.get(action_entry, :description) || Map.get(action_entry, "description"),
                source_snippet:
                  Map.get(action_entry, :description) || Map.get(action_entry, "description"),
                focus_node_id: step.focus_node_id || step.node_id
              })
              | maybe_assert_result_step(step)
            ]
        end

      {:action_prepare, _action} ->
        maybe_assert_result_step(step)

      _ ->
        []
    end
  end

  defp expand_pipeline_step(step, node) do
    steps = Map.get(node, :steps, [])

    pipeline_steps =
      Enum.map(steps, fn pipeline_step ->
        focus_node_id =
          resolve_pipeline_focus(node.id, pipeline_step, node.type) || node.id

        expanded_step(step, %{
          type: :reaction,
          kind: pipeline_step_kind(pipeline_step),
          status: normalized_status(step, :potential),
          label:
            pipeline_step_label(
              node.id,
              pipeline_step,
              Map.get(pipeline_step, :description) || Map.get(pipeline_step, "description")
            ),
          node_id: pipeline_step_target_node_id(node.id, pipeline_step) || node.id,
          focus_node_id: focus_node_id,
          details: pipeline_step_description(pipeline_step),
          source_snippet: pipeline_step_snippet(pipeline_step)
        })
      end)

    pipeline_steps ++ maybe_assert_result_step(step)
  end

  defp expand_job_step(step, node, node_lookup) do
    with {:ok, module_ast, _alias_map} <- fetch_module_ast(node.module, node_lookup) do
      case find_function_body(module_ast, :perform) do
        {:ok, body} ->
          if shallow_stub_body?(body) do
            [
              expanded_step(step, %{
                type: :reaction,
                kind: :job_execute,
                status: :potential,
                label: "Job implementation is stubbed",
                details: "Job implementation is stubbed",
                source_snippet: ast_to_text(body)
              })
              | maybe_assert_result_step(step)
            ]
          else
            maybe_assert_result_step(step)
          end

        :error ->
          maybe_assert_result_step(step)
      end
    else
      _ -> maybe_assert_result_step(step)
    end
  end

  defp expand_with_chain_step(step, node, node_lookup) do
    with {:ok, module_ast, alias_map} <- fetch_module_ast(node.module, node_lookup),
         {:ok, body} <- find_function_body(module_ast, :handle_webhook),
         {:with, _meta, args} <- body do
      {clauses, [options]} = Enum.split(args, -1)
      do_block = Keyword.get(options, :do)
      else_block = Keyword.get(options, :else)
      reached_count = with_reached_count(step, clauses)

      clause_steps =
        clauses
        |> Enum.take(reached_count)
        |> Enum.with_index()
        |> Enum.map(fn {clause, index} ->
          expand_with_clause(
            step,
            clause,
            index,
            alias_map,
            node.module,
            node_lookup,
            index == reached_count - 1
          )
        end)

      clause_steps ++ with_result_steps(step, do_block, else_block)
    else
      _ -> maybe_assert_result_step(step)
    end
  end

  defp expand_with_clause(
         step,
         {:<-, _, [_pattern, expr]},
         index,
         alias_map,
         current_module,
         node_lookup,
         last_reached?
       ) do
    expand_with_expr(step, expr, index, alias_map, current_module, node_lookup, last_reached?)
  end

  defp expand_with_clause(
         step,
         expr,
         index,
         alias_map,
         current_module,
         node_lookup,
         last_reached?
       ) do
    expand_with_expr(step, expr, index, alias_map, current_module, node_lookup, last_reached?)
  end

  defp expand_with_expr(
         step,
         expr,
         _index,
         alias_map,
         current_module,
         node_lookup,
         last_reached?
       ) do
    %{label: label, node_id: node_id, focus_node_id: focus_node_id, kind: kind, details: details} =
      summarize_with_expr(expr, alias_map, current_module, node_lookup)

    expanded_step(step, %{
      type: :reaction,
      kind: kind,
      status:
        if(last_reached? and step.status in [:failed, :short_circuit],
          do: :short_circuit,
          else: :passed
        ),
      label: label,
      node_id: node_id || step.node_id,
      focus_node_id: focus_node_id || node_id || step.focus_node_id || step.node_id,
      details: details,
      source_snippet: ast_to_text(expr)
    })
  end

  defp with_result_steps(step, do_block, else_block) do
    cond do
      step.status in [:passed, :matched] ->
        [
          expanded_step(step, %{
            type: :reaction,
            kind: :assert_result,
            provenance: :branch,
            status: step.status,
            label: "Return success result",
            details: ast_to_text(last_expression(do_block)),
            source_snippet: ast_to_text(last_expression(do_block))
          })
        ]

      step.status in [:failed, :short_circuit] ->
        [
          expanded_step(step, %{
            type: :reaction,
            kind: :assert_result,
            provenance: :branch,
            status: :failed,
            label: "Return failure result",
            details: ast_to_text(last_expression(else_block)),
            source_snippet: ast_to_text(last_expression(else_block))
          })
        ]

      true ->
        maybe_assert_result_step(step)
    end
  end

  defp expand_rule_step(step, node, node_lookup) do
    with {:ok, module_ast, _alias_map} <- fetch_module_ast(node.module, node_lookup),
         {:ok, body} <- find_function_body(module_ast, :evaluate) do
      statements = block_statements(body)
      {setup, [decision]} = Enum.split(statements, max(length(statements) - 1, 0))

      setup_steps =
        setup
        |> Enum.flat_map(&rule_setup_steps(step, &1))

      branch_steps =
        case decision do
          {:cond, meta, [[do: clauses]]} ->
            expand_cond_rule(step, meta[:line], clauses)

          {:if, meta, [condition, opts]} ->
            expand_if_rule(step, meta[:line], condition, opts)

          {:case, meta, [expr, [do: clauses]]} ->
            expand_case_rule(step, meta[:line], expr, clauses)

          _ ->
            maybe_assert_result_step(step)
        end

      setup_steps ++ branch_steps
    else
      _ ->
        maybe_assert_result_step(step)
    end
  end

  defp rule_setup_steps(step, {:=, meta, [lhs, rhs]}) do
    label =
      case {lhs, rhs} do
        {{var, _, _}, {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, _args}}
        when var == :limit ->
          "Select limit from player risk level"

        {{var, _, _}, {{:., _, [{:__aliases__, _, [:Money]}, :add!]}, _, _args}}
        when var == :total ->
          "Compute total requested amount"

        {{var, _, _}, {{:., _, [{:__aliases__, _, [:Enum]}, :filter]}, _, _args}}
        when var == :player_grants ->
          "Filter grants for the player and campaign"

        {{var, _, _}, {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, _args}}
        when var == :campaign_grants ->
          "Resolve campaign grant set"

        {{var, _, _}, _} ->
          "Compute #{Atom.to_string(var)}"

        _ ->
          nil
      end

    if label do
      [
        expanded_step(step, %{
          type: :reaction,
          kind: :rule_check,
          status: :passed,
          label: label,
          line: meta[:line] || step.line,
          details: ast_to_text(rhs),
          source_snippet: ast_to_text({:=, meta, [lhs, rhs]})
        })
      ]
    else
      []
    end
  end

  defp rule_setup_steps(_step, _statement), do: []

  defp expand_cond_rule(step, line, clauses) do
    matched_index = matched_clause_index(clauses, step.result)

    clauses
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{:->, _meta, [[condition], body]}, index} ->
        expand_cond_clause(step, line, index, matched_index, condition, body)

      _ ->
        []
    end)
  end

  defp expand_cond_clause(step, line, index, matched_index, condition, body) do
    cond do
      is_nil(matched_index) ->
        []

      index < matched_index ->
        [
          expanded_step(step, %{
            type: :reaction,
            kind: :rule_check,
            status: :passed,
            label: "Check #{humanize_condition(condition)}",
            line: line || step.line,
            details: "Branch not taken",
            source_snippet: ast_to_text(condition)
          })
        ]

      index == matched_index ->
        [
          expanded_step(step, %{
            type: :reaction,
            kind: :rule_branch,
            provenance: :branch,
            status: :matched,
            label: "Matched #{humanize_condition(condition)}",
            line: line || step.line,
            details: ast_to_text(last_expression(body)),
            source_snippet: ast_to_text(condition)
          }),
          expanded_step(step, %{
            type: :reaction,
            kind: :assert_result,
            provenance: :branch,
            status: normalized_status(step, :matched),
            label: "Return #{humanize_result(step.result)}",
            line: line || step.line,
            details: ast_to_text(last_expression(body)),
            source_snippet: ast_to_text(last_expression(body))
          })
        ]

      true ->
        []
    end
  end

  defp expand_if_rule(step, line, condition, opts) do
    do_branch = Keyword.get(opts, :do)
    else_branch = Keyword.get(opts, :else)
    do_matches? = branch_matches_result?(do_branch, step.result)
    else_matches? = branch_matches_result?(else_branch, step.result)

    matched_label =
      cond do
        do_matches? -> "Matched #{humanize_condition(condition)}"
        else_matches? -> "Matched not (#{humanize_condition(condition)})"
        true -> "Evaluated #{humanize_condition(condition)}"
      end

    matched_body = if(do_matches?, do: do_branch, else: else_branch)

    [
      expanded_step(step, %{
        type: :reaction,
        kind: :rule_branch,
        provenance: :branch,
        status: :matched,
        label: matched_label,
        line: line || step.line,
        details: ast_to_text(last_expression(matched_body)),
        source_snippet: ast_to_text(condition)
      }),
      expanded_step(step, %{
        type: :reaction,
        kind: :assert_result,
        provenance: :branch,
        status: normalized_status(step, :matched),
        label: "Return #{humanize_result(step.result)}",
        line: line || step.line,
        details: ast_to_text(last_expression(matched_body)),
        source_snippet: ast_to_text(last_expression(matched_body))
      })
    ]
  end

  defp expand_case_rule(step, line, expr, clauses) do
    matched_index = matched_clause_index(clauses, step.result)

    [
      expanded_step(step, %{
        type: :reaction,
        kind: :rule_check,
        status: :passed,
        label: "Compare #{humanize_case_expr(expr)}",
        line: line || step.line,
        details: ast_to_text(expr),
        source_snippet: ast_to_text(expr)
      })
      | expand_case_branches(step, line, clauses, matched_index)
    ]
  end

  defp expand_case_branches(step, line, clauses, matched_index) do
    clauses
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{:->, _meta, [[pattern], body]}, index} when index == matched_index ->
        [
          expanded_step(step, %{
            type: :reaction,
            kind: :rule_branch,
            provenance: :branch,
            status: :matched,
            label: "Matched #{humanize_case_pattern(pattern)}",
            line: line || step.line,
            details: ast_to_text(last_expression(body)),
            source_snippet: ast_to_text(pattern)
          }),
          expanded_step(step, %{
            type: :reaction,
            kind: :assert_result,
            provenance: :branch,
            status: normalized_status(step, :matched),
            label: "Return #{humanize_result(step.result)}",
            line: line || step.line,
            details: ast_to_text(last_expression(body)),
            source_snippet: ast_to_text(last_expression(body))
          })
        ]

      _ ->
        []
    end)
  end

  defp maybe_assert_result_step(step) do
    if step.result do
      [
        expanded_step(step, %{
          type: :reaction,
          kind: :assert_result,
          provenance: :branch,
          status: normalized_status(step, :matched),
          label: "Assert #{humanize_result(step.result)}",
          details: step.result,
          source_snippet: step.result
        })
      ]
    else
      []
    end
  end

  defp expanded_step(step, attrs) do
    %{
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
      test_kind: step.test_kind
    }
  end

  defp fetch_module_ast(module_name, node_lookup) do
    case Map.get(node_lookup.code, module_name) do
      %{ast: ast, alias_map: alias_map} -> {:ok, ast, alias_map}
      _ -> :error
    end
  end

  defp find_function_body(module_ast, function_name) do
    Macro.prewalk(module_ast, :error, fn
      {kind, _meta, [{^function_name, _, _args}, [do: body]]} = node, :error
      when kind in [:def, :defp] ->
        {node, {:ok, body}}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp with_reached_count(step, clauses) do
    cond do
      step.status in [:passed, :matched] ->
        Enum.count(clauses)

      String.contains?(step.result || "", "unknown provider") ->
        1

      true ->
        1
    end
  end

  defp summarize_with_expr(expr, alias_map, current_module, node_lookup) do
    case expr do
      {fun, _, args} when is_atom(fun) and is_list(args) ->
        summarize_local_with_expr(fun, alias_map, current_module, node_lookup, expr)

      {{:., _, [module_ast, fun]}, _, _args} ->
        module_name = resolve_module_name(module_ast, alias_map)
        fun_name = to_string(fun)

        cond do
          fun_name == "verify_signature" ->
            %{
              label: "Verify provider signature",
              node_id: resolve_node_id(module_name, node_lookup),
              focus_node_id: resolve_node_id(module_name, node_lookup),
              kind: :trigger_receive,
              details: ast_to_text(expr)
            }

          fun_name == "parse_event" ->
            %{
              label: "Parse provider event",
              node_id: resolve_node_id(module_name, node_lookup),
              focus_node_id: resolve_node_id(module_name, node_lookup),
              kind: :read,
              details: ast_to_text(expr)
            }

          fun_name == "persist_event" ->
            target = helper_focus_node(module_name, :persist_event, node_lookup)

            %{
              label: "Persist webhook event",
              node_id: target || resolve_node_id(module_name, node_lookup),
              focus_node_id: target || resolve_node_id(module_name, node_lookup),
              kind: :write,
              details: ast_to_text(expr)
            }

          fun_name == "dispatch_async_job" ->
            target = helper_focus_node(module_name, :dispatch_async_job, node_lookup)

            %{
              label: "Enqueue webhook processor job",
              node_id: target || resolve_node_id(module_name, node_lookup),
              focus_node_id: target || resolve_node_id(module_name, node_lookup),
              kind: :job_enqueue,
              details: ast_to_text(expr)
            }

          true ->
            %{
              label: "Execute #{fun_name}",
              node_id: resolve_node_id(module_name, node_lookup),
              focus_node_id: resolve_node_id(module_name, node_lookup),
              kind: :action_execute,
              details: ast_to_text(expr)
            }
        end

      _ ->
        %{
          label: ast_to_text(expr),
          node_id: nil,
          focus_node_id: nil,
          kind: :action_execute,
          details: nil
        }
    end
  end

  defp summarize_local_with_expr(fun, _alias_map, current_module, node_lookup, expr) do
    fun_name = to_string(fun)

    cond do
      fun_name == "verify_signature" ->
        %{
          label: "Verify provider signature",
          node_id: nil,
          focus_node_id: nil,
          kind: :trigger_receive,
          details: ast_to_text(expr)
        }

      fun_name == "parse_event" ->
        %{
          label: "Parse provider event",
          node_id: nil,
          focus_node_id: nil,
          kind: :read,
          details: ast_to_text(expr)
        }

      fun_name == "persist_event" ->
        target = helper_focus_node(current_module, :persist_event, node_lookup)

        %{
          label: "Persist event",
          node_id: target,
          focus_node_id: target,
          kind: :write,
          details: ast_to_text(expr)
        }

      fun_name == "dispatch_async_job" ->
        target = helper_focus_node(current_module, :dispatch_async_job, node_lookup)

        %{
          label: "Enqueue async job",
          node_id: target,
          focus_node_id: target,
          kind: :job_enqueue,
          details: ast_to_text(expr)
        }

      true ->
        %{
          label: ast_to_text(expr),
          node_id: nil,
          focus_node_id: nil,
          kind: :action_execute,
          details: nil
        }
    end
  end

  defp helper_focus_node(module_name, helper_name, node_lookup) when is_binary(module_name) do
    with {:ok, module_ast, alias_map} <- fetch_module_ast(module_name, node_lookup),
         {:ok, body} <- find_function_body(module_ast, helper_name) do
      collect_call_steps(
        body,
        alias_map,
        node_lookup,
        %{name: Atom.to_string(helper_name), kind: :test, line: nil},
        nil,
        nil
      )
      |> Enum.find_value(&(&1.focus_node_id || &1.node_id))
      |> Kernel.||(helper_focus_fallback(body, alias_map, node_lookup))
      |> base_node_id()
    end
  end

  defp helper_focus_node(_module_name, _helper_name, _node_lookup), do: nil

  defp helper_focus_fallback(body, alias_map, node_lookup) do
    Macro.prewalk(body, nil, fn
      {:|>, _, [left, {{:., _, [{:__aliases__, _, [:Ash, :Changeset]}, fun]}, _, args}]} = node,
      nil
      when fun in @ash_changeset_funs ->
        focus =
          left
          |> resolve_module_name(alias_map)
          |> resolve_optional_node_id(node_lookup)

        {node, focus || helper_focus_from_args(args || [], alias_map, node_lookup)}

      {:|>, _, [left, {{:., _, [{:__aliases__, _, [:Ash]}, fun]}, _, args}]} = node, nil
      when fun in @ash_funs ->
        focus =
          left
          |> resolve_module_name(alias_map)
          |> resolve_optional_node_id(node_lookup)

        {node, focus || helper_focus_from_args(args || [], alias_map, node_lookup)}

      {{:., _, [{:__aliases__, _, [:Ash, :Changeset]}, fun]}, _, [resource_ast | _rest]} = node,
      nil
      when fun in @ash_changeset_funs ->
        focus =
          resource_ast
          |> resolve_module_name(alias_map)
          |> resolve_optional_node_id(node_lookup)

        {node, focus}

      {{:., _, [{:__aliases__, _, [:Ash]}, fun]}, _, [resource_ast | _rest]} = node, nil
      when fun in @ash_funs ->
        focus =
          resource_ast
          |> resolve_module_name(alias_map)
          |> resolve_optional_node_id(node_lookup)

        {node, focus}

      {{:., _, [{:__aliases__, _, [:Oban]}, :insert]}, _, [job_ast]} = node, nil ->
        focus =
          case job_ast do
            {{:., _, [module_ast, :new]}, _, _args} ->
              module_ast
              |> resolve_module_name(alias_map)
              |> resolve_optional_node_id(node_lookup)

            _ ->
              nil
          end

        {node, focus}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp helper_focus_from_args([resource_ast | _rest], alias_map, node_lookup) do
    resource_ast
    |> resolve_module_name(alias_map)
    |> resolve_optional_node_id(node_lookup)
  end

  defp helper_focus_from_args(_args, _alias_map, _node_lookup), do: nil

  defp extract_scenario_metadata(body) do
    Macro.prewalk(body, [], fn
      {:@, _meta, [{:scenario, _, [value]}]} = node, acc ->
        {node, [normalize_scenario_attr(value) | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.reduce(%{}, &Map.merge(&2, &1))
  end

  defp normalize_scenario_attr(value) do
    case literal_value(value) do
      literal when is_map(literal) ->
        literal

      literal when is_list(literal) ->
        if Keyword.keyword?(literal), do: Map.new(literal), else: %{}

      _ ->
        %{}
    end
  end

  defp extract_test_blocks(body) do
    Macro.prewalk(body, [], fn
      {:test, meta, [name, [do: block]]} = node, acc ->
        {node, [%{name: stringify(name), kind: :test, line: meta[:line], block: block} | acc]}

      {:test, meta, [name, _context_ast, [do: block]]} = node, acc ->
        {node, [%{name: stringify(name), kind: :test, line: meta[:line], block: block} | acc]}

      {:property, meta, [name, [do: block]]} = node, acc ->
        {node, [%{name: stringify(name), kind: :property, line: meta[:line], block: block} | acc]}

      {:property, meta, [name, _context_ast, [do: block]]} = node, acc ->
        {node, [%{name: stringify(name), kind: :property, line: meta[:line], block: block} | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp attach_focus_targets(steps) do
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

  defp assign_step_ids(steps) do
    Enum.with_index(steps, 1)
    |> Enum.map(fn {step, index} -> Map.put(step, :id, "step-#{index}") end)
  end

  defp summarize_evidence(flow) do
    %{
      executed_steps: Enum.count(flow, &(&1.provenance == :executed)),
      expanded_steps: Enum.count(flow, &(&1.provenance == :expanded)),
      branch_steps: Enum.count(flow, &(&1.provenance == :branch)),
      passed_steps: Enum.count(flow, &(&1.status == :passed)),
      failed_steps: Enum.count(flow, &(&1.status == :failed)),
      short_circuit_steps: Enum.count(flow, &(&1.status == :short_circuit))
    }
  end

  defp collapse_duplicate_runtime_steps(steps) do
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

  defp duplicate_runtime_step?(left, right) do
    runtime_step_key(left) == runtime_step_key(right)
  end

  defp runtime_step_key(step) do
    {
      step.provenance,
      step.type,
      step.node_id,
      step.focus_node_id,
      step.kind,
      step.action || runtime_step_operation(step.module_function) || step.label,
      step.test_name
    }
  end

  defp runtime_step_operation(nil), do: nil

  defp runtime_step_operation(module_function) when is_binary(module_function) do
    module_function
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.split("/")
    |> List.first()
  end

  defp merge_runtime_steps(previous, current) do
    merged_focus_targets =
      (Map.get(previous, :focus_targets, []) ++ Map.get(current, :focus_targets, []))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    merged_emits =
      (Map.get(previous, :emits, []) ++ Map.get(current, :emits, []))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    current
    |> Map.put(:focus_targets, merged_focus_targets)
    |> Map.put(:emits, merged_emits)
    |> Map.put(:reacts_to, Map.get(current, :reacts_to) || Map.get(previous, :reacts_to))
    |> Map.put(:action, Map.get(current, :action) || Map.get(previous, :action))
    |> Map.put(:actor, Map.get(current, :actor) || Map.get(previous, :actor))
    |> Map.put(
      :module_function,
      Map.get(current, :module_function) || Map.get(previous, :module_function)
    )
    |> Map.put(
      :source_snippet,
      Map.get(current, :source_snippet) || Map.get(previous, :source_snippet)
    )
    |> Map.put(:result, Map.get(current, :result) || Map.get(previous, :result))
    |> Map.put(:details, Map.get(current, :details) || Map.get(previous, :details))
    |> Map.put(:line, Map.get(current, :line) || Map.get(previous, :line))
    |> Map.put(:status, merged_runtime_status(previous.status, current.status))
  end

  defp merged_runtime_status(:failed, _), do: :failed
  defp merged_runtime_status(_, :failed), do: :failed
  defp merged_runtime_status(:short_circuit, _), do: :short_circuit
  defp merged_runtime_status(_, :short_circuit), do: :short_circuit
  defp merged_runtime_status(_previous, current), do: current

  defp merge_flow_hints(flow, []), do: flow

  defp merge_flow_hints(flow, hints) do
    flow
    |> Enum.with_index()
    |> Enum.map(fn {step, index} ->
      case Enum.at(hints, index) do
        nil -> step
        hint -> merge_flow_hint(step, hint)
      end
    end)
  end

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
    |> maybe_put(:id, Map.get(hint, :id))
    |> maybe_put(:type, Map.get(hint, :type))
    |> maybe_put(:kind, Map.get(hint, :kind))
    |> maybe_put(:label, Map.get(hint, :label))
    |> maybe_put(:actor, Map.get(hint, :actor))
    |> maybe_put(:details, Map.get(hint, :details))
    |> maybe_put(:provenance, Map.get(hint, :provenance))
    |> maybe_put(:status, Map.get(hint, :status))
    |> maybe_put(:module_function, Map.get(hint, :module_function))
    |> maybe_put(:source_snippet, Map.get(hint, :source_snippet))
    |> maybe_put(:result, Map.get(hint, :result))
    |> maybe_put(:emits, non_empty_list(Map.get(hint, :emits)))
    |> maybe_put(:reacts_to, Map.get(hint, :reacts_to))
    |> maybe_put(:focus_node_id, compatible_focus(step, Map.get(hint, :focus_node_id)))
    |> Map.put(:focus_targets, merged_targets)
  end

  defp compatible_focus(step, hinted_focus) do
    if compatible_focus_target?(step, hinted_focus), do: hinted_focus, else: step.focus_node_id
  end

  defp compatible_focus_target?(_step, nil), do: false

  defp compatible_focus_target?(step, target) do
    target_base = base_node_id(target)
    step_base = base_node_id(step.node_id)
    step_focus_base = base_node_id(step.focus_node_id)

    target_base in Enum.reject(
      [step_base, step_focus_base | Enum.map(step.focus_targets, &base_node_id/1)],
      &is_nil/1
    )
  end

  defp normalize_flow_hints(nil, _node_lookup), do: []
  defp normalize_flow_hints(flow, _node_lookup) when flow in [%{}, []], do: []

  defp normalize_flow_hints(flow, node_lookup) when is_list(flow) do
    flow
    |> Enum.with_index()
    |> Enum.map(fn {step, index} -> normalize_flow_hint(step, index, node_lookup) end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_flow_hints(_flow, _node_lookup), do: []

  defp normalize_flow_hint(step, index, node_lookup) when is_map(step) do
    node_id =
      step
      |> first_present([:node_id, :node])
      |> resolve_optional_node_id(node_lookup)

    focus_node_id =
      step
      |> first_present([:focus_node_id, :graph_node, :graph_node_id])
      |> normalize_focus_override(node_id, node_lookup)
      |> Kernel.||(
        resolve_step_focus(
          node_id,
          first_present(step, [:step_name, :focus_step_name]),
          node_lookup
        )
      )
      |> Kernel.||(node_id)

    %{
      id: normalize_optional_string(first_present(step, [:id])) || "step-#{index + 1}",
      type: first_present(step, [:type]) || infer_flow_type(index),
      kind: first_present(step, [:kind]),
      provenance: first_present(step, [:provenance]),
      status: first_present(step, [:status]),
      label: normalize_optional_string(first_present(step, [:label])),
      node_id: node_id,
      focus_node_id: focus_node_id,
      focus_targets: explicit_focus_targets(step, node_lookup),
      emits: normalize_string_list(first_present(step, [:emits])),
      reacts_to: normalize_optional_string(first_present(step, [:reacts_to])),
      action: normalize_optional_string(first_present(step, [:action])),
      actor: normalize_optional_string(first_present(step, [:actor])),
      module_function: normalize_optional_string(first_present(step, [:module_function])),
      source_snippet: normalize_optional_string(first_present(step, [:source_snippet])),
      result: normalize_optional_string(first_present(step, [:result])),
      details: normalize_optional_string(first_present(step, [:details]))
    }
  end

  defp normalize_flow_hint(_step, _index, _node_lookup), do: nil

  defp derive_flow_summaries(flow) do
    nodes =
      flow
      |> Enum.flat_map(fn step ->
        [step.node_id, step.focus_node_id | Enum.map(step.focus_targets, &base_node_id/1)]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&base_node_id/1)
      |> Enum.uniq()

    graph_path =
      flow
      |> Enum.flat_map(fn step ->
        [step.focus_node_id || step.node_id | step.focus_targets]
      end)
      |> Enum.reject(&is_nil/1)
      |> distinct_consecutive()

    {nodes, graph_path}
  end

  defp infer_category(scenario_meta, traced_tests) do
    cond do
      category = first_present(scenario_meta, [:category]) ->
        category

      first_present(scenario_meta, [:compliance_links])
      |> normalize_string_list()
      |> Enum.any?() ->
        :compliance

      Enum.any?(traced_tests, &(&1.test_case.kind == :property)) ->
        :property

      true ->
        :invariant
    end
  end

  defp infer_level(traced_tests, node_lookup) do
    levels =
      traced_tests
      |> Enum.flat_map(&Map.get(&1, :entry_points, []))
      |> Enum.map(&entry_point_level(&1, node_lookup))
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

  defp entry_point_level(
         %{node_id: node_id, module_function: module_function, kind: kind},
         node_lookup
       ) do
    node = Map.get(node_lookup.by_id, base_node_id(node_id || ""))

    cond do
      node == nil ->
        case kind do
          kind when kind in [:action_prepare, :action_execute] -> :action
          kind when kind in [:rule_check, :rule_branch] -> :rule
          _ -> nil
        end

      node.type == "trigger" and String.ends_with?(module_function || "", ".handle_webhook") ->
        :webhook

      node.type == "job" and String.ends_with?(module_function || "", ".perform") ->
        :job

      node.type == "transfer" ->
        :transfer

      node.type == "reactor" ->
        :reactor

      node.type == "resource" ->
        :action

      node.type == "rule" ->
        :rule

      true ->
        nil
    end
  end

  defp build_code_lookup(project_root) do
    @code_globs
    |> Enum.flat_map(&Path.wildcard(Path.join(project_root, &1)))
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn file_path, acc ->
      with {:ok, content} <- File.read(file_path),
           {:ok, ast} <- Code.string_to_quoted(content) do
        alias_map = extract_alias_map(ast)

        extract_modules(ast)
        |> Enum.reduce(acc, fn {module_name, module_ast}, inner ->
          Map.put(inner, module_name, %{
            ast: module_ast,
            alias_map: alias_map,
            file: file_path,
            source: content
          })
        end)
      else
        _ -> acc
      end
    end)
  end

  defp extract_modules(ast) do
    Macro.prewalk(ast, [], fn
      {:defmodule, _meta, [{:__aliases__, _, parts}, _body]} = node, acc ->
        {node, [{Enum.join(parts, "."), node} | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp extract_alias_map(ast) do
    Macro.prewalk(ast, %{}, fn
      {:alias, _meta, args} = node, acc ->
        {node, merge_alias_map(acc, alias_entries_from_ast(args))}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp alias_entries_from_ast([{:__aliases__, _, base}, [do: {:__block__, _, nested}]]) do
    Enum.flat_map(nested, fn
      {:__aliases__, _, [leaf]} ->
        [{to_string(leaf), Enum.join(base ++ [leaf], ".")}]

      _ ->
        []
    end)
  end

  defp alias_entries_from_ast([{:__aliases__, _, parts}]), do: default_alias_entry(parts)

  defp alias_entries_from_ast([{:__aliases__, _, parts}, opts]) when is_list(opts) do
    explicit_alias = Keyword.get(opts, :as)

    if explicit_alias do
      [{alias_name(explicit_alias), Enum.join(parts, ".")}]
    else
      default_alias_entry(parts)
    end
  end

  defp alias_entries_from_ast(_args), do: []

  defp default_alias_entry(parts) do
    [{List.last(parts) |> to_string(), Enum.join(parts, ".")}]
  end

  defp alias_name({:__aliases__, _, parts}), do: List.last(parts) |> to_string()
  defp alias_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp alias_name(other), do: to_string(other)

  defp merge_alias_map(left, right), do: Map.merge(left, Map.new(right))

  defp resolve_module_name({:__aliases__, _, parts}, alias_map) do
    parts
    |> Enum.map(&to_string/1)
    |> resolve_alias_parts(alias_map)
  end

  defp resolve_module_name(atom, _alias_map) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp resolve_module_name(binary, _alias_map) when is_binary(binary), do: binary
  defp resolve_module_name(_, _alias_map), do: nil

  defp resolve_alias_parts([head | tail], alias_map) do
    case Map.get(alias_map, head) do
      nil -> Enum.join([head | tail], ".")
      resolved when tail == [] -> resolved
      resolved -> Enum.join([resolved | tail], ".")
    end
  end

  defp resolve_alias_parts([], _alias_map), do: nil

  defp build_node_lookup(nodes, code_lookup) do
    by_id = Map.new(nodes, &{&1.id, &1})

    aliases =
      nodes
      |> Enum.flat_map(fn node ->
        module_name = node.module || node.id
        parts = String.split(module_name, ".")
        short = List.last(parts)
        domain_short = parts |> Enum.take(-2) |> Enum.join(".")
        id_short = node.id |> String.replace_prefix((List.first(parts) || "") <> ".", "")

        [
          {module_name, node.id},
          {node.id, node.id},
          {short, node.id},
          {domain_short, node.id},
          {id_short, node.id}
        ]
      end)
      |> Enum.reject(fn {key, _value} -> is_nil(key) or key == "" end)
      |> Enum.into(%{})

    %{by_id: by_id, aliases: aliases, code: code_lookup}
  end

  defp resolve_node_id(nil, _node_lookup), do: nil

  defp resolve_node_id(node_name, node_lookup) do
    normalized = stringify(node_name)

    cond do
      Map.has_key?(node_lookup.aliases, normalized) ->
        Map.fetch!(node_lookup.aliases, normalized)

      Map.has_key?(node_lookup.by_id, normalized) ->
        normalized

      true ->
        nil
    end
  end

  defp resolve_optional_node_id(nil, _node_lookup), do: nil

  defp resolve_optional_node_id(node_name, node_lookup),
    do: resolve_node_id(node_name, node_lookup)

  defp resolve_step_focus(nil, _step_name, _node_lookup), do: nil
  defp resolve_step_focus(_node_id, nil, _node_lookup), do: nil

  defp resolve_step_focus(node_id, step_name, node_lookup) do
    case Map.get(node_lookup.by_id, node_id) do
      %{steps: steps} when is_list(steps) ->
        steps
        |> Enum.with_index()
        |> Enum.find_value(fn {step, index} ->
          current_name = Map.get(step, :name) || Map.get(step, "name")

          if normalize_name(current_name) == normalize_name(step_name) do
            "#{node_id}:step:#{index}"
          end
        end)

      _ ->
        nil
    end
  end

  defp normalize_focus_override(nil, _node_id, _node_lookup), do: nil

  defp normalize_focus_override(focus_value, node_id, node_lookup) do
    graph_id = stringify(focus_value)

    cond do
      node_id && String.starts_with?(graph_id, ":step:") ->
        "#{node_id}#{graph_id}"

      node_id && String.starts_with?(graph_id, ":action:") ->
        "#{node_id}#{graph_id}"

      String.contains?(graph_id, ":step:") ->
        [base, suffix] = String.split(graph_id, ":step:", parts: 2)

        case resolve_node_id(base, node_lookup) do
          nil -> nil
          resolved -> "#{resolved}:step:#{suffix}"
        end

      String.contains?(graph_id, ":action:") ->
        [base, suffix] = String.split(graph_id, ":action:", parts: 2)

        case resolve_node_id(base, node_lookup) do
          nil -> nil
          resolved -> "#{resolved}:action:#{suffix}"
        end

      true ->
        resolve_node_id(graph_id, node_lookup)
    end
  end

  defp explicit_focus_targets(step, node_lookup) do
    explicit_targets =
      step
      |> first_present([:focus_targets, :next_graph_nodes])
      |> normalize_string_list()

    resolved_explicit_targets =
      explicit_targets
      |> Enum.map(&normalize_focus_override(&1, nil, node_lookup))
      |> Enum.reject(&is_nil/1)

    step_names =
      step
      |> first_present([:next_step_names])
      |> normalize_string_list()

    if step_names == [] do
      resolved_explicit_targets
    else
      base_targets =
        if explicit_targets != [] do
          explicit_targets
          |> Enum.map(&resolve_node_id(&1, node_lookup))
        else
          step
          |> first_present([:next_nodes])
          |> normalize_string_list()
          |> Enum.map(&resolve_node_id(&1, node_lookup))
        end

      base_targets
      |> Enum.zip(step_names)
      |> Enum.map(fn {next_node_id, step_name} ->
        resolve_step_focus(next_node_id, step_name, node_lookup) || next_node_id
      end)
      |> Enum.reject(&is_nil/1)
    end
  end

  defp build_action_focus(node_id, action_name, node_lookup) do
    case Map.get(node_lookup.by_id, node_id) do
      %{actions: actions} when is_list(actions) ->
        normalized_action = normalize_name(action_name)

        if Enum.any?(actions, fn action ->
             current = Map.get(action, :name) || Map.get(action, "name")
             normalize_name(current) == normalized_action
           end) do
          "#{node_id}:action:#{action_name}"
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp extract_ash_action(args) when is_list(args) do
    Enum.reduce_while(args, {nil, []}, fn arg, {action, seen} ->
      cond do
        action_name = extract_action_name(arg) ->
          {:halt, {action_name, seen ++ [arg]}}

        action_name = extract_keyword_action(arg) ->
          {:halt, {action_name, seen ++ [arg]}}

        true ->
          {:cont, {action, seen ++ [arg]}}
      end
    end)
  end

  defp extract_ash_action(_args), do: {nil, []}

  defp extract_keyword_action(keyword_ast) when is_list(keyword_ast) do
    keyword_ast
    |> Enum.find_value(fn
      {:action, value} -> extract_action_name(value)
      _ -> nil
    end)
  end

  defp extract_keyword_action(_keyword_ast), do: nil

  defp infer_module_focus(node_id, %{type: type} = node, fun_name, node_lookup)
       when type in ["resource", "job", "rule"] do
    case build_action_focus(node_id, fun_name, node_lookup) do
      nil -> node.id
      action_focus -> action_focus
    end
  end

  defp infer_module_focus(node_id, %{type: type}, fun_name, node_lookup)
       when type in ["transfer", "reactor"] do
    resolve_step_focus(node_id, fun_name, node_lookup) || node_id
  end

  defp infer_module_focus(node_id, _node, _fun_name, _node_lookup), do: node_id

  defp resolve_pipeline_focus(node_id, pipeline_step, type) do
    step_name = Map.get(pipeline_step, :name) || Map.get(pipeline_step, "name")

    cond do
      is_nil(step_name) ->
        node_id

      type in ["transfer", "reactor"] ->
        "#{node_id}:step:#{Map.get(pipeline_step, :step_index) || Map.get(pipeline_step, "step_index") || 0}"

      true ->
        node_id
    end
  end

  defp pipeline_step_target_node_id(node_id, pipeline_step) do
    Map.get(pipeline_step, :target_resource) ||
      Map.get(pipeline_step, "target_resource") ||
      node_id
  end

  defp pipeline_step_kind(pipeline_step) do
    case Map.get(pipeline_step, :step_kind) || Map.get(pipeline_step, "step_kind") do
      :write -> :write
      "write" -> :write
      :read -> :read
      "read" -> :read
      _ -> :action_execute
    end
  end

  defp pipeline_step_label(node_id, pipeline_step, description) do
    step_name = Map.get(pipeline_step, :name) || Map.get(pipeline_step, "name")

    cond do
      is_binary(description) and description != "" -> description
      is_atom(step_name) -> "#{List.last(String.split(node_id, "."))}.#{step_name}"
      is_binary(step_name) -> "#{List.last(String.split(node_id, "."))}.#{step_name}"
      true -> "Expand #{List.last(String.split(node_id, "."))}"
    end
  end

  defp pipeline_step_description(pipeline_step) do
    Map.get(pipeline_step, :description) || Map.get(pipeline_step, "description")
  end

  defp pipeline_step_snippet(pipeline_step) do
    Map.get(pipeline_step, :source_snippet) || Map.get(pipeline_step, "source_snippet")
  end

  defp extract_action_name(action_ast) do
    case literal_value(action_ast) do
      action when is_atom(action) -> Atom.to_string(action)
      action when is_binary(action) -> action
      _ -> nil
    end
  end

  defp infer_assertion_context(pattern_ast) do
    result = ast_to_text(pattern_ast)

    %{
      result: result,
      status: infer_status_from_pattern(pattern_ast)
    }
  end

  defp infer_status_from_pattern({:ok, _}), do: :passed
  defp infer_status_from_pattern(:ok), do: :passed
  defp infer_status_from_pattern(true), do: :passed
  defp infer_status_from_pattern({:error, _, _}), do: :failed
  defp infer_status_from_pattern({:error, _}), do: :failed
  defp infer_status_from_pattern(_), do: :matched

  defp normalized_status(step, fallback), do: step.status || fallback

  defp matched_clause_index(clauses, result) do
    Enum.find_index(clauses, fn
      {:->, _, [_patterns, body]} -> branch_matches_result?(body, result)
      _ -> false
    end)
  end

  defp branch_matches_result?(body, result) do
    branch_signature(last_expression(body)) == result_signature(result)
  end

  defp branch_signature(ast) do
    ast
    |> result_signature_from_ast()
  end

  defp result_signature(result) when is_binary(result) do
    cond do
      String.starts_with?(result, "{:error,") ->
        [_, code | _] = Regex.run(~r/^\{\:error,\s*(:[a-zA-Z0-9_]+)/, result) || [nil, nil]
        {:error, code}

      String.starts_with?(result, "{:ok,") ->
        :ok

      result == ":ok" ->
        :ok

      true ->
        result
    end
  end

  defp result_signature(_result), do: nil

  defp result_signature_from_ast({:__block__, _, exprs}),
    do: result_signature_from_ast(List.last(exprs))

  defp result_signature_from_ast(:ok), do: :ok
  defp result_signature_from_ast({:ok, _}), do: :ok

  defp result_signature_from_ast({:{}, _, [:error, code, _msg]}),
    do: {:error, extract_signature_code(code)}

  defp result_signature_from_ast({:{}, _, [:error, code]}),
    do: {:error, extract_signature_code(code)}

  defp result_signature_from_ast({:{}, _, values}) do
    case Enum.map(values, &literal_value/1) do
      [:ok, _] -> :ok
      [:error, code, _msg] -> {:error, extract_signature_code(code)}
      [:error, code] -> {:error, extract_signature_code(code)}
      other -> ast_to_text({:{}, [], Enum.map(other, &literal_to_ast/1)})
    end
  end

  defp result_signature_from_ast(other), do: ast_to_text(other)

  defp extract_signature_code(code) when is_atom(code), do: ":#{code}"
  defp extract_signature_code(code) when is_binary(code), do: code
  defp extract_signature_code(code), do: ast_to_text(code)

  defp literal_to_ast(value) when is_atom(value), do: value
  defp literal_to_ast(value), do: value

  defp humanize_condition(true), do: "fallback branch"
  defp humanize_condition(condition), do: condition |> ast_to_text() |> String.replace("_", " ")

  defp humanize_case_expr(expr), do: expr |> ast_to_text() |> String.replace("_", " ")
  defp humanize_case_pattern(pattern), do: pattern |> ast_to_text() |> String.replace("_", " ")

  defp humanize_result(nil), do: "result"
  defp humanize_result(result), do: result |> String.replace("_", " ")

  defp find_action(node, action_name) do
    Enum.find(Map.get(node, :actions, []), fn action ->
      normalize_name(Map.get(action, :name) || Map.get(action, "name")) ==
        normalize_name(action_name)
    end)
  end

  defp ash_kind(fun_name) when fun_name in ["get", "read", "read_one"], do: :read
  defp ash_kind(_fun_name), do: :action_execute

  defp ash_step_label(fun_name, node_id, action) do
    short = List.last(String.split(node_id, "."))

    case {fun_name, action} do
      {"get", _} -> "Load #{short}"
      {"read", _} -> "Read #{short}"
      {"read_one", _} -> "Read #{short}"
      {"create", nil} -> "Create #{short}"
      {"create", act} -> "Create #{short} via #{act}"
      {"update", nil} -> "Update #{short}"
      {"update", act} -> "Update #{short} via #{act}"
      {"destroy", nil} -> "Destroy #{short}"
      {"destroy", act} -> "Destroy #{short} via #{act}"
      _ -> "#{String.capitalize(fun_name)} #{short}"
    end
  end

  defp changeset_step_label(fun_name, node_id, action) do
    short = List.last(String.split(node_id, "."))

    case {fun_name, action} do
      {"for_create", nil} -> "Prepare create #{short}"
      {"for_create", act} -> "Prepare #{short}.#{act}"
      {"for_update", nil} -> "Prepare update #{short}"
      {"for_update", act} -> "Prepare #{short}.#{act}"
      {"for_read", nil} -> "Prepare read #{short}"
      {"for_read", act} -> "Prepare #{short}.#{act}"
      {"for_destroy", nil} -> "Prepare destroy #{short}"
      {"for_destroy", act} -> "Prepare #{short}.#{act}"
      _ -> "Prepare #{short}"
    end
  end

  defp infer_module_label(:assertion, short_name, _fun_name), do: "Evaluate #{short_name}"
  defp infer_module_label(:job, short_name, _fun_name), do: "Run #{short_name}"

  defp infer_module_label(:entry, short_name, "handle_webhook"),
    do: "Handle #{short_name} webhook"

  defp infer_module_label(:entry, short_name, fun_name),
    do: "#{String.capitalize(fun_name)} #{short_name}"

  defp infer_module_label(_type, short_name, fun_name),
    do: "#{String.capitalize(fun_name)} #{short_name}"

  defp infer_flow_type(0), do: :entry
  defp infer_flow_type(_index), do: :reaction

  defp generate_scenario_id(source_module, describe_name) do
    suffix =
      describe_name
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "_")
      |> String.trim("_")

    "#{source_module}.#{suffix}"
  end

  defp normalize_tags(tags) when is_list(tags), do: Enum.filter(tags, &is_atom/1)
  defp normalize_tags(_tags), do: []

  defp load_runtime_trace_lookup(project_root) do
    trace_dir = Path.join(project_root, ".foundry/scenario_traces")

    if File.dir?(trace_dir) do
      trace_dir
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.reduce(%{}, fn path, acc ->
        with {:ok, content} <- File.read(path),
             {:ok, payload} <- Jason.decode(content),
             scenario_id when is_binary(scenario_id) <- payload["scenario_id"] do
          Map.update(acc, scenario_id, [payload], &[payload | &1])
        else
          _ -> acc
        end
      end)
      |> Map.new(fn {scenario_id, payloads} ->
        sorted =
          Enum.sort_by(payloads, &Map.get(&1, "captured_at", ""), :desc)

        {scenario_id, sorted}
      end)
    else
      %{}
    end
  end

  defp lookup_runtime_trace(runtime_lookup, scenario_id, test_name) do
    normalized_test_name = normalize_runtime_test_name(test_name)

    runtime_lookup
    |> Map.get(scenario_id, [])
    |> Enum.find(fn payload ->
      trace_test_name = normalize_runtime_test_name(payload["test_name"] || "")

      trace_test_name == normalized_test_name or
        String.ends_with?(trace_test_name, normalized_test_name)
    end)
  end

  defp normalize_runtime_test_name(name) do
    name
    |> to_string()
    |> String.replace_prefix("test ", "")
    |> String.replace_prefix("property ", "")
  end

  defp first_present(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end

  defp literal_value({:%{}, _meta, pairs}) do
    pairs
    |> Enum.map(fn {key, value} -> {literal_value(key), literal_value(value)} end)
    |> Map.new()
  end

  defp literal_value({:__aliases__, _meta, parts}), do: Enum.join(parts, ".")

  defp literal_value({:{}, _meta, values}) do
    values
    |> Enum.map(&literal_value/1)
    |> List.to_tuple()
  end

  defp literal_value(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Enum.map(list, fn {key, value} -> {key, literal_value(value)} end)
    else
      Enum.map(list, &literal_value/1)
    end
  end

  defp literal_value(value), do: value

  defp block_statements({:__block__, _, statements}), do: statements
  defp block_statements(nil), do: []
  defp block_statements(statement), do: [statement]

  defp last_expression({:__block__, _, statements}), do: List.last(statements)
  defp last_expression(expression), do: expression

  defp shallow_stub_body?(:ok), do: true
  defp shallow_stub_body?({:__block__, _, [:ok]}), do: true
  defp shallow_stub_body?(_), do: false

  defp short_call_snippet(module_name, fun_name, args) do
    rendered_args =
      args
      |> List.wrap()
      |> Enum.take(2)
      |> Enum.map(&ast_to_text/1)
      |> Enum.join(", ")

    "#{module_name}.#{fun_name}(#{rendered_args})"
  end

  defp ast_to_text(nil), do: nil

  defp ast_to_text(ast) do
    ast
    |> Macro.to_string()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(value) when is_nil(value), do: []

  defp normalize_string_list(value) do
    value
    |> normalize_optional_string()
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value), do: to_string(value)

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: to_string(value)

  defp normalize_name(nil), do: nil
  defp normalize_name(value), do: value |> stringify() |> String.trim_leading(":")

  defp base_node_id(nil), do: nil

  defp base_node_id(graph_id) do
    graph_id
    |> stringify()
    |> String.split(":step:", parts: 2)
    |> List.first()
    |> String.split(":action:", parts: 2)
    |> List.first()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp non_empty_list([]), do: nil
  defp non_empty_list(nil), do: nil
  defp non_empty_list(list), do: list

  defp distinct_consecutive(list) do
    list
    |> Enum.reduce([], fn item, acc ->
      case acc do
        [^item | _] -> acc
        _ -> [item | acc]
      end
    end)
    |> Enum.reverse()
  end
end

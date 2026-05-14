defmodule Foundry.Context.Scenarios.Adapters.Trigger do
  @moduledoc false

  @behaviour ExTracer.Adapter

  alias ExTracer.CallTracer
  alias ExTracer.FlowExpander
  alias ExTracer.FlowSummary
  alias ExTracer.TestBlock
  alias Foundry.Context.Scenarios.Adapters.Oban
  alias Foundry.Context.Scenarios.ModuleIndex
  alias Foundry.Context.Scenarios.Utils

  @impl true
  def expand_step(step, lookup) do
    case Map.get(lookup.by_id, step.node_id || "") do
      %{type: "trigger"} = node ->
        if String.ends_with?(step.module_function || "", ".handle_webhook") do
          expand_with_chain_step(step, node, lookup)
        else
          []
        end

      _ ->
        []
    end
  end

  @impl true
  def classify_call(module_ast, fun, args, alias_map, lookup, opts) do
    Foundry.Context.Scenarios.CallClassifier.classify_ast_call(
      module_ast,
      fun,
      args,
      alias_map,
      lookup,
      opts
    )
  end

  @impl true
  def focus_for_helper(module_name, helper_name, lookup) do
    with {:ok, module_ast, alias_map} <- ModuleIndex.fetch_module_ast(module_name, lookup),
         {:ok, body} <- ModuleIndex.find_function_body(module_ast, helper_name) do
      CallTracer.collect_executed_trace(
        %TestBlock{name: Atom.to_string(helper_name), kind: :test, line: nil, block: body},
        alias_map,
        lookup,
        [__MODULE__, Oban]
      )
      |> Enum.find_value(&(&1.focus_node_id || &1.node_id))
      |> Kernel.||(Oban.focus_for_helper(module_name, helper_name, lookup))
      |> Utils.base_node_id()
    end
  end

  def expand_with_chain_step(step, node, lookup) do
    with {:ok, module_ast, alias_map} <- ModuleIndex.fetch_module_ast(node.module, lookup),
         {:ok, body} <- ModuleIndex.find_function_body(module_ast, :handle_webhook),
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
            lookup,
            index == reached_count - 1
          )
        end)

      clause_steps ++ with_result_steps(step, do_block, else_block)
    else
      _ -> FlowExpander.maybe_assert_result_step(step)
    end
  end

  defp expand_with_clause(
         step,
         {:<-, _, [_pattern, expr]},
         index,
         alias_map,
         current_module,
         lookup,
         last_reached?
       ) do
    expand_with_expr(step, expr, index, alias_map, current_module, lookup, last_reached?)
  end

  defp expand_with_clause(step, expr, index, alias_map, current_module, lookup, last_reached?) do
    expand_with_expr(step, expr, index, alias_map, current_module, lookup, last_reached?)
  end

  defp expand_with_expr(step, expr, _index, alias_map, current_module, lookup, last_reached?) do
    %{label: label, node_id: node_id, focus_node_id: focus_node_id, kind: kind, details: details} =
      summarize_with_expr(expr, alias_map, current_module, lookup)

    FlowSummary.expanded_step(step, %{
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
      source_snippet: Utils.ast_to_text(expr)
    })
  end

  defp with_result_steps(step, do_block, else_block) do
    cond do
      step.status in [:passed, :matched] ->
        [
          FlowSummary.expanded_step(step, %{
            type: :reaction,
            kind: :assert_result,
            provenance: :branch,
            status: step.status,
            label: "Return success result",
            details: Utils.ast_to_text(Utils.last_expression(do_block)),
            source_snippet: Utils.ast_to_text(Utils.last_expression(do_block))
          })
        ]

      step.status in [:failed, :short_circuit] ->
        [
          FlowSummary.expanded_step(step, %{
            type: :reaction,
            kind: :assert_result,
            provenance: :branch,
            status: :failed,
            label: "Return failure result",
            details: Utils.ast_to_text(Utils.last_expression(else_block)),
            source_snippet: Utils.ast_to_text(Utils.last_expression(else_block))
          })
        ]

      true ->
        FlowExpander.maybe_assert_result_step(step)
    end
  end

  defp with_reached_count(step, clauses) do
    if step.status in [:passed, :matched], do: Enum.count(clauses), else: 1
  end

  defp summarize_with_expr(expr, alias_map, current_module, lookup) do
    case expr do
      {fun, _, args} when is_atom(fun) and is_list(args) ->
        summarize_local_with_expr(fun, current_module, lookup, expr)

      {{:., _, [module_ast, fun]}, _, _args} ->
        module_name = ModuleIndex.resolve_module_name(module_ast, alias_map)
        fun_name = to_string(fun)

        cond do
          fun_name == "verify_signature" ->
            named_step("Verify provider signature", :trigger_receive, module_name, lookup, expr)

          fun_name == "parse_event" ->
            named_step("Parse provider event", :read, module_name, lookup, expr)

          fun_name == "persist_event" ->
            target = focus_for_helper(module_name, :persist_event, lookup)
            named_step("Persist event", :write, module_name, lookup, expr, target)

          fun_name == "dispatch_async_job" ->
            target = focus_for_helper(module_name, :dispatch_async_job, lookup)
            named_step("Enqueue async job", :job_enqueue, module_name, lookup, expr, target)

          true ->
            named_step("Execute #{fun_name}", :action_execute, module_name, lookup, expr)
        end

      _ ->
        %{
          label: Utils.ast_to_text(expr),
          node_id: nil,
          focus_node_id: nil,
          kind: :action_execute,
          details: nil
        }
    end
  end

  defp summarize_local_with_expr(fun, current_module, lookup, expr) do
    fun_name = to_string(fun)

    cond do
      fun_name == "verify_signature" ->
        %{
          label: "Verify provider signature",
          node_id: nil,
          focus_node_id: nil,
          kind: :trigger_receive,
          details: Utils.ast_to_text(expr)
        }

      fun_name == "parse_event" ->
        %{
          label: "Parse provider event",
          node_id: nil,
          focus_node_id: nil,
          kind: :read,
          details: Utils.ast_to_text(expr)
        }

      fun_name == "persist_event" ->
        target = focus_for_helper(current_module, :persist_event, lookup)

        %{
          label: "Persist event",
          node_id: target,
          focus_node_id: target,
          kind: :write,
          details: Utils.ast_to_text(expr)
        }

      fun_name == "dispatch_async_job" ->
        target = focus_for_helper(current_module, :dispatch_async_job, lookup)

        %{
          label: "Enqueue async job",
          node_id: target,
          focus_node_id: target,
          kind: :job_enqueue,
          details: Utils.ast_to_text(expr)
        }

      true ->
        %{
          label: Utils.ast_to_text(expr),
          node_id: nil,
          focus_node_id: nil,
          kind: :action_execute,
          details: nil
        }
    end
  end

  defp named_step(label, kind, module_name, lookup, expr, target \\ nil) do
    node_id = target || ModuleIndex.resolve_node_id(module_name, lookup)

    %{
      label: label,
      node_id: node_id,
      focus_node_id: node_id,
      kind: kind,
      details: Utils.ast_to_text(expr)
    }
  end
end

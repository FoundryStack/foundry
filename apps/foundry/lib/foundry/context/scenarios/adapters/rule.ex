defmodule Foundry.Context.Scenarios.Adapters.Rule do
  @moduledoc false

  @behaviour ExTracer.Adapter

  alias ExTracer.FlowExpander
  alias ExTracer.FlowSummary
  alias Foundry.Context.Scenarios.ModuleIndex
  alias Foundry.Context.Scenarios.Utils

  @impl true
  def expand_step(step, lookup) do
    case Map.get(lookup.by_id, step.node_id || "") do
      %{type: "rule"} = node ->
        if String.ends_with?(step.module_function || "", ".evaluate") do
          expand_rule_step(step, node, lookup)
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
  def focus_for_helper(_module_name, _helper_name, _lookup), do: nil

  defp expand_rule_step(step, node, lookup) do
    with {:ok, module_ast, _alias_map} <- ModuleIndex.fetch_module_ast(node.module, lookup),
         {:ok, body} <- ModuleIndex.find_function_body(module_ast, :evaluate) do
      statements = Utils.block_statements(body)
      {setup, [decision]} = Enum.split(statements, max(length(statements) - 1, 0))

      setup_steps = Enum.flat_map(setup, &rule_setup_steps(step, &1))

      branch_steps =
        case decision do
          {:cond, meta, [[do: clauses]]} ->
            expand_cond_rule(step, meta[:line], clauses)

          {:if, meta, [condition, opts]} ->
            expand_if_rule(step, meta[:line], condition, opts)

          {:case, meta, [expr, [do: clauses]]} ->
            expand_case_rule(step, meta[:line], expr, clauses)

          _ ->
            FlowExpander.maybe_assert_result_step(step)
        end

      setup_steps ++ branch_steps
    else
      _ -> FlowExpander.maybe_assert_result_step(step)
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
        FlowSummary.expanded_step(step, %{
          type: :reaction,
          kind: :rule_check,
          status: :passed,
          label: label,
          line: meta[:line] || step.line,
          details: Utils.ast_to_text(rhs),
          source_snippet: Utils.ast_to_text({:=, meta, [lhs, rhs]})
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
          FlowSummary.expanded_step(step, %{
            type: :reaction,
            kind: :rule_check,
            status: :passed,
            label: "Check #{humanize_condition(condition)}",
            line: line || step.line,
            details: "Branch not taken",
            source_snippet: Utils.ast_to_text(condition)
          })
        ]

      index == matched_index ->
        [
          FlowSummary.expanded_step(step, %{
            type: :reaction,
            kind: :rule_branch,
            provenance: :branch,
            status: :matched,
            label: "Matched #{humanize_condition(condition)}",
            line: line || step.line,
            details: Utils.ast_to_text(Utils.last_expression(body)),
            source_snippet: Utils.ast_to_text(condition)
          }),
          FlowSummary.expanded_step(step, %{
            type: :reaction,
            kind: :assert_result,
            provenance: :branch,
            status: FlowSummary.normalized_status(step, :matched),
            label: "Return #{humanize_result(step.result)}",
            line: line || step.line,
            details: Utils.ast_to_text(Utils.last_expression(body)),
            source_snippet: Utils.ast_to_text(Utils.last_expression(body))
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
      FlowSummary.expanded_step(step, %{
        type: :reaction,
        kind: :rule_branch,
        provenance: :branch,
        status: :matched,
        label: matched_label,
        line: line || step.line,
        details: Utils.ast_to_text(Utils.last_expression(matched_body)),
        source_snippet: Utils.ast_to_text(condition)
      }),
      FlowSummary.expanded_step(step, %{
        type: :reaction,
        kind: :assert_result,
        provenance: :branch,
        status: FlowSummary.normalized_status(step, :matched),
        label: "Return #{humanize_result(step.result)}",
        line: line || step.line,
        details: Utils.ast_to_text(Utils.last_expression(matched_body)),
        source_snippet: Utils.ast_to_text(Utils.last_expression(matched_body))
      })
    ]
  end

  defp expand_case_rule(step, line, expr, clauses) do
    matched_index = matched_clause_index(clauses, step.result)

    [
      FlowSummary.expanded_step(step, %{
        type: :reaction,
        kind: :rule_check,
        status: :passed,
        label: "Compare #{humanize_case_expr(expr)}",
        line: line || step.line,
        details: Utils.ast_to_text(expr),
        source_snippet: Utils.ast_to_text(expr)
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
          FlowSummary.expanded_step(step, %{
            type: :reaction,
            kind: :rule_branch,
            provenance: :branch,
            status: :matched,
            label: "Matched #{humanize_case_pattern(pattern)}",
            line: line || step.line,
            details: Utils.ast_to_text(Utils.last_expression(body)),
            source_snippet: Utils.ast_to_text(pattern)
          }),
          FlowSummary.expanded_step(step, %{
            type: :reaction,
            kind: :assert_result,
            provenance: :branch,
            status: FlowSummary.normalized_status(step, :matched),
            label: "Return #{humanize_result(step.result)}",
            line: line || step.line,
            details: Utils.ast_to_text(Utils.last_expression(body)),
            source_snippet: Utils.ast_to_text(Utils.last_expression(body))
          })
        ]

      _ ->
        []
    end)
  end

  defp matched_clause_index(clauses, result) do
    Enum.find_index(clauses, fn
      {:->, _, [_patterns, body]} -> branch_matches_result?(body, result)
      _ -> false
    end)
  end

  defp branch_matches_result?(body, result) do
    branch_signature(Utils.last_expression(body)) == result_signature(result)
  end

  defp branch_signature(ast), do: result_signature_from_ast(ast)

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
    case Enum.map(values, &Utils.literal_value/1) do
      [:ok, _] -> :ok
      [:error, code, _msg] -> {:error, extract_signature_code(code)}
      [:error, code] -> {:error, extract_signature_code(code)}
      other -> Utils.ast_to_text({:{}, [], Enum.map(other, &literal_to_ast/1)})
    end
  end

  defp result_signature_from_ast(other), do: Utils.ast_to_text(other)
  defp extract_signature_code(code) when is_atom(code), do: ":#{code}"
  defp extract_signature_code(code) when is_binary(code), do: code
  defp extract_signature_code(code), do: Utils.ast_to_text(code)
  defp literal_to_ast(value) when is_atom(value), do: value
  defp literal_to_ast(value), do: value
  defp humanize_condition(true), do: "fallback branch"

  defp humanize_condition(condition),
    do: condition |> Utils.ast_to_text() |> String.replace("_", " ")

  defp humanize_case_expr(expr), do: expr |> Utils.ast_to_text() |> String.replace("_", " ")

  defp humanize_case_pattern(pattern),
    do: pattern |> Utils.ast_to_text() |> String.replace("_", " ")

  defp humanize_result(nil), do: "result"
  defp humanize_result(result), do: String.replace(result, "_", " ")
end

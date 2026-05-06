defmodule ExTracer.CallTracer do
  @moduledoc false

  alias ExTracer.AdapterDispatcher
  alias ExTracer.Utils

  def collect_executed_trace(test_block, alias_map, lookup, adapters \\ []) do
    test_block.block
    |> Utils.block_statements()
    |> Enum.flat_map(fn statement ->
      collect_statement_steps(statement, alias_map, lookup, test_block, adapters)
    end)
  end

  defp collect_statement_steps({:assert, meta, [assertion_ast]}, alias_map, lookup, test_block, adapters) do
    line = meta[:line] || test_block.line

    case assertion_ast do
      {:=, _match_meta, [pattern, expr]} ->
        collect_call_steps(
          expr,
          alias_map,
          lookup,
          test_block,
          line,
          AdapterDispatcher.infer_assertion_context(pattern),
          adapters
        )

      expr ->
        collect_call_steps(
          expr,
          alias_map,
          lookup,
          test_block,
          line,
          AdapterDispatcher.infer_assertion_context(expr),
          adapters
        )
    end
  end

  defp collect_statement_steps({:=, meta, [_lhs, expr]}, alias_map, lookup, test_block, adapters) do
    collect_call_steps(expr, alias_map, lookup, test_block, meta[:line] || test_block.line, nil, adapters)
  end

  defp collect_statement_steps(statement, alias_map, lookup, test_block, adapters) do
    collect_call_steps(statement, alias_map, lookup, test_block, test_block.line, nil, adapters)
  end

  defp collect_call_steps(ast, alias_map, lookup, test_block, default_line, assertion_context, adapters) do
    Macro.prewalk(ast, [], fn
      {:|>, meta, [left, {{:., _, [module_ast, fun]}, _call_meta, args}]} = node, acc ->
        step =
          AdapterDispatcher.classify_ast_call(
            module_ast,
            fun,
            [left | args || []],
            alias_map,
            lookup,
            %{
              alias_map: alias_map,
              line: meta[:line] || default_line,
              test_name: test_block.name,
              test_kind: test_block.kind,
              assertion_context: assertion_context,
              adapters: adapters
            }
          )

        {node, if(step, do: acc ++ [step], else: acc)}

      {{:., meta, [module_ast, fun]}, _call_meta, args} = node, acc ->
        step =
          AdapterDispatcher.classify_ast_call(module_ast, fun, args || [], alias_map, lookup, %{
            alias_map: alias_map,
            line: meta[:line] || default_line,
            test_name: test_block.name,
            test_kind: test_block.kind,
            assertion_context: assertion_context,
            adapters: adapters
          })

        {node, if(step, do: acc ++ [step], else: acc)}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end
end

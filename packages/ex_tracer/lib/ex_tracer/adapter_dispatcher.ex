defmodule ExTracer.AdapterDispatcher do
  @moduledoc false

  def classify_ast_call(module_ast, fun, args, alias_map, lookup, opts) do
    Enum.find_value(Map.get(opts, :adapters, []), fn adapter ->
      if Code.ensure_loaded?(adapter) and function_exported?(adapter, :classify_call, 6) do
        adapter.classify_call(module_ast, fun, args, alias_map, lookup, opts)
      end
    end)
  end

  def infer_assertion_context(pattern_ast) do
    result = ExTracer.Utils.ast_to_text(pattern_ast)
    %{result: result, status: infer_status_from_pattern(pattern_ast)}
  end

  defp infer_status_from_pattern({:ok, _}), do: :passed
  defp infer_status_from_pattern(:ok), do: :passed
  defp infer_status_from_pattern(true), do: :passed
  defp infer_status_from_pattern({:error, _, _}), do: :failed
  defp infer_status_from_pattern({:error, _}), do: :failed
  defp infer_status_from_pattern(_), do: :matched
end

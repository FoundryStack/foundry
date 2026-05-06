defmodule Foundry.Context.Scenarios.Adapters.ASTClassifier do
  @behaviour ExTracer.Adapter

  def expand_step(_step, _lookup), do: []

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
end

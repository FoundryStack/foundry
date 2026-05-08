defmodule Foundry.Context.Scenarios.Adapters.Page do
  @moduledoc false

  @behaviour ExTracer.Adapter

  @impl true
  def expand_step(_step, _lookup), do: []

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
end

defmodule Foundry.SparkLint.Rule do
  @callback check(module :: module(), context :: Foundry.SparkLint.Context.t()) ::
    {:ok, [Foundry.SparkLint.Violation.t()]} | {:error, term()}
end

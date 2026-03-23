defmodule SparkLint.Rule do
  @moduledoc """
  Behaviour that every lint rule must implement.

  A rule receives a compiled module and a `SparkLint.Context` and returns
  either a (possibly empty) list of violations or an error tuple.
  """

  @callback check(module :: module(), context :: SparkLint.Context.t()) ::
              {:ok, [SparkLint.Violation.t()]} | {:error, term()}
end

defmodule Foundry.SparkLint.Context do
  @moduledoc """
  Passed to each rule. `metadata` is opaque — SparkLint never inspects it.
  Foundry.LintRules.* cast context.metadata to access manifest data.
  """
  defstruct [:module, :modules, metadata: %{}]
end

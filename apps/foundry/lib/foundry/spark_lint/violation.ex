defmodule Foundry.SparkLint.Violation do
  @enforce_keys [:rule, :module, :message, :severity]
  defstruct [:rule, :module, :message, :severity, :step, :attribute]
end

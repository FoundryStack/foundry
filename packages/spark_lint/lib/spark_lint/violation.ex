defmodule SparkLint.Violation do
  @moduledoc """
  A single lint finding emitted by a rule.

  Fields:
    - `:rule` — atom rule identifier (e.g. `:missing_paper_trail`)
    - `:module` — the module the violation was found in
    - `:message` — human-readable description
    - `:severity` — `:error | :warning | :info`
    - `:step` — optional, for step-scoped violations in Reactors
    - `:attribute` — optional, for attribute-scoped violations
  """

  @enforce_keys [:rule, :module, :message, :severity]
  defstruct [:rule, :module, :message, :severity, :step, :attribute]
end

defmodule ExTracer.Adapter do
  @moduledoc """
  Domain adapter for AST call classification and step expansion.
  """

  alias ExTracer.Lookup
  alias ExTracer.Step

  @callback expand_step(Step.t(), Lookup.t()) :: [Step.t()]
  @callback classify_call(Macro.t(), atom(), [Macro.t()], map(), Lookup.t(), map()) :: Step.t() | nil
  @callback focus_for_helper(String.t(), atom(), Lookup.t()) :: String.t() | nil

  @optional_callbacks classify_call: 6, focus_for_helper: 3
end

defmodule ExTracer.Adapter do
  @moduledoc """
  Pluggable behaviour for domain-specific call classification and step expansion.

  Adapters examine AST expressions and classify function calls into typed Steps.
  They can also expand steps (e.g., breaking a helper invocation into its
  constituent lower-level calls) and define focus targets for linking to
  graph nodes.

  Implement this behaviour to extract domain semantics from your test calls,
  mapping them onto your application's resource graph. See the README for
  a full example building an Accounts adapter.

  The adapter dispatcher (`ExTracer.AdapterDispatcher`) manages registration
  and invocation of multiple adapters in sequence.
  """

  alias ExTracer.Lookup
  alias ExTracer.Step

  @callback expand_step(Step.t(), Lookup.t()) :: [Step.t()]
  @callback classify_call(Macro.t(), atom(), [Macro.t()], map(), Lookup.t(), map()) :: Step.t() | nil
  @callback focus_for_helper(String.t(), atom(), Lookup.t()) :: String.t() | nil

  @optional_callbacks classify_call: 6, focus_for_helper: 3
end

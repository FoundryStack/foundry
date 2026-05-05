defmodule Foundry.Context.Scenarios.Adapter do
  @moduledoc false

  alias Foundry.Context.Scenarios.Lookup
  alias Foundry.Context.Scenarios.Step

  @callback expand_step(Step.t(), Lookup.t()) :: [Step.t()]
  @callback classify_call(map(), Lookup.t() | nil) :: Step.t() | nil
  @callback focus_for_helper(String.t(), atom(), Lookup.t()) :: String.t() | nil

  @optional_callbacks classify_call: 2, focus_for_helper: 3
end

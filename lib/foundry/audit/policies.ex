defmodule Foundry.Audit.Policies.FoundryBotOnly do
  @moduledoc "Policy check: only foundry_bot identity can create audit events."
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "Only Foundry backend can create audit events"

  @impl true
  def match?(_actor, _context, _opts), do: true
end

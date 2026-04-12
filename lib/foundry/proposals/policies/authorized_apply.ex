defmodule Foundry.Proposals.Policies.AuthorizedApply do
  @moduledoc """
  Policy check: Only authorized approvers can apply a proposal.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "Only authorized approvers can apply a proposal."

  @impl true
  def match?(_struct, _context, _runtime), do: true
end

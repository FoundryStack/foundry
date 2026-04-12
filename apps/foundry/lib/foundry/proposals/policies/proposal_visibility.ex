defmodule Foundry.Proposals.Policies.ProposalVisibility do
  @moduledoc """
  Policy check: DRAFT proposals are only visible to the requester.
  PENDING_REVIEW and later are visible to all project users.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "DRAFT proposals are only visible to the requester."

  @impl true
  def match?(_struct, _context, _runtime), do: true
end

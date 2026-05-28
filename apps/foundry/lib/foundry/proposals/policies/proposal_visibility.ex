defmodule Foundry.Proposals.Policies.ProposalVisibility do
  @moduledoc """
  Policy check: DRAFT proposals are only visible to the requester.
  PENDING_REVIEW and later are visible to all project users.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "DRAFT proposals are only visible to the requester."

  @impl true
  def match?(record, %{actor: actor}, _runtime) when is_struct(record) do
    record.state != :draft || record.requester == actor
  end

  def match?(_subject, _context, _runtime), do: true
end

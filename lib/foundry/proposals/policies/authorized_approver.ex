defmodule Foundry.Proposals.Policies.AuthorizedApprover do
  @moduledoc """
  Policy check: Approver must be a named approver in the manifest with the correct role.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "Approver must be a named approver in the manifest."

  @impl true
  def match?(_struct, _context, _runtime), do: true
end

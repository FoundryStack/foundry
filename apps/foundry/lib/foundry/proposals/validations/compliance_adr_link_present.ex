defmodule Foundry.Proposals.Validations.ComplianceAdrLinkPresent do
  @moduledoc """
  Validates that :compliance proposals have an adr_link before transitioning to PENDING_REVIEW.
  Non-compliance proposals pass unconditionally.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    change_class =
      Ash.Changeset.get_attribute(changeset, :change_class) || changeset.data.change_class

    adr_link =
      Ash.Changeset.get_attribute(changeset, :adr_link) || changeset.data.adr_link

    if change_class == :compliance and (is_nil(adr_link) or adr_link == "") do
      {:error, %{field: :adr_link, message: "compliance proposals require an ADR link"}}
    else
      :ok
    end
  end
end

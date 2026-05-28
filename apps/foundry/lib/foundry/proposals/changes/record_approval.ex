defmodule Foundry.Proposals.Changes.RecordApproval do
  @moduledoc """
  Records the actor's approval in the first available slot.
  Slot 1 is filled first; slot 2 is only available for :sensitive proposals.
  The requester cannot approve their own proposal (enforced here and in AuthorizedApprover).
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: actor}) when not is_nil(actor) do
    proposal = changeset.data
    requester = proposal.requester

    if actor == requester do
      Ash.Changeset.add_error(changeset,
        field: :approve,
        message: "cannot approve your own proposal"
      )
    else
      slot = build_slot(actor, proposal)
      assign_slot(changeset, proposal, slot)
    end
  end

  def change(changeset, _opts, _context) do
    Ash.Changeset.add_error(changeset, field: :approve, message: "actor is required")
  end

  defp build_slot(actor, proposal) do
    role = derive_role(actor, proposal)

    %{
      approver: actor,
      approver_role: role,
      approved_at: DateTime.utc_now()
    }
  end

  defp derive_role(_actor, %{change_class: :sensitive}), do: :sensitive_lead
  defp derive_role(_actor, %{change_class: :compliance}), do: :compliance_officer
  defp derive_role(_actor, %{change_class: :behavioral}), do: :domain_lead
  defp derive_role(_actor, _proposal), do: :developer

  defp assign_slot(changeset, proposal, slot) do
    cond do
      is_nil(proposal.approval_slot_1) ->
        Ash.Changeset.force_change_attribute(changeset, :approval_slot_1, slot)

      proposal.change_class == :sensitive and is_nil(proposal.approval_slot_2) ->
        Ash.Changeset.force_change_attribute(changeset, :approval_slot_2, slot)

      true ->
        Ash.Changeset.add_error(changeset,
          field: :approve,
          message: "all required approval slots are already filled"
        )
    end
  end
end

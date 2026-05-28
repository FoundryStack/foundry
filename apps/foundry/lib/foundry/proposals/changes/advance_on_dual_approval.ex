defmodule Foundry.Proposals.Changes.AdvanceOnDualApproval do
  @moduledoc """
  Advances the proposal state to :approved when all required slots are filled.
  :sensitive proposals require two distinct approvers (slot_1 and slot_2).
  All other classes require only slot_1.
  Runs after RecordApproval has filled the relevant slot.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    change_class = Ash.Changeset.get_attribute(changeset, :change_class) || changeset.data.change_class
    slot_1 = Ash.Changeset.get_attribute(changeset, :approval_slot_1) || changeset.data.approval_slot_1
    slot_2 = Ash.Changeset.get_attribute(changeset, :approval_slot_2) || changeset.data.approval_slot_2

    if approved?(change_class, slot_1, slot_2) do
      AshStateMachine.transition_state(changeset, :approved)
    else
      changeset
    end
  end

  defp approved?(:sensitive, slot_1, slot_2), do: not is_nil(slot_1) and not is_nil(slot_2)
  defp approved?(_class, slot_1, _slot_2), do: not is_nil(slot_1)
end

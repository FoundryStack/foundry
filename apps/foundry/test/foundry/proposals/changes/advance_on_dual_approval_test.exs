defmodule Foundry.Proposals.Changes.AdvanceOnDualApprovalTest do
  use ExUnit.Case, async: true

  import Foundry.ProposalFactory

  alias Foundry.Proposals.Changes.AdvanceOnDualApproval

  # Proposals must be in :pending_review for the :approve action transition to be valid.
  defp pending_proposal(attrs \\ []) do
    build_proposal(Keyword.merge([state: :pending_review], attrs))
  end

  defp run_change(proposal, extra_attrs \\ []) do
    cs =
      proposal
      |> Ash.Changeset.for_update(:approve, %{}, domain: Foundry.Proposals, authorize?: false)

    cs =
      Enum.reduce(extra_attrs, cs, fn {k, v}, acc ->
        Ash.Changeset.force_change_attribute(acc, k, v)
      end)

    AdvanceOnDualApproval.change(cs, [], %{})
  end

  defp slot(approver \\ "a@x.com"), do: approval_slot(approver)

  describe ":sensitive proposals" do
    test "does not advance with only slot_1 set on changeset" do
      proposal = pending_proposal(change_class: :sensitive)
      cs = run_change(proposal, approval_slot_1: slot())
      refute Ash.Changeset.get_attribute(cs, :state) == :approved
    end

    test "advances to :approved when both slots are set on the changeset" do
      proposal = pending_proposal(change_class: :sensitive)
      cs = run_change(proposal, approval_slot_1: slot("a@x.com"), approval_slot_2: slot("b@x.com"))
      assert Ash.Changeset.get_attribute(cs, :state) == :approved
    end

    test "advances when slot_1 already on data and slot_2 set on changeset" do
      proposal = pending_proposal(change_class: :sensitive, approval_slot_1: slot("a@x.com"))
      cs = run_change(proposal, approval_slot_2: slot("b@x.com"))
      assert Ash.Changeset.get_attribute(cs, :state) == :approved
    end

    test "does not advance when neither slot is set" do
      proposal = pending_proposal(change_class: :sensitive)
      cs = run_change(proposal)
      refute Ash.Changeset.get_attribute(cs, :state) == :approved
    end
  end

  describe "non-sensitive proposals" do
    for change_class <- [:structural, :behavioral, :compliance] do
      test "#{change_class} advances to :approved when slot_1 is set on the changeset" do
        proposal = pending_proposal(change_class: unquote(change_class))
        cs = run_change(proposal, approval_slot_1: slot())
        assert Ash.Changeset.get_attribute(cs, :state) == :approved
      end

      test "#{change_class} does not advance when slot_1 is nil" do
        proposal = pending_proposal(change_class: unquote(change_class))
        cs = run_change(proposal)
        refute Ash.Changeset.get_attribute(cs, :state) == :approved
      end

      test "#{change_class} advances when slot_1 already on data" do
        proposal = pending_proposal(change_class: unquote(change_class), approval_slot_1: slot())
        cs = run_change(proposal)
        assert Ash.Changeset.get_attribute(cs, :state) == :approved
      end
    end
  end
end

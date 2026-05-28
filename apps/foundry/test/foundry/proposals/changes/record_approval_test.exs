defmodule Foundry.Proposals.Changes.RecordApprovalTest do
  use ExUnit.Case, async: true

  import Foundry.ProposalFactory

  alias Foundry.Proposals.Changes.RecordApproval

  defp run(proposal, actor) do
    proposal
    |> Ash.Changeset.for_update(:approve, %{}, domain: Foundry.Proposals, actor: actor)
    |> then(fn cs ->
      context = %{actor: actor, domain: Foundry.Proposals}
      RecordApproval.change(cs, [], context)
    end)
  end

  describe "slot assignment" do
    test "fills slot_1 on first approval" do
      proposal = build_proposal(change_class: :structural, state: :pending_review, requester: "req@x.com")
      cs = run(proposal, "dev@x.com")

      slot = Ash.Changeset.get_attribute(cs, :approval_slot_1)
      assert slot.approver == "dev@x.com"
      assert slot.approver_role == :developer
      assert %DateTime{} = slot.approved_at
    end

    test "fills slot_2 for :sensitive when slot_1 already filled" do
      slot1 = approval_slot("first@x.com", :sensitive_lead)

      proposal =
        build_proposal(
          change_class: :sensitive,
          state: :pending_review,
          requester: "req@x.com",
          approval_slot_1: slot1
        )

      cs = run(proposal, "second@x.com")

      slot = Ash.Changeset.get_attribute(cs, :approval_slot_2)
      assert slot.approver == "second@x.com"
    end

    test "returns error when all slots are already filled for :sensitive" do
      proposal =
        build_proposal(
          change_class: :sensitive,
          state: :pending_review,
          requester: "req@x.com",
          approval_slot_1: approval_slot("a@x.com", :sensitive_lead),
          approval_slot_2: approval_slot("b@x.com", :sensitive_lead)
        )

      cs = run(proposal, "c@x.com")
      assert cs.errors != []
      assert Enum.any?(cs.errors, &(&1.message =~ "already filled"))
    end

    test "returns error when slot_1 is filled for non-sensitive (no slot_2 available)" do
      proposal =
        build_proposal(
          change_class: :structural,
          state: :pending_review,
          requester: "req@x.com",
          approval_slot_1: approval_slot("a@x.com", :developer)
        )

      cs = run(proposal, "b@x.com")
      assert cs.errors != []
    end
  end

  describe "self-approval prevention" do
    test "requester cannot approve their own proposal" do
      proposal = build_proposal(change_class: :structural, state: :pending_review, requester: "req@x.com")
      cs = run(proposal, "req@x.com")

      assert cs.errors != []
      assert Enum.any?(cs.errors, &(&1.message =~ "own proposal"))
    end
  end

  describe "nil actor" do
    test "returns error when actor is nil" do
      proposal = build_proposal(change_class: :structural, state: :pending_review, requester: "req@x.com")

      cs =
        proposal
        |> Ash.Changeset.for_update(:approve, %{}, domain: Foundry.Proposals)
        |> then(fn cs -> RecordApproval.change(cs, [], %{}) end)

      assert cs.errors != []
      assert Enum.any?(cs.errors, &(&1.message =~ "actor is required"))
    end
  end

  describe "role derivation" do
    for {change_class, expected_role} <- [
          sensitive: :sensitive_lead,
          compliance: :compliance_officer,
          behavioral: :domain_lead,
          structural: :developer
        ] do
      test "#{change_class} proposals get role #{expected_role}" do
        proposal = build_proposal(change_class: unquote(change_class), state: :pending_review, requester: "req@x.com")
        cs = run(proposal, "approver@x.com")

        slot = Ash.Changeset.get_attribute(cs, :approval_slot_1)
        assert slot.approver_role == unquote(expected_role)
      end
    end
  end
end

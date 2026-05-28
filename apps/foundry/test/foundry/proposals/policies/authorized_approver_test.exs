defmodule Foundry.Proposals.Policies.AuthorizedApproverTest do
  use ExUnit.Case, async: false

  alias Foundry.Proposals.Policies.AuthorizedApprover

  import Foundry.ProposalFactory

  setup do
    _dir =
      with_manifest(&on_exit/1,
        approvers: [
          sensitive_lead: "sensitive@example.com",
          domain_lead: "domain@example.com",
          compliance_officer: "compliance@example.com",
          developer: "dev@example.com"
        ]
      )

    :ok
  end

  defp record(change_class, requester \\ "requester@example.com") do
    %{
      __struct__: FakeProposal,
      change_class: change_class,
      requester: requester
    }
  end

  describe "self-approval prevention" do
    test "requester cannot approve their own proposal" do
      refute AuthorizedApprover.match?(record(:structural, "dev@example.com"), %{actor: "dev@example.com"}, [])
    end
  end

  describe "role matching" do
    test "sensitive_lead can approve :sensitive proposals" do
      assert AuthorizedApprover.match?(record(:sensitive), %{actor: "sensitive@example.com"}, [])
    end

    test "domain_lead can approve :behavioral proposals" do
      assert AuthorizedApprover.match?(record(:behavioral), %{actor: "domain@example.com"}, [])
    end

    test "compliance_officer can approve :compliance proposals" do
      assert AuthorizedApprover.match?(record(:compliance), %{actor: "compliance@example.com"}, [])
    end

    test "developer can approve :structural proposals" do
      assert AuthorizedApprover.match?(record(:structural), %{actor: "dev@example.com"}, [])
    end
  end

  describe "wrong role" do
    test "domain_lead cannot approve :sensitive proposals" do
      refute AuthorizedApprover.match?(record(:sensitive), %{actor: "domain@example.com"}, [])
    end

    test "developer cannot approve :compliance proposals" do
      refute AuthorizedApprover.match?(record(:compliance), %{actor: "dev@example.com"}, [])
    end

    test "unknown actor cannot approve anything" do
      refute AuthorizedApprover.match?(record(:structural), %{actor: "nobody@example.com"}, [])
    end
  end

  describe "edge cases" do
    test "nil actor returns false" do
      assert AuthorizedApprover.match?(:not_a_struct, %{actor: nil}, []) == false
    end

    test "non-struct subject returns false" do
      assert AuthorizedApprover.match?(SomeModule, %{actor: "dev@example.com"}, []) == false
    end
  end

  describe "delegate support" do
    setup do
      with_manifest(&on_exit/1,
        approvers: [
          sensitive_lead: "sensitive@example.com",
          sensitive_lead_delegate: "delegate@example.com"
        ]
      )

      :ok
    end

    test "delegate of sensitive_lead can approve :sensitive proposals" do
      assert AuthorizedApprover.match?(record(:sensitive), %{actor: "delegate@example.com"}, [])
    end
  end
end

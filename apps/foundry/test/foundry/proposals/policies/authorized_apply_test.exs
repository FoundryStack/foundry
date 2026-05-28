defmodule Foundry.Proposals.Policies.AuthorizedApplyTest do
  use ExUnit.Case, async: false

  alias Foundry.Proposals.Policies.AuthorizedApply

  import Foundry.ProposalFactory

  defp record(change_class, requester \\ "requester@example.com") do
    %{__struct__: FakeProposal, change_class: change_class, requester: requester}
  end

  describe "structural proposals with auto_apply: true" do
    setup do
      with_manifest(&on_exit/1,
        auto_apply: true,
        approvers: [developer: "dev@example.com"]
      )

      :ok
    end

    test "passes even with an actor who is not in approvers" do
      assert AuthorizedApply.match?(record(:structural), %{actor: "anyone@example.com"}, [])
    end
  end

  describe "structural proposals with auto_apply: false" do
    setup do
      with_manifest(&on_exit/1,
        auto_apply: false,
        approvers: [developer: "dev@example.com"]
      )

      :ok
    end

    test "passes for an authorized developer" do
      assert AuthorizedApply.match?(record(:structural), %{actor: "dev@example.com"}, [])
    end

    test "blocked for an unauthorized actor" do
      refute AuthorizedApply.match?(record(:structural), %{actor: "nobody@example.com"}, [])
    end
  end

  describe "non-structural proposals ignore auto_apply" do
    setup do
      with_manifest(&on_exit/1,
        auto_apply: true,
        approvers: [
          sensitive_lead: "sensitive@example.com",
          compliance_officer: "compliance@example.com",
          domain_lead: "domain@example.com"
        ]
      )

      :ok
    end

    test ":sensitive does not auto-apply, requires authorized approver" do
      assert AuthorizedApply.match?(record(:sensitive), %{actor: "sensitive@example.com"}, [])
    end

    test ":sensitive blocked for wrong role" do
      refute AuthorizedApply.match?(record(:sensitive), %{actor: "domain@example.com"}, [])
    end
  end

  test "non-struct subject returns false" do
    assert AuthorizedApply.match?(SomeModule, %{actor: "actor@example.com"}, []) == false
  end
end

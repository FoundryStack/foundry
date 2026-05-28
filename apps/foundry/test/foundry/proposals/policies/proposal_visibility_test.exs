defmodule Foundry.Proposals.Policies.ProposalVisibilityTest do
  use ExUnit.Case, async: true

  alias Foundry.Proposals.Policies.ProposalVisibility

  defp record(state, requester), do: %{__struct__: FakeProposal, state: state, requester: requester}

  describe "DRAFT proposals" do
    test "visible to the requester" do
      assert ProposalVisibility.match?(record(:draft, "alice@x.com"), %{actor: "alice@x.com"}, [])
    end

    test "hidden from anyone else" do
      refute ProposalVisibility.match?(record(:draft, "alice@x.com"), %{actor: "bob@x.com"}, [])
    end

    test "hidden when actor is nil" do
      refute ProposalVisibility.match?(record(:draft, "alice@x.com"), %{actor: nil}, [])
    end
  end

  describe "non-DRAFT proposals" do
    for state <- [:pending_review, :approved, :applied, :committed, :rejected, :stale] do
      test "#{state} visible to anyone" do
        assert ProposalVisibility.match?(record(unquote(state), "alice@x.com"), %{actor: "bob@x.com"}, [])
      end

      test "#{state} visible to the requester" do
        assert ProposalVisibility.match?(record(unquote(state), "alice@x.com"), %{actor: "alice@x.com"}, [])
      end
    end
  end

  test "non-struct subject (read action subject is the module) passes unconditionally" do
    assert ProposalVisibility.match?(Foundry.Proposals.Proposal, %{actor: "anyone@x.com"}, [])
  end
end

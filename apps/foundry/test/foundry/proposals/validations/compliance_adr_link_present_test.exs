defmodule Foundry.Proposals.Validations.ComplianceAdrLinkPresentTest do
  use ExUnit.Case, async: true

  alias Foundry.Proposals.Validations.ComplianceAdrLinkPresent

  # Build a minimal changeset-like struct for the validation.
  # ComplianceAdrLinkPresent reads change_class and adr_link from
  # Ash.Changeset.get_attribute (falling back to changeset.data fields).
  # Since we're unit-testing the pure validation logic, we build a real
  # Ash.Changeset for Proposal and inject the relevant attributes.

  defp changeset_for(attrs) do
    defaults = [
      change_class: :structural,
      operation: "Op.Test",
      diff: "--- a/f\n+++ b/f\n@@ -1 +1 @@\n-x\n+y",
      requester: "r@x.com"
    ]

    merged = Keyword.merge(defaults, attrs)

    Foundry.Proposals.Proposal
    |> Ash.Changeset.for_create(:create_draft, Map.new(merged), domain: Foundry.Proposals)
  end

  describe "compliance proposals" do
    test "nil adr_link returns error" do
      cs = changeset_for(change_class: :compliance, adr_link: nil)
      assert {:error, %{field: :adr_link}} = ComplianceAdrLinkPresent.validate(cs, [], %{})
    end

    test "empty string adr_link returns error" do
      cs = changeset_for(change_class: :compliance, adr_link: "")
      assert {:error, %{field: :adr_link, message: msg}} = ComplianceAdrLinkPresent.validate(cs, [], %{})
      assert msg =~ "ADR link"
    end

    test "present adr_link returns :ok" do
      cs = changeset_for(change_class: :compliance, adr_link: "ADR-042")
      assert :ok = ComplianceAdrLinkPresent.validate(cs, [], %{})
    end
  end

  describe "non-compliance proposals" do
    for class <- [:structural, :behavioral, :sensitive] do
      test "#{class} with nil adr_link returns :ok" do
        cs = changeset_for(change_class: unquote(class), adr_link: nil)
        assert :ok = ComplianceAdrLinkPresent.validate(cs, [], %{})
      end
    end
  end
end

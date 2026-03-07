# Embedded resources for Foundry.Manifest — compiled first (manifest/ before manifest.ex)

defmodule Foundry.Manifest.ApproverConfig do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:sensitive_lead, :string, allow_nil?: false)
    attribute(:sensitive_lead_delegate, :string, allow_nil?: true)
    attribute(:domain_lead, :string, allow_nil?: true)
    attribute(:platform_lead, :string, allow_nil?: true)
    attribute(:compliance_officer, :string, allow_nil?: false)
    attribute(:compliance_officer_delegate, :string, allow_nil?: true)
  end
end

defmodule Foundry.Manifest.ApprovalSla do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:structural, :integer, allow_nil?: true, default: nil)
    attribute(:behavioral, :integer, allow_nil?: true, default: 24)
    attribute(:sensitive, :integer, allow_nil?: true, default: 4)
    attribute(:compliance, :integer, allow_nil?: true, default: 48)
  end
end

defmodule Foundry.Manifest.NotificationTarget do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:channel, :atom, constraints: [one_of: [:slack, :email]], allow_nil?: false)
    attribute(:target, :string, allow_nil?: false)
  end
end

defmodule Foundry.Manifest.NotificationConfig do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:runbook_stale, Foundry.Manifest.NotificationTarget, allow_nil?: false)
    attribute(:adapter_verify_failed, Foundry.Manifest.NotificationTarget, allow_nil?: false)
    attribute(:compliance_test_failed, Foundry.Manifest.NotificationTarget, allow_nil?: false)
  end
end

defmodule Foundry.Manifest.CoverageWeights do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:transfer_coverage, :decimal,
      default: Decimal.new("0.25"),
      constraints: [min: 0, max: 1]
    )

    attribute(:rule_coverage, :decimal,
      default: Decimal.new("0.20"),
      constraints: [min: 0, max: 1]
    )

    attribute(:blueprint_coverage, :decimal,
      default: Decimal.new("0.20"),
      constraints: [min: 0, max: 1]
    )

    attribute(:compliance_coverage, :decimal,
      default: Decimal.new("0.25"),
      constraints: [min: 0, max: 1]
    )

    attribute(:ui_coverage, :decimal, default: Decimal.new("0.10"), constraints: [min: 0, max: 1])
  end
end

defmodule Foundry.Manifest.DataRetention do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:proposals, :integer, default: 365, constraints: [min: 1])
    attribute(:audit_log, :integer, default: 2555, constraints: [min: 365])
    attribute(:activity_feed, :integer, default: 90, constraints: [min: 1])
  end
end

defmodule Foundry.Manifest.SensitiveExemption do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:resource_module, :string, allow_nil?: false)

    attribute(:exemption_type, :atom,
      constraints: [one_of: [:paper_trail, :archival]],
      allow_nil?: false
    )

    attribute(:reason, :string, allow_nil?: false)
    attribute(:adr_link, :string, allow_nil?: true)
    attribute(:review_due, :date, allow_nil?: true)
  end
end

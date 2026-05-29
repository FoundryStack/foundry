# .foundry/manifest.exs — IgamingRef reference project
#
# This is the canonical manifest for the iGaming reference fixture project.
# It is the source of truth for all Phase 1 acceptance criteria checks.
# See: docs/reference-project-fixture.md
[
  project_name: "IgamingRef",
  domain_type: :igaming,
  sensitive_resources: [
    IgamingRef.Finance.Wallet,
    IgamingRef.Finance.LedgerEntry,
    IgamingRef.Finance.WithdrawalRequest,
    IgamingRef.Promotions.BonusEvent,
    IgamingRef.Players.Player,
    IgamingRef.Players.SelfExclusionRecord
    # IgamingRef.Accounts.User and IgamingRef.Accounts.Token are added
    # automatically by the sensitive resource classifier — do not list them here.
  ],
  approvers: [
    sensitive_lead: "finance-lead@igamingref.test",
    sensitive_lead_delegate: "cto@igamingref.test",
    domain_lead: "platform-lead@igamingref.test",
    platform_lead: "platform-lead@igamingref.test",
    compliance_officer: "compliance@igamingref.test"
    # compliance_officer_delegate intentionally absent — test single-approver path
  ],
  approval_sla: [
    structural: nil,
    behavioral: [hours: 24],
    sensitive: [hours: 4],
    compliance: [hours: 48]
  ],
  auto_apply_structural: false,
  change_generation_enabled: true,
  notifications: [
    runbook_stale: [channel: :slack, target: "#ops-alerts"],
    adapter_verify_failed: [channel: :email, target: "platform-lead@igamingref.test"],
    compliance_test_failed: [channel: :slack, target: "#compliance-alerts"]
    # Channels are non-functional in test environment by design.
    # :missing_notification_config lint warning will NOT fire (config is present).
  ],
  # false for new projects; set true before go-live
  coverage_gate: false,
  coverage_weights: [
    transfer_coverage: 0.25,
    rule_coverage: 0.20,
    blueprint_coverage: 0.20,
    compliance_coverage: 0.25,
    ui_coverage: 0.10
  ],
  conditional_libraries: [
    :ash_money,
    :ash_state_machine,
    :fun_with_flags
  ],
  preview_server: [
    command: "mix phx.server",
    port: 4001,
    env: [
      {~c"MIX_BUILD_PATH", ~c"_build/preview"}
    ]
  ]
]

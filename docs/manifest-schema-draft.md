# docs/manifest-schema-draft.md — Foundry Project Manifest Schema

> **Status:** Pre-ADR draft — consolidated from implicit references across ADR-001 through ADR-015.
> This document exists to give `Foundry.Manifest` Ash resource design a complete target.
> It will be superseded by ADR-011 once the Ash resource is defined.
> Do not treat this as a frozen contract. Treat it as the authoritative candidate schema.
>
> **Rule:** If you find a manifest field referenced in any ADR or invariant that is not listed
> here, add it here and note which document references it. Do not let implicit manifest fields
> accumulate in ADRs without being reflected in this document.

---

## File Location

```
.foundry/manifest.exs   ← committed to the target project repository
```

Foundry's own manifest lives at the same path within Foundry's own repository.
The schema is identical regardless of whether the project is Foundry itself or a target platform.

---

## Full Schema (Elixir keyword list format)

```elixir
# .foundry/manifest.exs
[
  # ── Identity ──────────────────────────────────────────────────────────────

  # Human-readable project name. Used in Studio UI headers, notification subjects,
  # and audit log records.
  project_name: "MyApp",

  # The target domain type. Informational only — does not change enforcement behaviour.
  # Used in bootstrap mode to select template defaults.
  # Values: :igaming | :fintech | :healthcare | :legal | :insurance | :other
  domain_type: :igaming,

  # ── Sensitive Resources ────────────────────────────────────────────────────
  # Source: ADR-005, INV-001, INV-011, INV-012

  # Modules that require dual approval, AshPaperTrail, AshArchival, and
  # full audit logging. Authentication User and Token resources are always
  # added to this set automatically — do not list them here.
  sensitive_resources: [
    MyApp.Finance.LedgerEntry,
    MyApp.Finance.Wallet,
    # Healthcare example: MyApp.Records.PatientRecord
    # Legal example: MyApp.Documents.PrivilegedDocument
  ],

  # Per-sensitive-resource exemptions. Each entry requires a documented reason
  # and is a :compliance class change to add or remove.
  # Source: INV-011 (paper_trail exemption), INV-012 (archival exemption)
  sensitive_resource_exemptions: [
    # {MyApp.Finance.LedgerEntry, paper_trail: :exempt, reason: "..."},
    # {MyApp.Finance.ArchivedWallet, archival: :exempt, reason: "..."}
  ],

  # ── Approvers ─────────────────────────────────────────────────────────────
  # Source: ADR-005, ADR-014, approval_queue_blocked runbook

  approvers: [
    # Required for :sensitive dual approval slot 1.
    sensitive_lead: "finance-lead@company.com",

    # Optional fallback when sensitive_lead is unavailable.
    sensitive_lead_delegate: "cto@company.com",

    # Qualifies as :sensitive dual approval slot 2,
    # and as the sole approver for :behavioral changes.
    domain_lead: "platform-lead@company.com",

    # Qualifies as :sensitive dual approval slot 2.
    platform_lead: "platform-lead@company.com",

    # Required sole approver for :compliance changes. No override path.
    compliance_officer: "compliance@company.com",

    # Optional fallback for compliance_officer.
    compliance_officer_delegate: "legal@company.com"
  ],

  # ── Approval SLAs ─────────────────────────────────────────────────────────
  # Source: approval_queue_blocked runbook

  # nil means no SLA. The operations board shows proposals exceeding their SLA in amber/red.
  approval_sla: [
    structural:  nil,
    behavioral:  [hours: 24],
    sensitive:   [hours: 4],
    compliance:  [hours: 48]
  ],

  # ── Auto-Apply Configuration ───────────────────────────────────────────────
  # Source: ADR-005, ADR-014, BUILD_SEQUENCE Phase 5

  # When true, approved :structural proposals are applied immediately on approval.
  # The approval action IS the apply trigger for :structural auto-apply.
  # All other classes always require a separate deliberate Apply action.
  auto_apply_structural: false,

  # ── Change Generation Phase Gate ──────────────────────────────────────────
  # Source: ADR-010, ADR-013, BUILD_SEQUENCE Phase 3/4

  # Controls whether the copilot generates real diffs (Phase 4+) or only
  # describes what would be proposed (Phase 3).
  # This is also set in config/foundry_studio.exs but the manifest value
  # takes precedence for per-project overrides.
  # Note: config :foundry_studio, change_generation_enabled: true/false is the
  # primary mechanism; this manifest field enables per-project override.
  change_generation_enabled: true,

  # ── Copilot Agentic Loop ──────────────────────────────────────────────────
  # Source: ADR-010 §Agentic Loop Specification

  copilot: [
    # Maximum bash tool calls per copilot request before :context_budget_exceeded.
    # Circuit breaker — not a quality knob. Normal operations never hit this.
    # Increase if complex multi-module operations routinely hit the limit.
    # Decrease to 4–5 for faster average response at the cost of depth.
    max_tool_calls: 8
  ],

  # ── Notifications ─────────────────────────────────────────────────────────
  # Source: INV-010, ADR-001 (swoosh, Slack webhook)

  # All three keys are required. Omitting any triggers a :missing_notification_config
  # lint warning (not a build failure, but a governance risk flag).
  notifications: [
    runbook_stale:          [channel: :slack,  target: "#ops-alerts"],
    adapter_verify_failed:  [channel: :email,  target: "platform-lead@company.com"],
    compliance_test_failed: [channel: :slack,  target: "#compliance-alerts"]
  ],

  # ── Test Coverage ─────────────────────────────────────────────────────────
  # Source: ADR-007

  # When true, a domain coverage score below 0.6 fails CI.
  # Recommended: false for new projects, true before go-live.
  coverage_gate: false,

  # Override the default domain coverage formula weights.
  # All five weights must sum to 1.0.
  coverage_weights: [
    transfer_coverage:    0.25,
    rule_coverage:        0.20,
    blueprint_coverage:   0.20,
    compliance_coverage:  0.25,
    ui_coverage:          0.10
  ],

  # ── Data Retention ────────────────────────────────────────────────────────
  # Source: ADR-012 §Data Retention

  # Override the default retention periods (financial/regulated platform defaults).
  # All values are in days.
  data_retention: [
    proposals:           365,    # completed proposals in .foundry/proposals/
    audit_log:           2555,   # .foundry/audit.jsonl (7 years — financial default)
    activity_feed:       90      # in-Studio activity feed entries
  ],

  # ── Context Exclusions ────────────────────────────────────────────────────
  # Source: studio_ux_degradation runbook (workaround for cyclic DSL modules)

  # Modules excluded from mix foundry.context introspection.
  # Use only as a temporary workaround for cyclic dependency or DSL loop issues.
  # Each exclusion should have a filed issue reference.
  context_exclusions: [
    # MyApp.Finance.ProblemModule   # Issue #42 — cyclic dependency in DSL
  ],

  # ── Conditionally Present Libraries ───────────────────────────────────────
  # Source: ADR-001 §Conditionally Present

  # Declares which optional ecosystem libraries are present in this target platform.
  # Foundry uses this list to enable/disable lint rules and scaffold operations
  # that are only valid when the library is present.
  conditional_libraries: [
    :ash_money,          # enables Ash.Type.Money generation, validates CLDR backend
    :ash_state_machine,  # enables state transition generation and lint rules
    # :ash_pyro,         # enables AshPyro component lint rules
    # :fun_with_flags,   # enables feature flag generation and INV-013 lint rule
  ]
]
```

---

## Field Reference Table

| Field | Type | Required | Default | Source |
|---|---|---|---|---|
| `project_name` | string | yes | — | convention |
| `domain_type` | atom | no | `:other` | bootstrap templates |
| `sensitive_resources` | list of modules | no | `[]` | ADR-005, INV-001 |
| `sensitive_resource_exemptions` | keyword list | no | `[]` | INV-011, INV-012 |
| `approvers` | keyword list | yes | — | ADR-005, ADR-014 |
| `approvers.sensitive_lead` | email string | yes | — | ADR-005 |
| `approvers.sensitive_lead_delegate` | email string | no | none | approval runbook |
| `approvers.domain_lead` | email string | no | none | ADR-005 |
| `approvers.platform_lead` | email string | no | none | ADR-014 |
| `approvers.compliance_officer` | email string | yes | — | ADR-005 |
| `approvers.compliance_officer_delegate` | email string | no | none | approval runbook |
| `approval_sla` | keyword list | no | see defaults | approval runbook |
| `auto_apply_structural` | boolean | no | `false` | ADR-005, ADR-014 |
| `change_generation_enabled` | boolean | no | `true` | ADR-010, ADR-013 |
| `notifications` | keyword list | yes* | — | INV-010 |
| `notifications.runbook_stale` | channel config | yes* | — | INV-010 |
| `notifications.adapter_verify_failed` | channel config | yes* | — | INV-010 |
| `notifications.compliance_test_failed` | channel config | yes* | — | INV-010 |
| `coverage_gate` | boolean | no | `false` | ADR-007 |
| `coverage_weights` | keyword list | no | see ADR-007 defaults | ADR-007 |
| `data_retention` | keyword list | no | see ADR-012 defaults | ADR-012 |
| `context_exclusions` | list of modules | no | `[]` | degradation runbook |
| `conditional_libraries` | list of atoms | no | `[]` | ADR-001 |

*Required in the sense that omission triggers a lint warning (not a build failure). See INV-010.

---

## Validation Rules

The following are enforced by `mix foundry.lint.all` against the manifest:

1. `approvers.sensitive_lead` and `approvers.compliance_officer` must be present — lint error if absent.
2. `notifications` with all three keys must be present — lint warning if absent (INV-010).
3. `sensitive_resource_exemptions` entries must reference modules in `sensitive_resources` — lint error for unknown modules.
4. `coverage_weights` values must sum to 1.0 ± 0.001 — lint error.
5. `context_exclusions` entries should have a comment with an issue reference — lint warning if absent.
6. If `conditional_libraries` includes `:ash_money`, a CLDR backend module must be discoverable — lint error.

---

## What This Document Is Not

This is not a frozen API contract. It is a pre-ADR design target. When `Foundry.Manifest`
is implemented as an Ash resource, ADR-011 will be written from this document, and ADR-011
will become the contract. This document will then be archived.

Do not add fields to this document speculatively. Only add fields that are already
referenced (explicitly or implicitly) in an existing ADR, invariant, or runbook.
If a new field is needed, the originating decision must be documented in the relevant ADR first.
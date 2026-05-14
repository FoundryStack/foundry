# Platform Invariants

> **Scope:** These are target-platform domain requirements — constraints on what Foundry
> enforces about the code it governs (sensitive resources, idempotency, runbook links,
> description coverage, compliance implementation, etc.).
>
> **Numbering note:** INV-001..013 here use the same numbers as AGENTS.md §Hard Invariants
> but cover different requirements from INV-003 onward. AGENTS.md INVs govern agent
> behaviour and Foundry's build rules. These INVs govern target-platform code requirements.
> When an ADR cites "INV-NNN", check which document it references.
>
> Enforcement: compiler, linter (`mix foundry.lint.all`), and approval workflow.
> Violations are build failures unless marked `:warning`.

---

## INV-001: No Autonomous Changes to Sensitive Domain Resources

**Requirement:** Any change affecting resources designated `:sensitive` in the project manifest requires dual human approval before application.

**Scope:** Determined per project via `manifest.sensitive_resources`. Examples: LedgerEntry, Wallet (iGaming/fintech); PatientRecord (healthcare); PrivilegedDocument (legal). Foundry does not hardcode what counts as sensitive — the project declares it.

**Enforcement:** Change classifier tags these as `:sensitive`. Approval workflow blocks application until two distinct approvers have confirmed. Audit log records both approvals with timestamps and approver identity.

**Rationale:** Certain domain resources carry legal, regulatory, or financial integrity requirements. No level of AI confidence justifies bypassing human review on these. The decision of which resources are sensitive belongs to the project, not to the platform.

---

## INV-002: No Direct Filesystem Writes from Agent

**Requirement:** All code changes are routed through Igniter operations executed by the Foundry backend via `Foundry.Operations.run/2`. Agents never write to the filesystem directly.

**Scope:** All source files in `lib/`, `test/`, `config/`. For `docs/` (ADRs, runbooks, regulations), agents may propose plain-text content which humans review and commit. The compiler validates code; humans validate prose.

**Enforcement:** `Foundry.Operations.run/2` is the only code-change entry point. `File.write!/2` on source files is a forbidden pattern detected by the linter. The mechanism (local Igniter call vs WebSocket to cloud backend) is an implementation detail — the invariant holds in both modes.

**Note on raw Igniter:** Agents may use raw Igniter API (not catalogue operations) for novel patterns. "Raw" means using Igniter's own functions directly rather than a pre-built `Op.*` module. It does not mean bypassing Igniter. String interpolation to produce Elixir source is always forbidden.

---

## INV-003: Infrastructure Is Proposal-Only

**Requirement:** Kubernetes configs, Postgres configs, CI pipeline modifications — agents produce proposals, humans apply.

**Scope:** All files outside the application codebase: `k8s/`, `deploy/`, `.github/workflows/`, database configuration files.

**Enforcement:** The `Op.InfrastructureProposal` operation renders a diff for human review and routes to the infrastructure approver. There is no `Op.ApplyInfrastructure` operation.

---

## INV-004: Every External Side-Effect Reactor Must Declare Idempotency

**Requirement:** All Reactor modules that perform external side effects (money movement, provider API calls, state transitions with audit implications) must include an idempotency declaration with a key field.

**Scope:** Reactors where replaying a step would cause harm — double charges, duplicate API calls, duplicate audit records. The target platform's core library defines the exact DSL syntax. Purely internal read/compute Reactors are exempt.

**Enforcement:** `mix foundry.lint.all` — `:missing_idempotency` lint rule. The lint rule reads the Reactor's step types to determine if external effects are present. Build fails when required and absent.

---

## INV-005: Every Reactor Must Have a Runbook Link

**Requirement:** All Reactor modules must declare `@runbook` pointing to an existing runbook file.

**Scope:** All modules using `Reactor` with more than 3 steps.

**Enforcement:** `mix foundry.lint.all` — `:missing_runbook` lint rule. Build fails if runbook file doesn't exist at the declared path.

---

## INV-006: Description Coverage Must Be Complete

**Requirement:** All Ash resource attributes must have a `description:` value. All public modules must have `@moduledoc`.

**Scope:** All Ash resources in `lib/`. Test modules are exempt.

**Enforcement:** `mix foundry.lint.all` — `:missing_description` lint rule. Build fails. This is the raw material for the system map detail panel and the copilot's domain knowledge — without it, both degrade.

---

## INV-007: Compliance Requirements Must Have Implementation Pointers

**Requirement:** Every RG-* requirement declared in a regulation file must have at least one `implementation:` pointer to a module or test.

**Scope:** All requirement entries in `docs/regulations/*.md`.

**Enforcement:** `mix foundry.compliance.check` — `:unimplemented_requirement` violation. This is a CI gate for projects that have declared compliance certifications in their manifest.

---

## INV-008: Generated Diagrams Must Be Committed

**Requirement:** The project context must not be stale at CI time — `.foundry/context.lock`
must match the current source file hash.

**Scope:** `.foundry/context.lock` (50-byte SHA256 hash of all `lib/**/*.ex` and `test/**/*.ex` files).

**Enforcement:** CI runs `mix foundry.project.context --check`. Exits 1 if the lock file
is absent or if the hash does not match the current source. To update after source changes,
run `mix foundry.project.context` locally and commit the updated `.foundry/context.lock`.

`mix foundry.diagram.generate` is a deprecated alias retained for backward compatibility.
`mix foundry.project.context --check` is the canonical CI gate. See ADR-020.

---

## INV-009: The Spec-Kit Is the Only Manual Documentation

**Requirement:** The only documentation that requires manual authorship is: ADRs, regulation files, runbooks, and AGENTS.md. Foundry may also generate canonical `docs/findings/*.md` artifacts from copilot sessions when a durable technical finding is discovered. All other documentation is generated from code.

**Scope:** `docs/adrs/`, `docs/findings/`, `docs/regulations/`, `docs/runbooks/`, `AGENTS.md`.

**Rationale:** Documentation that can be generated from code must be generated from code. Manually maintaining what the compiler already knows creates synchronization drift. The spec-kit contains only decisions, constraints, procedures, and durable technical findings — things the compiler cannot know.

---

## INV-010: Staleness Conditions Must Have Notification Channels

**Requirement:** The project manifest must declare notification targets for operational staleness conditions. Staleness is never silently ignored.

**Scope:** Three required notification types:
- `runbook_stale` — a runbook has not been tested within the configured interval (default 90 days)
- `adapter_verify_failed` — a provider adapter's contract test failed its scheduled verification
- `compliance_test_failed` — a compliance-tagged E2E test failed in the latest CI run

**Manifest declaration:**
```elixir
notifications: [
  runbook_stale:          [channel: :slack, target: "#ops-alerts"],
  adapter_verify_failed:  [channel: :email, target: "platform-lead@company.com"],
  compliance_test_failed: [channel: :slack, target: "#compliance-alerts"]
]
```

**Enforcement:** `mix foundry.lint.all` — `:missing_notification_config` lint rule warns (not fails) if notification channels are not declared. The scheduled staleness jobs will log but not deliver notifications until channels are configured. A project going to production without notification config is a governance risk flagged in the compliance dashboard.

**Rationale:** The operations board is a pull medium — someone must be looking at it. Regulated platforms require that compliance failures and operational risks are actively surfaced to responsible parties, not passively visible to those who check.

---

## INV-011: Sensitive Resources Must Have Change History

**Requirement:** All resources designated `:sensitive` in the project manifest must use
`AshPaperTrail` to record a change history. A sensitive resource without paper trail
configuration is a lint error.

**Scope:** All modules in `manifest.sensitive_resources`, plus authentication User and Token
resources (which are always `:sensitive` regardless of manifest declaration).

**Enforcement:** `mix foundry.lint.all` — `:missing_paper_trail` lint rule. Reads each
sensitive resource's extensions list and fails if `AshPaperTrail.Resource` is absent.

**Rationale:** In regulated domains, knowing *that* a sensitive record changed is insufficient —
the audit chain requires knowing *what* changed, *when*, and under *which* approval. Paper trail
is the machine-readable audit log for individual record mutations. Without it, the audit log
(INV-001) records approvals but not the actual data changes.

**Override:** A sensitive resource may declare `paper_trail: :exempt` in the manifest with a
documented reason. This is a `:compliance` class change (ADR-005) and requires compliance
officer approval. Exemptions must be reviewed annually.

---

## INV-012: Sensitive Resources Must Use Soft Delete

**Requirement:** All resources designated `:sensitive` must use `AshArchival` for soft deletion.
Hard deletion of sensitive records (ledger entries, wallet records, PHI, audit records) is
prohibited unless explicitly exempted.

**Scope:** All modules in `manifest.sensitive_resources`, plus authentication User and Token resources.

**Enforcement:** `mix foundry.lint.all` — `:missing_archival` lint rule. Reads each sensitive
resource's extensions list and fails if `AshArchival.Resource` is absent. Also checks that
no `:destroy` action on a sensitive resource bypasses archival (i.e., uses `soft_delete?: false`).

**Rationale:** Hard deletion of regulated data is frequently illegal (financial records, health
records, audit trails). In iGaming, deleting a LedgerEntry is a regulatory violation. Soft
deletion preserves records while marking them inactive, satisfying both product requirements
(the record is "gone" from user perspective) and regulatory requirements (the data is retained).

**Override:** A sensitive resource may declare `archival: :exempt` in the manifest with a
documented reason and the specific regulation that permits hard deletion. This is a `:compliance`
class change and requires compliance officer approval.

---

## INV-013: Compliance-Gated Feature Flags Must Have ADR Links

**Requirement:** Any `fun_with_flags` feature flag that gates a compliance control, a sensitive
operation, or a regulatory feature must declare an ADR link in its Foundry governance metadata.
A compliance-gated flag without an ADR link is a lint error.

**Scope:** Feature flags declared with `governance: :compliance` or `governance: :sensitive`
in their Foundry governance metadata (declared when the flag is created).

**Enforcement:** `mix foundry.lint.all` — `:missing_flag_adr` lint rule. Reads flags from
the project's `fun_with_flags` configuration and checks for governance metadata.

**Rationale:** A feature flag that can silently disable a compliance control (e.g., "temporarily
disable self-exclusion enforcement during the migration") is a compliance risk at the configuration
layer, not the code layer. The approval and audit chain must extend to flag state changes, not
just code changes. The ADR link ensures the rationale for the flag's existence is documented
and its activation/deactivation is governed.

**Classification:** Adding a compliance-gated feature flag is a `:compliance` class change (ADR-005).
Activating or deactivating a compliance-gated flag in production is also a `:compliance` class
change and must go through the approval workflow.

---

## Implementation Tracker

| INV | Lint rule / check | Status |
|---|---|---|
| INV-001 | Change classifier `:sensitive` + dual approval workflow, reads `manifest.sensitive_resources`; auth resources always `:sensitive` | planned |
| INV-002 | Linter: forbidden `File.write!` on source files; `Foundry.Operations.run/2` as sole entry point | planned |
| INV-003 | No `Op.ApplyInfrastructure` in catalogue | by design |
| INV-004 | `:missing_idempotency` lint rule — infers from Reactor step types | planned |
| INV-005 | `:missing_runbook` lint rule — validates file exists at declared path | planned |
| INV-006 | `:missing_description` lint rule | planned |
| INV-007 | `foundry.compliance.check :unimplemented_requirement` | planned |
| INV-008 | CI diagram diff check | planned |
| INV-009 | Enforced by convention + team discipline | by design |
| INV-010 | `:missing_notification_config` lint warning | planned |
| INV-011 | `:missing_paper_trail` lint rule — sensitive resources must use AshPaperTrail | planned |
| INV-012 | `:missing_archival` lint rule — sensitive resources must use AshArchival | planned |
| INV-013 | `:missing_flag_adr` lint rule — compliance-gated flags must have ADR links | planned |

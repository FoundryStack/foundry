# ADR-014: Proposal Lifecycle

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

ADR-005 specifies change classification and approval requirements. ADR-009 specifies stale
proposal detection. Neither specifies the complete proposal state machine, the mechanics of
dual approval (timeouts, revocation, audit), how `:compliance` ADR linking is enforced in
the workflow, how the apply step handles failure, or how proposals become superseded.

Phase 4's done criteria require all of this to be implemented and validated. This ADR is
the contract that implementation follows.

---

## Decision: Proposal State Machine

```
DRAFT ──────────────────────────► PENDING_REVIEW
  │                                      │
  │ (dismissed before submit)            ├──► APPROVED ──► APPLIED ──► COMMITTED
  ▼                                      │
DISMISSED                                ├──► REJECTED
                                         │
                                         ├──► STALE (blob hash mismatch at apply time)
                                         │
                                         └──► SUPERSEDED (another proposal for same module applied first)
```

**DRAFT**
All generated files are on the `foundry/prop_<id>` branch: spec-kit documents first
(ADR stub, runbook stub — if required by change class), then test skeletons, then
implementation, then migration (if schema changes). The diff is captured. The requester
views the complete unified diff in the review panel and either submits or dismisses.
No file type is treated differently from another — ADR markdown and Elixir source are
reviewed and approved together.

A DRAFT is not visible to other users. Only the requester sees it.

**PENDING_REVIEW**
Submitted for approval. Notification sent to designated approver(s). The proposal is
visible to all project users — read-only for non-approvers.

Once in PENDING_REVIEW, only an approver or the requester can dismiss (transitions to REJECTED
with a reason). The requester cannot recall and re-draft without the approver being notified.

**APPROVED**
All required approvals received. For `:structural` with auto-apply configured: transitions
to APPLIED immediately without further user action. For all other classes: waits for a human
to press "Apply" in the review panel.

An APPROVED proposal that is not applied within 24 hours is flagged in the operations board
(amber indicator). It is not auto-applied — the 24h flag is informational only.

**APPLIED**
Igniter has run in non-dry-run mode. Code has been written to disk. Pre-apply blob hash
check has passed. `mix ash.codegen` and `mix ash.migrate` have run (if the proposal
includes a migration). `mix compile` has confirmed no compilation errors.

**COMMITTED**
Git commit created with structured message. CI triggered. Terminal success state.

**REJECTED**
Any approver, or the requester, may reject. Rejection requires a reason (text field, minimum
10 characters — enforced). Reason is stored in the audit log. The requester is notified.
A rejected proposal can be revised by regenerating (which creates a new DRAFT).

**STALE**
Blob hash mismatch at apply time (ADR-009). Transitions from APPROVED back to pending.
Requester notified with the specific file that changed. One-click regenerate in stale banner (ADR-012).

**SUPERSEDED**
A different proposal touching the same files was applied first. Requester notified to regenerate.

---

## Decision: Dual Approval Mechanics

For `:sensitive` proposals, two distinct human approvals are required before APPLIED.

### Approval Slots

- `approval_slot_1` — the `sensitive_lead` named in the manifest
- `approval_slot_2` — any other named approver in the manifest (`domain_lead`, `platform_lead`, or `compliance_officer`)

**Constraint:** The same person cannot fill both slots. If the `sensitive_lead` and `domain_lead`
are the same individual, only the `compliance_officer` qualifies as the second approver.

**Order:** Either approver may act first. The proposal enters APPROVED when both slots
are filled.

**Visibility:** Both approvers see the full diff, lint results, and impact analysis.
Each approver can see whether the other has approved — the review panel footer shows
both slots and their current state (pending / approved / revoked).

### Timeouts

After the SLA window (default: 4 hours for `:sensitive`, configurable in manifest), the
proposal is flagged as SLA-exceeded in the operations board. The INV-010 notification
fires to the configured channel. There is no auto-escalation and no auto-rejection.
The flag is informational — it surfaces the blockage so a human can act (see
`runbooks/approval_queue_blocked.md`).

### Revocation

An approver may revoke their approval at any time before the proposal transitions to
APPLIED. Revocation:
1. Returns the proposal to PENDING_REVIEW
2. Clears the revoked approval slot
3. Notifies both the other approver and the requester
4. Requires a reason (text field, minimum 10 characters)
5. Records the revocation in the audit log: `{proposal_id, approver_email, action: :revoked, reason, timestamp}`

A proposal that has been revoked once and then re-approved by the same approver carries
both events in the audit log. The audit log is append-only.

### Audit Record

Per approval event, the audit log stores:

```json
{
  "proposal_id": "...",
  "event": "approved" | "revoked",
  "approver_email": "...",
  "approver_role": "sensitive_lead" | "domain_lead" | "platform_lead" | "compliance_officer",
  "approval_slot": 1 | 2,
  "timestamp": "2026-03-04T14:22:00Z",
  "diff_hash_at_event": "sha256:...",
  "proposal_change_class": ":sensitive"
}
```

`diff_hash_at_event` records the state of the diff at the time of the approval decision.
If the diff is later found to differ from what was applied (integrity check), the audit
record shows what the approver actually reviewed.

---

## Decision: ADR Linking for Compliance Changes

When the change classifier tags a proposal as `:compliance`, the ADR link field in the
review panel footer is required before "Submit for Approval" activates.

### Validation Rules

- The field accepts an ADR ID: `"ADR-005"`, `"ADR-013"`, etc.
- On input, the system checks whether `docs/adrs/ADR-XXX-*.md` exists at the declared ID.
- **If the file exists:** green checkmark. "Submit for Approval" activates.
- **If the file does not exist:** amber warning: "ADR-XXX not found. The compliance officer must confirm the ADR will be created before approving. You may still submit." "Submit for Approval" activates with the warning persisting.

The compliance officer makes the final judgment on whether a non-existent ADR is acceptable.
The system does not block submission on a non-existent ADR — it surfaces the gap and
delegates the decision to the human approver.

### No Inline ADR Creation

There is no flow to create an ADR from within the review panel. ADRs are authored as
Markdown files in `docs/adrs/`, reviewed as prose, and committed by a human. The copilot
may draft ADR content in the copilot panel when asked ("Draft an ADR for this change"), but
the file is committed manually. The ADR link field in the review panel only references
ADRs that already exist (or will exist at approval time, per the compliance officer's judgment).

---

## Decision: Proposal Visibility

All proposals in PENDING_REVIEW or later states are visible to all authenticated project users.
DRAFT proposals are visible only to the requester.

**What all users can see:**
- Proposal title, change class, requester identity, current state, affected modules
- SLA status
- The diff (read-only)
- Lint and impact analysis results

**What only approvers and the requester can see:**
- Approval deliberation notes and revocation reasons
- The full conversation context that generated the proposal

**Concurrent conflict warning:**
When a user generates a new proposal and there is already a PENDING_REVIEW proposal
touching any of the same files, the Studio shows a non-blocking warning in the copilot panel:
"[User] has a pending proposal that also touches [module]. Your proposal may become stale if
theirs is applied first. This is not an error — proceed if your changes are independent."

This is purely informational. The optimistic locking mechanism (ADR-009) handles the actual
conflict at apply time if it arises.

---

## Decision: The Apply Step

The apply step is a two-phase operation. Both phases must succeed; failure in Phase B is
surfaced to the user and requires manual resolution.

### Phase A — Pre-Apply Checks (must all pass before Phase B begins)

1. Re-read blob hash for every file in the proposal. Compare to stored hashes.
   → Mismatch: transition to STALE. Notify requester. Abort.

2. Verify all required approval slots are filled and no slot has been revoked.
   → Not satisfied: block. Show current approval state in review panel.

3. For `:compliance` proposals: verify the ADR link field is populated.
   → Not populated: block. The field is required.

4. Re-run lint against the stored diff.
   → Lint errors: block. Show updated lint results. The proposal must be regenerated if
   the lint rules changed since generation.

5. Verify the proposal is not in SUPERSEDED state (a concurrent check — the state machine
   should have caught this, but a final check before execution is prudent).

### Phase B — Apply Execution

1. `Foundry.Operations.run(op, params, dry_run: false)` — executes the Igniter pipeline.

2. If the proposal includes a migration:
   a. Run `mix ash.codegen <auto_name>`
   b. Verify the generated migration file matches the migration diff stored in the proposal
      (blob hash check on the migration file — if the DSL changed since generation, the
      migration may differ from what was approved)
   c. If migration hash differs: abort. Surface: "The migration diff changed since this
      proposal was approved. Regenerate the proposal to capture the current migration."
   d. Run `mix ash.migrate`

3. Run `mix compile`. Verify exit code is 0.
   → Non-zero: **compilation failure path** (see below).

4. Create git commit:
   ```
   [FOUNDRY] :behavioral: Add WithdrawalLimitRule

   ADR: docs/adrs/ADR-020-withdrawal-limit-rule.md
   Approved by: domain-lead@company.com (2026-03-04T14:22:00Z)
   Proposal ID: prop_abc123
   Change class: :behavioral
   ```
   The `ADR:` line is omitted for `:structural` changes where no ADR was drafted.

5. Trigger CI.

6. Transition proposal to COMMITTED.

### Compilation Failure Path

If `mix compile` returns non-zero after Igniter apply:

The changes have been written to disk and cannot be automatically rolled back — Igniter
does not provide undo. This is an exceptional state.

The Studio surfaces:
```
⚠ Apply partially failed — compilation error after writing changes.
The following files were written:
  - lib/my_app/finance/withdrawal_limit_rule.ex (new)

Compiler error:
[error output, full, not truncated]

Next steps:
1. Fix the compilation error manually in your editor
2. Run `mix compile` to verify
3. Run `mix foundry.proposals.mark-applied --id prop_abc123` to close this proposal
```

The `mix foundry.proposals.mark-applied` CLI command closes the proposal lifecycle manually.
It requires `mix compile` to pass before it accepts the command — it will not mark a
proposal applied while the project is broken.

**Why this path exists:** Pre-apply lint should catch any errors that would cause a
compilation failure. If a compilation failure occurs, it indicates either a gap in the
lint rules or a race condition where the codebase changed between lint and apply. Both
are bugs to be filed against the lint rule coverage.

---

## Decision: Proposal Lifecycle for Auto-Apply

The `auto_apply_classes` manifest key (default: `[]`) lists which change classes bypass
the manual "Apply" button press. When a proposal's change class is in this list and all
Phase A checks pass, Phase B executes immediately on the final approval action.

**The approval action IS the apply trigger for classes in `auto_apply_classes`.**

`:behavioral`, `:sensitive`, and `:compliance` are hard-blocked from `auto_apply_classes`
regardless of configuration. Only `:structural` is a valid entry. Specifying other classes
is a manifest validation error.

For all other classes, the "Apply" button is a deliberate separate step after approval —
it forces a human to actively initiate the code change, not just approve it.

**Spec-kit → code ordering within a proposal:** When a session plan includes a spec-kit
file (ADR, runbook) before code files, all files are generated in one pass and land in
the same proposal branch. There is no separate "wait for ADR commit" gate — the ADR draft
is part of the diff the approver reviews. The approver's approval confirms both the spec
and the implementation simultaneously.

---

## Decision: Proposal Storage

Each proposal is stored as a single JSON file at `.foundry/proposals/prop_<id>.json`
in the target project's repository. Storage implementation and commit lifecycle are
specified in ADR-015. The schema below is the file's content.

```json
{
  "proposal_id": "prop_abc123",
  "state": "PENDING_REVIEW",
  "change_class": ":behavioral",
  "operation": "Op.AddRule",
  "operation_params": { ... },
  "diff": "...",
  "migration_diff": "..." | null,
  "blob_hashes": {
    "lib/my_app/finance/wallet.ex": "sha256:abc...",
    "test/my_app/finance/wallet_test.exs": "sha256:def..."
  },
  "lint_result": { ... },
  "impact_analysis": { ... },
  "adr_link": "ADR-005" | null,
  "graph_delta": {
    "base_diagram_hash": "sha256:...",
    "nodes_added": [],
    "nodes_modified": [],
    "edges_added": []
  },
  "requester": "dev@company.com",
  "created_at": "2026-03-04T14:00:00Z",
  "submitted_at": "2026-03-04T14:05:00Z",
  "approval_slot_1": { "approver": null, "approved_at": null },
  "approval_slot_2": { "approver": null, "approved_at": null },
  "applied_at": null,
  "committed_at": null,
  "git_commit_sha": null | "abc123..."
}
```

**DRAFT proposals** use the filename `prop_<id>.draft.json` and are not committed to git.
All other states use `prop_<id>.json` and are committed on each state transition (ADR-015).

This schema is owned by `Foundry.Proposals.ProposalStore`. Do not reference fields not
listed here from outside that module — the schema is an internal implementation detail.

---

## Consequences

- The DRAFT → PENDING_REVIEW transition is the point at which other users gain visibility — not proposal generation
- Compilation failure after apply is a recoverable exceptional state, not a rollback path. Lint coverage is the primary defence against it
- For classes in `auto_apply_classes` (default only `:structural`): approval and apply are a single action. For all other classes, they are two separate deliberate steps.
- The `mix foundry.proposals.mark-applied` command is a safety valve — it should rarely be needed and its use should be logged as a platform issue to investigate
- `approval_slot_2` for `:sensitive` proposals can be filled by `domain_lead`, `platform_lead`, or `compliance_officer` — the manifest determines who qualifies. This means a project with no `domain_lead` declared still has a valid second approver path via `platform_lead`.
- Proposal files and the audit log are stored in `.foundry/` as git-committed files — there is no database. Storage implementation and commit conventions are in ADR-015.
- The audit log is `.foundry/audit.jsonl` — each approval event appends one JSONL line and commits it. `git log -p .foundry/audit.jsonl` is the authoritative inspection tool.
- A proposal diff may contain ADR markdown, runbook markdown, test files, implementation files, and migration files — all reviewed and approved together. The approver sees the complete picture in one diff, not a sequence of separate proposals.
- `graph_delta` in the proposal JSON drives the system map preview mode. It is derived from operation parameters at plan confirmation time — no branch read or subprocess required to render phantom nodes on the canvas.
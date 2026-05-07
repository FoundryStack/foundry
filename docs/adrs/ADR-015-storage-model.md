# ADR-015: Foundry Storage Model — Git and ETS, No Database Requirement

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

The original spec-kit referenced "Project database" as the storage location for proposals,
audit logs, and approval records without justifying the choice. Foundry is a dev tool that
runs against an Elixir project. Requiring a Postgres instance as a prerequisite for
`mix foundry.studio` creates significant installation friction and contradicts the goal
of zero-infrastructure local operation.

The question: does Foundry need a database of its own, or can its state live in git and ETS?

## Decision

**Foundry requires no database of its own. All persistent state uses git-backed files.
All ephemeral state uses ETS. Postgres is a target platform concern, not a Foundry concern.**

---

## Two-Tier Storage Model

### Tier 1 — Git-backed files (persistent, both modes)

All state that must survive process restarts or be auditable lives as files under `.foundry/`
in the target project's repository.

```
.foundry/
  proposals/
    prop_<id>.json          ← one file per proposal, all lifecycle state
  audit.jsonl               ← append-only audit log, one JSON record per line
  manifest.exs              ← project manifest (approvers, sensitive_resources, etc.)
```

**Why git for persistence:**
- Git is already present — every Foundry project is a git repository
- Git commits are cryptographically integrity-checked — the audit log cannot be silently modified
- `git log .foundry/audit.jsonl` gives a human-readable history of every audit event with author and timestamp
- Blob hash coordination (ADR-009) already uses git — proposals and git are already coupled
- No infrastructure to provision, no connection strings, no migration lifecycle separate from the application

**`.foundry/` is committed to the repository.** Proposals in DRAFT state are not committed
(they are written to disk but not staged). Proposals from PENDING_REVIEW onward are committed
on every state transition. The audit log is committed on every approval event.

**Committer identity:** Foundry commits to `.foundry/` using the git user configured in the
project's git config. In cloud mode, a dedicated `foundry-bot` git identity is configured
per deployment. The committer is always distinct from the approver — the approval action
records the human approver's identity in the audit record; the commit records that Foundry
wrote it.

### Tier 2 — ETS (ephemeral, in-process)

All state that is session-scoped or derivable on restart lives in ETS via Nebulex L1.

| State | ETS key | Lost on restart? | Recovery |
|---|---|---|---|
| Spec-kit document cache | `{:spec_kit, path, mtime}` | Yes | Re-read from disk — cheap |
| ExDoc API cache | `{:exdoc, library, version}` | Yes | Re-fetch from ExDoc — cheap |
| Version manifest cache | `{:versions, mix_exs_mtime}` | Yes | Re-run mix task — cheap |
| Active WebSocket sessions | LiveView process state | Yes | Client reconnects automatically |
| DRAFT proposals (pre-submit) | LiveView assigns | Yes | User regenerates — DRAFTs are not committed |

Nothing in Tier 2 is irreplaceable. Restart recovery is automatic and cheap.

---

## Proposal File Format

Each proposal is a single JSON file at `.foundry/proposals/prop_<id>.json`.
The schema matches ADR-014 §Proposal Storage exactly — the file is the record.

**Reasoning trace field** — added at DRAFT creation, committed with the proposal.
Contains structured metadata of the engine's decision steps. Not LLM prompt content
(never stored — ADR-012 §Data Retention).

```json
"reasoning_trace": {
  "intent_classification": {
    "task": "change",
    "operation": "Op.AddRule",
    "confidence": 0.91
  },
  "shell_calls": [
    "cat docs/adrs/ADR-005-change-approval-model.md",
    "mix foundry.context MyApp.Finance.Wallet --json",
    "mix foundry.pattern.find rule --domain Finance"
  ],
  "contradiction_check": {
    "contradiction": false,
    "checked_adrs": ["ADR-005", "ADR-002"],
    "checked_invs": ["INV-001", "INV-011"],
    "summary": null
  },
  "change_class": ":behavioral",
  "confidence_state": "HIGH_CONFIDENCE",
  "session_snapshot": {
    "pending_migrations": 0,
    "open_proposals": 1,
    "lint_errors": 0
  }
}
```

`checked_adrs` and `checked_invs` must be non-empty. An empty list means the
contradiction check was skipped — test failure, not acceptable.

`shell_calls` records the actual bash commands the agent called during the loop.
Used for debugging misclassifications and auditing agent behaviour.

`session_snapshot` captures the Tier 2 state at proposal creation — whether the
agent was aware of pending migrations or conflicting open proposals.

For **question responses** (no proposal file): equivalent fields emitted as attributes
on the `[:foundry, :llm, :call]` telemetry span. Not persisted to disk.

**Dev-mode trace log:** `config :foundry_studio, copilot_trace_log: true` writes
all reasoning traces (including question responses) to
`.foundry/logs/copilot_trace.jsonl` (gitignored, never committed).

Format: one JSON object per line, same schema as proposal `reasoning_trace` plus
`"response_type": "question" | "change_preview" | "blocked" | "clarification"`.

Primary debugging surface during Phase 3 development before the Operations Board
(Phase 6) surfaces telemetry. Set `true` in `config/dev.exs` during active Phase 3
development. Not rotated automatically — clear manually.

State transitions write to the file and commit it:

```
DRAFT created        → file written to disk, NOT committed
PENDING_REVIEW       → file committed: "foundry: proposal prop_<id> submitted for review"
APPROVED             → file updated + committed: "foundry: proposal prop_<id> approved"
APPLIED              → file updated + committed: "foundry: proposal prop_<id> applied"
COMMITTED            → file updated + committed: "foundry: proposal prop_<id> committed [sha]"
REJECTED             → file updated + committed: "foundry: proposal prop_<id> rejected"
STALE                → file updated, NOT committed (ephemeral state, user will regenerate)
```

**Concurrent write safety:** Two simultaneous state transitions on the same proposal file
are resolved by git. The second writer rebases on the first commit. If the rebase fails
(genuine conflict on the same field), Foundry surfaces: "This proposal was modified
concurrently. Refresh to see current state." This is the same optimistic locking principle
as ADR-009, applied to the proposal file itself.

---

## Audit Log Format

`.foundry/audit.jsonl` is an append-only file. Each line is a complete JSON record.
New records are appended and the file is committed after each append.

```jsonl
{"event":"approved","proposal_id":"prop_abc","approver":"sl@co.com","role":"sensitive_lead","slot":1,"timestamp":"2026-03-04T14:22:00Z","diff_hash":"sha256:abc...","change_class":":sensitive"}
{"event":"approved","proposal_id":"prop_abc","approver":"pl@co.com","role":"platform_lead","slot":2,"timestamp":"2026-03-04T14:31:00Z","diff_hash":"sha256:abc...","change_class":":sensitive"}
{"event":"applied","proposal_id":"prop_abc","applied_by":"foundry-bot","timestamp":"2026-03-04T14:32:00Z","commit_sha":"abc123"}
```

**Integrity:** Because the file is committed to git, `git log -p .foundry/audit.jsonl`
shows every append with the committer identity, timestamp, and exact content added.
A record cannot be deleted without that deletion appearing in git history.

**Export:** `mix foundry.audit.export --from=<date> --to=<date>` reads the JSONL file,
filters by timestamp, and outputs a formatted JSON array. For regulatory inspection,
the git history of the file is the primary evidence — the export is a convenience format.

---

## Cloud Mode: Coordination Without a Database

In cloud mode, multiple Studio nodes serve requests. Proposal files live in the git
repository that the cloud instance is connected to. State transitions commit to that
repository. Cross-node coordination uses the git remote as the coordination point:

- Node A writes and commits a state transition → pushes to remote
- Node B reads proposal state → pulls from remote (or reads from its local clone, which is refreshed on file-watch events)
- PubSub (Phoenix, in-process Erlang distribution) handles real-time UI updates — when Node A commits a state transition, it broadcasts the event via PubSub so all connected clients see the update without polling

**Latency:** A git commit + push adds ~100–500ms to a state transition in cloud mode.
This is acceptable for approval workflows (humans are in the loop) but would be unacceptable
for request-per-second operations. Foundry has no request-per-second state transition
requirements — proposals are approved on the order of minutes to hours.

**No git push conflicts in practice:** State transitions on a single proposal are sequential
(a proposal cannot be approved by two people simultaneously for the same slot — the UI
disables the second approval button once the first is recorded). The only genuine concurrent
write case is two different proposals being approved simultaneously, which write to different
files and never conflict.

---

## What Changes From the Previous Spec

The following references in other documents meant "Postgres" implicitly. They now mean
the git-backed file storage described here:

| Document | Old implied meaning | Corrected meaning |
|---|---|---|
| ADR-012 §Data Retention | "Project database" | `.foundry/` files in git |
| ADR-014 §Proposal Storage | "stored in database" | `.foundry/proposals/prop_<id>.json` |
| ADR-014 §Audit Log | "append-only database table" | `.foundry/audit.jsonl` appended and committed |
| AGENTS.md dogfooding note | Foundry uses its own Ash/Postgres stack for its state | Foundry uses git-backed files for its own state; Ash/Postgres is for target platform resources only |

---

## Scope Boundary

Foundry's git-backed storage is for Foundry's own operational state (proposals, audit log).
Target platform domain resources still use `ash_postgres` — Foundry introspects those via
Mix task subprocess and does not own their database. Nebulex caches were already ETS.
ADR-001 is updated to reflect that `ash_postgres` is a target platform dependency, not a Foundry dependency.

## Related Artifact Families

Canonical spec-kit artifacts that preserve project reasoning continue to live under `docs/`
and are committed to git with the rest of the repository. This includes the durable
session-memory findings introduced in ADR-029 at `docs/findings/*.md`. These are not part of
Foundry's ephemeral ETS session state; they are durable project knowledge.

---

## Consequences

- `mix foundry.studio` has zero infrastructure prerequisites beyond Elixir and git
- `.foundry/` directory must be added to the project's `.gitignore` exclusion list for DRAFT proposals: `.foundry/proposals/prop_*.draft.json` — committed proposals use `.json` extension
- The audit log is the git history of `.foundry/audit.jsonl` — `git log -p .foundry/audit.jsonl` is a valid regulatory inspection tool
- Cloud mode adds ~100–500ms latency to state transitions due to git commit + push — acceptable for human-in-the-loop approval workflows
- Foundry's own `mix.exs` does not include `ash_postgres` — the Core Stack table in ADR-001 is corrected to reflect this
- `mix foundry.audit.export` reads `.foundry/audit.jsonl` directly — no database query
- DRAFT proposals are not committed — if the Studio process restarts while a user has an unsaved draft, the draft is lost. This is acceptable: DRAFTs are pre-submission and regeneration is cheap.

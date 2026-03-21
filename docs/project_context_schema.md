# docs/project_context_schema.md — Project Context Schema

> **Status:** Active — governs `mix foundry.project.context` output format.
> **Supersedes:** `docs/spec_kit_index_schema.md` (retired per ADR-021 — the `spec_kit` field
> here is the single authoritative spec-kit index for both the studio and the Tier 1 system prompt).
>
> `Foundry.Studio.SystemMapChannel` uses this as its primary data source.
> `Foundry.Copilot.ContextBuilder` reads the `spec_kit` field from this output for Tier 1
> context assembly — there is no separate `.foundry/spec_kit_index.json` file.
> The agent navigates code and specs as a unified graph: every NodeEntry links to its ADRs,
> runbooks, and compliance requirements, and the `spec_kit` field lists every document with
> its tags and summary. Code→spec linkage is preserved in both directions.
>
> Do not change the schema without updating `Foundry.Studio.SystemMapChannel`,
> `Foundry.Copilot.ContextBuilder`, the studio `data.ts` type definitions, and the CI
> staleness check.

---

## Command

```bash
# Generate (used by studio on load and on file-change events)
mix foundry.project.context

# CI staleness check — exits 0 if current, 1 if any source file is newer than cached output
mix foundry.project.context --check

# Umbrella: scans all apps/* trees automatically when project_type: :umbrella in manifest
mix foundry.project.context
```

Output is written to `.foundry/project_context.json` and committed. CI enforces freshness
via `--check` on the same pattern as `mix foundry.spec_kit.index --check`.

---

## Top-Level Structure

```json
{
  "generated_at": "2026-03-21T10:00:00Z",
  "project": "MyApp",
  "project_type": "standard",
  "domain_type": "igaming",
  "nodes": [ ...NodeEntry... ],
  "edges": [ ...EdgeEntry... ],
  "spec_kit": { ...SpecKitIndex... }
}
```

| Field | Type | Notes |
|---|---|---|
| `generated_at` | ISO 8601 string | Generation timestamp |
| `project` | string | From `.foundry/manifest.exs` `project_name` |
| `project_type` | `"standard" \| "umbrella"` | From manifest; `"standard"` if absent |
| `domain_type` | string | From manifest; `null` if absent |
| `nodes` | NodeEntry[] | One entry per module — see below |
| `edges` | EdgeEntry[] | Derived from DSL declarations — see below |
| `spec_kit` | SpecKitIndex | Index metadata only; full content fetched on demand |

---

## NodeEntry Schema

Each entry corresponds to one compiled module. Schema matches `mix foundry.context <Module>`
exactly — this is a bulk projection of per-module context into the graph.

```json
{
  "id": "MyApp.Finance.WithdrawalTransfer",
  "module": "MyApp.Finance.WithdrawalTransfer",
  "type": "transfer",
  "domain": "Finance",
  "app": null,
  "sensitive": true,
  "description": "Multi-step Reactor executing player withdrawal. Enforces KYC, cooling-off, balance checks. Idempotent.",
  "attributes": [
    {
      "name": "amount",
      "type": "Ash.Type.Money",
      "pii": false,
      "sensitive": true,
      "money": true,
      "cldr_backend": "MyApp.Cldr",
      "description": "Withdrawal amount in player currency"
    }
  ],
  "actions": [
    { "name": "execute", "change_class": "sensitive" },
    { "name": "rollback", "change_class": "sensitive" }
  ],
  "compliance": ["RG-UK-014", "RG-MGA-007"],
  "adrs": ["ADR-002", "ADR-005"],
  "runbook": "docs/runbooks/withdrawal_transfer.md",
  "test_coverage": {
    "property_tests": true,
    "scenario_tests": true,
    "e2e_tests": false
  },
  "data_layer": "ash_postgres",
  "pending_migrations": false,
  "paper_trail": true,
  "archival": true,
  "state_machine": {
    "present": false,
    "states": [],
    "transitions": [],
    "state_attribute": null
  },
  "api_routes": [
    { "route": "/withdraw", "method": "POST", "auth": true, "rate_limited": true, "idempotent": true }
  ],
  "telemetry_prefix": ["my_app", "finance", "withdrawal_transfer"],
  "money_attributes": [
    { "name": "amount", "type": "Ash.Type.Money", "cldr_backend": "MyApp.Cldr" }
  ],
  "authentication_subject": false,
  "oban_queues": [],
  "rate_limited": true,
  "feature_flags": [],
  "steps": [ ...StepEntry... ],
  "outputs": [ ...OutputEntry... ],
  "last_modified": "2026-03-02"
}
```

### NodeEntry field definitions

| Field | Type | Notes |
|---|---|---|
| `id` | string | Fully-qualified module name. Primary key for edges. |
| `module` | string | Same as `id`. Retained for compatibility with per-module context schema. |
| `type` | enum | See Node types below |
| `domain` | string | Ash domain short name |
| `app` | string\|null | Umbrella app name (`"igaming_core"`); `null` for standard projects |
| `sensitive` | boolean | From manifest `sensitive_resources` list |
| `description` | string | `@moduledoc` first paragraph |
| `attributes` | AttributeEntry[] | Empty for non-resource types |
| `actions` | ActionEntry[] | Empty for non-resource types |
| `compliance` | string[] | Requirement IDs linked via DSL |
| `adrs` | string[] | ADR IDs linked via DSL `@adrs` annotation |
| `runbook` | string\|null | Path to runbook doc; `null` if none declared |
| `test_coverage` | TestCoverage | Three boolean flags |
| `data_layer` | string\|null | `"ash_postgres"` etc.; `null` for non-persisted types |
| `pending_migrations` | boolean | True if `mix ash.codegen` would produce output |
| `paper_trail` | boolean | True if `AshPaperTrail` extension present |
| `archival` | boolean | True if `AshArchival` extension present |
| `state_machine` | StateMachine | FSM declaration |
| `api_routes` | RouteEntry[] | From `AshJsonApi` or Phoenix router declarations |
| `telemetry_prefix` | string[] | Declared telemetry prefix atoms |
| `money_attributes` | MoneyAttr[] | Attributes using `Ash.Type.Money` |
| `authentication_subject` | boolean | True if `AshAuthentication` subject |
| `oban_queues` | string[] | Declared Oban queue names |
| `rate_limited` | boolean | True if rate limiting declared |
| `feature_flags` | FeatureFlag[] | `fun_with_flags` flags gating this module |
| `steps` | StepEntry[] | Reactor/Transfer steps; empty for resources |
| `outputs` | OutputEntry[] | Terminal outcomes; empty for resources |
| `last_modified` | ISO 8601 date | File mtime |

### Node types

| Type | Source | Example |
|---|---|---|
| `resource` | Ash resource module | `MyApp.Finance.Wallet` |
| `transfer` | Ash Reactor with Transfer semantics | `MyApp.Finance.WithdrawalTransfer` |
| `reactor` | Ash Reactor (non-Transfer) | `MyApp.Compliance.AmlScreeningReactor` |
| `rule` | Ash policy or rule module | `MyApp.Compliance.KycCheck` |
| `job` | Oban worker | `MyApp.Workers.KycPoller` |
| `liveview` | Phoenix LiveView | `MyApp.Finance.WalletLive` |
| `liveresource` | AshAdmin / AshLiveView resource | `MyApp.Identity.PlayerLiveResource` |
| `blueprint` | Ash extension blueprint config | `MyApp.Game.DepositBonusBlueprint` |
| `provider` | External integration adapter | `MyApp.Finance.PaymentGatewayAdapter` |
| `trigger` | HTTP endpoint or scheduler entry point | `/api/register`, `cron 0 * * * *` |
| `agent` | Standalone AshAI agent module | `MyApp.Risk.WithdrawalScorerAgent` |

### StepEntry schema

```json
{
  "id": "w-check-limits",
  "name": "check_limits",
  "kind": "standard | agent",
  "reads": ["MyApp.Identity.SpendingLimit"],
  "writes": [],
  "compliance": ["RG-UK-031", "RG-MGA-022"],
  "change_class": "behavioral",
  "guard_rules": ["MyApp.Compliance.ResponsibleGamingCheck"],
  "compensation": null,
  "agent": {
    "agent_type": "scorer",
    "model": "claude-sonnet",
    "input_schema": "RiskInput",
    "output_schema": "RiskScore",
    "tools": ["read_player_history", "check_velocity", "read_spending_limit"],
    "confidence_threshold": 0.7,
    "on_low_confidence": "escalate_human",
    "human_gate": {
      "queue": "compliance_review",
      "sla_hours": 4,
      "escalation_path": "compliance_officer"
    },
    "telemetry_prefix": ["my_app", "risk", "withdrawal", "check_limits"]
  }
}
```

`agent` field is `null` for `kind: "standard"` steps.
`agent` field is required for `kind: "agent"` steps — a step with `kind: "agent"` and
`agent: null` is a schema error and `mix foundry.project.context` will warn and omit the step.

### OutputEntry schema

```json
{
  "id": "withdraw-commit",
  "label": "committed",
  "kind": "success | error | compensation"
}
```

### EdgeEntry schema

```json
{
  "from": "MyApp.Finance.WithdrawalTransfer",
  "to": "MyApp.Finance.Wallet",
  "relation": "writes",
  "cross_app": false,
  "cross_project": false
}
```

#### Edge relation types

| Relation | Meaning |
|---|---|
| `writes` | Source creates or mutates target resource |
| `reads` | Source reads target resource |
| `triggers` | Source initiates target (HTTP → action, cron → reactor) |
| `async` | Source enqueues target asynchronously via Oban |
| `guard` | Source rule gates execution of target |
| `eligibleIf` | Source blueprint requires target condition |
| `compensates` | Source step undoes target step on failure |
| `calls` | Cross-project declared dependency (manifest only) |

`cross_app: true` when `from` and `to` belong to different umbrella apps.
`cross_project: true` when the edge is declared in `cross_project_edges` in the manifest.

---

## SpecKitIndex embedded in context

The spec-kit index is embedded in `project.context` as metadata only. Full document
content is never included — it is fetched on demand via `FoundryChannel` `fetch_document` event.

This field has two consumers:
- **Studio** (`Foundry.Studio.SystemMapChannel`) — renders the spec-kit panel and overlays
  document links on node detail drawers
- **Copilot Tier 1** (`Foundry.Copilot.ContextBuilder`) — reads the `spec_kit` field from
  the cached `mix foundry.project.context` output at session startup to build the system prompt.
  The agent uses it to decide which documents to read via bash. No search tool needed.

The unified structure means node `adrs`, `runbook`, and `compliance` fields link outward to
the same document entries in `spec_kit`, preserving bidirectional code→spec traceability in
a single data source.

### JSON schema

```json
{
  "spec_kit": {
    "index_token_count": 387,
    "index_token_warn": true,
    "index_token_limit": 400,
    "adrs": [
      {
        "id": "ADR-003",
        "type": "adr",
        "title": "Agent Context — Structured Retrieval, Not RAG Over Code",
        "status": "Accepted",
        "file_path": "docs/adrs/ADR-003-agent-context-strategy.md",
        "summary": "Structured retrieval over live DSL introspection for code-derived information. Full inclusion for spec-kit documents. Three-tier library documentation strategy.",
        "tags": ["context", "retrieval", "agent", "copilot"],
        "supersedes": null,
        "superseded_by": null,
        "last_modified": "2026-03-16"
      }
    ],
    "runbooks": [
      {
        "id": "runbook:withdrawal_transfer",
        "type": "runbook",
        "title": "Runbook: WithdrawalTransfer",
        "file_path": "docs/runbooks/withdrawal_transfer.md",
        "summary": "Operational failure scenarios for WithdrawalTransfer Reactor.",
        "tags": ["withdrawal", "transfer", "reactor", "compensation"],
        "last_modified": "2026-03-02"
      }
    ],
    "regulations": [
      {
        "id": "regulation:platform_invariants",
        "type": "regulation",
        "title": "Platform Invariants",
        "file_path": "docs/regulations/platform_invariants.md",
        "summary": "Hard invariants enforced by compiler, linter, and CI.",
        "tags": ["invariants", "lint", "ci", "compliance"],
        "last_modified": "2026-03-10"
      }
    ],
    "agents": {
      "id": "AGENTS",
      "type": "agents",
      "title": "AGENTS.md — Foundry",
      "file_path": "AGENTS.md",
      "summary": "Primary context document. Invariants, change classification, agent reasoning sequence.",
      "tags": ["agents", "invariants", "copilot", "change", "classification"],
      "last_modified": "2026-03-18"
    },
    "usage_rules": [
      {
        "id": "usage_rules:ash",
        "type": "usage_rules",
        "title": "Ash 3.x Usage Rules",
        "file_path": ".foundry/usage_rules/ash.md",
        "summary": "Idiomatic Ash 3.x patterns, anti-patterns, and version-specific gotchas for agent code generation.",
        "tags": ["ash", "dsl", "resource", "action", "policy"],
        "last_modified": "2026-03-10"
      }
    ]
  }
}
```

### Per-document entry fields

| Field | Type | Extraction source | Required |
|---|---|---|---|
| `id` | string | Filename prefix (`ADR-010`) or `AGENTS`, `runbook:<slug>`, `regulation:<slug>`, `usage_rules:<lib>` | Yes |
| `type` | enum | Derived from directory path — see table below | Yes |
| `title` | string | First H1 heading | Yes |
| `status` | string | `**Status:**` frontmatter field; `null` for non-ADR documents | ADRs only |
| `file_path` | string | Relative path from project root | Yes |
| `summary` | string | First substantive paragraph, max 2 sentences / 300 characters | Yes |
| `tags` | string[] | Extracted keywords — see Tag Extraction below | Yes |
| `supersedes` | string\|null | `**Supersedes:**` frontmatter value | No |
| `superseded_by` | string\|null | `**Superseded by:**` frontmatter value | No |
| `last_modified` | string | File mtime, ISO 8601 date | Yes |

### Document types

| Directory / path | Type | ID format | Example |
|---|---|---|---|
| `docs/adrs/` | `adr` | `ADR-NNN` from filename | `ADR-010` |
| `docs/runbooks/` | `runbook` | `runbook:<slug>` | `runbook:studio_copilot_failure` |
| `docs/regulations/` | `regulation` | `regulation:<slug>` | `regulation:platform_invariants` |
| `AGENTS.md` | `agents` | `AGENTS` | `AGENTS` |
| `.foundry/usage_rules/` | `usage_rules` | `usage_rules:<lib>` | `usage_rules:ash` |

### Tag extraction

Lowercase keywords from title + summary + H2 headings:

1. Split into words, lowercase, strip punctuation
2. Remove stop words: the, a, an, is, are, for, with, by, in, on, at, to, of, and, or,
   not, this, that, it, its, be, as, from, will, must, when, if, all, any, each, per, no
3. Remove words shorter than 3 characters
4. Deduplicate, sort alphabetically
5. Maximum 12 tags per document

**Manual override:** A document may declare `**Tags:** llm, context, adapter` in frontmatter.
Merged with extracted tags, capped at 12. Use sparingly.

### Summary extraction

First substantive paragraph after the frontmatter block (lines matching `**Key:** Value`).
Skip: blockquotes, code fences, horizontal rules, headings, empty lines.
Truncate at 2 sentences or 300 characters, whichever comes first. Do not truncate mid-word.
If no substantive paragraph found in first 30 lines: `summary` is `null`; generation warns.

### Token budget

The `spec_kit` field must serialize to ≤ **400 tokens** for inclusion in Tier 1.
`mix foundry.project.context` warns (but does not fail) when `index_token_count > 360` (10% headroom).
`index_token_warn: true` is set when the count exceeds 360. The studio renders a warning badge.

Growth rate: ~15 tokens per document at minimum; summaries for longer ADRs run 20–25 tokens.
Practical ceiling: **24 documents** before the warn threshold is reliably hit.

When the budget is exceeded: consolidate runbooks first (they have the lowest information density
per token), then consider shortening summaries for large ADRs.

### Exclusion rules

The following files must NOT be indexed. They are infrastructure references, not documents the
agent reasons about:

| File | Reason |
|---|---|
| `docs/project_context_schema.md` | This file — describes its own format |
| `docs/spec_kit_index_schema.md` | Retired tombstone |
| `docs/mix_task_summary_schemas.md` | Schema reference for implementors |
| `docs/reference-project-fixture.md` | Test fixture, not spec-kit |
| `docs/manifest-schema-draft.md` | Pre-ADR-011 draft; superseded |
| `docs/BUILD_SEQUENCE.md` | Implementation sequencing; not a decision or invariant |

Schema documents (files whose purpose is to describe other documents' formats) are never
indexed. BUILD_SEQUENCE.md captures sequencing, not decisions — it is not spec-kit.

`index_token_warn: true` when `index_token_count > 360` (10% below the 400-token limit).
The studio renders a visible warning badge on the spec-kit panel when this flag is set.
The copilot logs a warning but does not fail — context is still assembled.

---

## Umbrella output shape

In umbrella mode, `app` is populated on each node:

```json
{ "id": "IgamingCore.Finance.Wallet", "app": "igaming_core", "domain": "Finance", ... }
{ "id": "IgamingWeb.Finance.WalletController", "app": "igaming_web", "domain": "Finance", ... }
```

Cross-app edges carry `cross_app: true`:

```json
{ "from": "IgamingWeb.Finance.WalletController", "to": "IgamingCore.Finance.Wallet", "relation": "reads", "cross_app": true }
```

The top-level structure gains an `apps` field in umbrella mode:

```json
{
  "project_type": "umbrella",
  "apps": [
    { "name": "igaming_core", "path": "apps/igaming_core", "layer": "domain" },
    { "name": "igaming_web",  "path": "apps/igaming_web",  "layer": "web" },
    { "name": "igaming",      "path": "apps/igaming",      "layer": "application" }
  ]
}
```

---

## What is NOT in this output

- Full document content — fetched on demand via `FoundryChannel` `fetch_document`
- Full `mix.exs` dependency list — available via `bash("cat mix.exs")`
- Proposal content — scanned from `.foundry/proposals/` by `mix foundry.project.status`
- Audit log — append-only, never indexed
- `_build/`, `deps/` — never read
- LLM context tiers — this file is studio data, not agent context
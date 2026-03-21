# docs/project_context_schema.md — Project Context Schema

> **Status:** Active — governs `mix foundry.project.context` output format.
> **Supersedes:** `docs/spec_kit_index_schema.md` (retired per ADR-020 — the `spec_kit`
> field here is the single authoritative spec-kit index for both the studio and the
> Tier 1 system prompt).
>
> `Foundry.Studio.SystemMapChannel` uses this as its primary data source.
> `Foundry.Copilot.ContextBuilder` reads the `spec_kit` field from the ETS-cached
> project context for Tier 1 context assembly — there is no separate
> `.foundry/spec_kit_index.json` file and no separate `mix foundry.spec_kit.index` task.
> The agent navigates code and specs as a unified graph: every NodeEntry links to its
> ADRs, runbooks, and compliance requirements, and the `spec_kit` field lists every
> document with its tags and summary. Code→spec linkage is preserved in both directions.
>
> Do not change the schema without updating `Foundry.Studio.SystemMapChannel`,
> `Foundry.Copilot.ContextBuilder`, the studio `data.ts` type definitions, and the
> CI staleness check.

---

## Commands

```bash
# Generate and update lockfile (used by studio on load and on file-change events)
mix foundry.project.context

# Per-module detail — same command, optional argument narrows to one NodeEntry
mix foundry.project.context MyApp.Finance.Wallet

# CI staleness check — compares sha256(lib/**/*.ex + test/**/*.ex) against .foundry/context.lock
# Exits 0 if hashes match, 1 if they differ or if lock file is absent
mix foundry.project.context --check

# Umbrella: scans all apps/* trees automatically when project_type: :umbrella in manifest
mix foundry.project.context
```

The command output lives in ETS (Nebulex L1), not in a committed JSON file.
`.foundry/context.lock` is the only committed artifact — a 50-byte SHA256 hash of
all source files. CI enforces freshness via `--check`.

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
  "spec_kit": { ...SpecKitIndex... },
  "graph_delta": null
}
```

| Field | Type | Notes |
|---|---|---|
| `generated_at` | ISO 8601 string | Generation timestamp |
| `project` | string | From `.foundry/manifest.exs` `project_name` |
| `project_type` | `"standard" \| "umbrella"` | From manifest; `"standard"` if absent |
| `domain_type` | string | From manifest; `null` if absent |
| `nodes` | NodeEntry[] | One entry per module — alphabetical by FQN |
| `edges` | EdgeEntry[] | Derived from DSL declarations — ordered by from FQN, then to FQN |
| `spec_kit` | SpecKitIndex | Index metadata only; full parsed document fetched on demand |
| `graph_delta` | GraphDelta \| null | Present when a session state exists; shows changes vs session start |

---

## NodeEntry Schema

Each entry corresponds to one compiled module. Schema matches
`mix foundry.project.context <Module>` exactly — the bulk output is a projection of
per-module context into the graph.

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
  "rules": ["SufficientBalance", "WithdrawalLimitNotExceeded"],
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
  "agent_steps": [],
  "last_modified": "2026-03-02"
}
```

### NodeEntry field definitions

| Field | Type | Notes |
|---|---|---|
| `id` | string | Fully-qualified module name. Primary key for edges. |
| `module` | string | Same as `id`. Retained for compatibility with per-module schema. |
| `type` | enum | See Node types below |
| `domain` | string | Ash domain short name |
| `app` | string\|null | Umbrella app name (`"igaming_core"`); `null` for standard projects |
| `sensitive` | boolean | From manifest `sensitive_resources` list |
| `description` | string | `@moduledoc` first paragraph |
| `attributes` | AttributeEntry[] | Empty for non-resource types |
| `actions` | ActionEntry[] | Empty for non-resource types |
| `rules` | string[] | Short names of policy/rule modules declared on this resource |
| `compliance` | string[] | Requirement IDs linked via DSL |
| `adrs` | string[] | ADR IDs linked via DSL `@adrs` annotation |
| `runbook` | string\|null | Path to runbook doc; `null` if none declared |
| `test_coverage` | TestCoverage | Three boolean flags |
| `data_layer` | string\|null | `"ash_postgres"` etc.; `null` for non-persisted types |
| `pending_migrations` | boolean | True if `mix ash.codegen --check` exits non-zero |
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
| `agent_steps` | AgentStep[] | AshAI agent step declarations; `[]` if none |
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

---

## EdgeEntry Schema

```json
{
  "from": "MyApp.Finance.WithdrawalTransfer",
  "to": "MyApp.Finance.Wallet",
  "relation": "writes",
  "cross_app": false,
  "cross_project": false
}
```

Edges are ordered: `from` FQN ascending, then `to` FQN ascending.

---

## GraphDelta Schema

Present when `Foundry.Context.SessionState` holds a baseline for the current session.
`null` when no editing session is active.

```json
{
  "graph_delta": {
    "session_started_at": "2026-03-21T09:00:00Z",
    "added_nodes": ["MyApp.Finance.NewResource"],
    "changed_nodes": ["MyApp.Finance.Wallet"],
    "removed_nodes": [],
    "added_edges": [
      {"from": "MyApp.Finance.NewResource", "to": "MyApp.Finance.Wallet", "relation": "reads"}
    ],
    "removed_edges": []
  }
}
```

The studio uses `graph_delta` to render the system map in preview mode during active
proposals: added nodes highlighted green, changed nodes amber, removed nodes dimmed red.

---

## SpecKitDocument Struct

Returned by `FoundryChannel fetch_document` events. Parsed from the MDEx AST cached
in ETS by `{:spec_kit, file_path, mtime}`. The index builder and document server share
the same cached AST — one parse, two views.

```json
{
  "id": "ADR-003",
  "type": "adr",
  "title": "Agent Context — Structured Retrieval, Not RAG Over Code",
  "status": "Accepted",
  "file_path": "docs/adrs/ADR-003-agent-context-strategy.md",
  "sections": [
    { "heading": "Context", "body": "The copilot needs accurate..." },
    { "heading": "Decision", "body": "Structured retrieval over..." }
  ],
  "compliance_refs": [],
  "module_refs": ["Foundry.Copilot.ContextBuilder", "Foundry.Context.PatternFinder"],
  "last_modified": "2026-03-16"
}
```

| Field | Type | Notes |
|---|---|---|
| `id` | string | Same as SpecKitIndex entry id |
| `type` | enum | `adr`, `runbook`, `regulation`, `agents`, `usage_rules` |
| `title` | string | First H1 heading |
| `status` | string\|null | `**Status:**` frontmatter field; `null` for non-ADR documents |
| `file_path` | string | Relative path from project root |
| `sections` | Section[] | H2 headings with body text (list of `{heading, body}`) |
| `compliance_refs` | string[] | RG-* requirement IDs extracted from body text |
| `module_refs` | string[] | Fully-qualified Elixir module names extracted from body text |
| `last_modified` | string | File mtime, ISO 8601 date |

The diff view of a spec-kit document (in the proposal review panel) uses the raw
unified git diff output, not `SpecKitDocument` sections. The parsed struct is for the
read/navigation view only.

---

## SpecKitIndex Schema

This field has two consumers:
- **Studio** (`Foundry.Studio.SystemMapChannel`) — renders the spec-kit panel and
  overlays document links on node detail drawers
- **Copilot Tier 1** (`Foundry.Copilot.ContextBuilder`) — reads the `spec_kit` field
  from the cached project context at session startup to build the system prompt. The
  agent uses it to decide which documents to read via bash. No search tool needed.

```json
{
  "spec_kit": {
    "index_token_count": 387,
    "index_token_warn": false,
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
    "runbooks": [ ...entries... ],
    "regulations": [ ...entries... ],
    "agents": { ...entry... },
    "usage_rules": [ ...entries... ]
  }
}
```

### Per-document index entry fields

| Field | Type | Extraction source | Required |
|---|---|---|---|
| `id` | string | Filename prefix (`ADR-010`) or `AGENTS`, `runbook:<slug>`, `regulation:<slug>`, `usage_rules:<lib>` | Yes |
| `type` | enum | Derived from directory path | Yes |
| `title` | string | First H1 heading | Yes |
| `status` | string | `**Status:**` frontmatter field; `null` for non-ADR documents | ADRs only |
| `file_path` | string | Relative path from project root | Yes |
| `summary` | string | First substantive paragraph, max 2 sentences / 300 characters | Yes |
| `tags` | string[] | Extracted keywords — see Tag Extraction | Yes |
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

1. Split into words, lowercase, strip punctuation
2. Remove stop words: the, a, an, is, are, for, with, by, in, on, at, to, of, and, or,
   not, this, that, it, its, be, as, from, will, must, when, if, all, any, each, per, no
3. Remove words shorter than 3 characters
4. Deduplicate, sort alphabetically
5. Maximum 12 tags per document

**Manual override:** A document may declare `**Tags:** llm, context, adapter` in
frontmatter. Merged with extracted tags, capped at 12. Use sparingly.

### Summary extraction

First substantive paragraph after the frontmatter block (lines matching `**Key:** Value`).
Skip: blockquotes, code fences, horizontal rules, headings, empty lines.
Truncate at 2 sentences or 300 characters, whichever comes first. Do not truncate mid-word.
If no substantive paragraph found in first 30 lines: `summary` is `null`; generation warns.

### Token budget

The `spec_kit` field must serialize to ≤ **400 tokens** for inclusion in Tier 1.
`mix foundry.project.context` warns (but does not fail) when `index_token_count > 360`
(10% headroom). `index_token_warn: true` is set when the count exceeds 360. The studio
renders a warning badge.

Growth rate: ~15 tokens per document at minimum; summaries for longer ADRs run 20–25
tokens. Practical ceiling: **24 documents** before the warn threshold is reliably hit.

**Testing the warn path:** The Phase 1 acceptance tests include a synthetic corpus
expansion test — documents are added to push `index_token_count` above 360 and the
test asserts `index_token_warn: true`. This ensures the warning logic is exercised,
not just the happy path.

### Exclusion rules

The following files must NOT be indexed:

| File | Reason |
|---|---|
| `docs/project_context_schema.md` | This file — describes its own format |
| `docs/spec_kit_index_schema.md` | Retired tombstone |
| `docs/mix_task_summary_schemas.md` | Schema reference for implementors |
| `docs/reference-project-fixture.md` | Test fixture, not spec-kit |
| `docs/manifest-schema-draft.md` | Pre-ADR-011 draft; superseded |
| `docs/BUILD_SEQUENCE.md` | Implementation sequencing; not a decision or invariant |

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

- Full document content — fetched on demand via `FoundryChannel fetch_document`
  (returns `SpecKitDocument`) or `fetch_file` (returns raw string)
- Full `mix.exs` dependency list — available via `bash("cat mix.exs")`
- Proposal content — scanned from `.foundry/proposals/` by `mix foundry.project.status`
- Audit log — append-only, never indexed
- `_build/`, `deps/` — never read
- LLM context tiers — this data lives in ETS; ContextBuilder reads from it
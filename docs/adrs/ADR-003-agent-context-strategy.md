# ADR-003: Agent Context — Structured Retrieval, Not RAG Over Code

**Status:** Accepted
**Date:** 2026-03
**Deciders:** Platform team

---

## Context

The copilot needs accurate, current information about the project's domain model when
generating proposals. Two approaches:

1. **Classic RAG**: chunk all source files, embed them, vector-search for relevant chunks
2. **Structured retrieval**: query the live Spark DSL introspection directly

We also need library documentation to prevent hallucination on Ash 3.x APIs.

## Decision

**Structured retrieval over live DSL introspection for all code-derived information.**
**Small event-driven RAG only for unstructured prose documents (ADRs, runbooks, regulations).**
**Three-tier library documentation strategy for anti-hallucination.**

### What uses structured retrieval

Everything derivable from compiled modules:
- Resource attributes, actions, relationships, policies
- Transfer steps, rules, idempotency declarations
- Blueprint config schemas, eligibility rules
- Compliance links and requirement mappings
- Runbook links, alert declarations
- State machine states and transitions
- AshJsonApi routes and route options
- Paper trail and archival configuration
- Monetary attribute types and CLDR backend reference
- Authentication subject configuration
- Oban queue assignments
- Telemetry prefix declarations
- Pending migration status
- Feature flag usage

Source: `mix foundry.project.context <Module>` — re-runs on every copilot request,
always current. The bulk form `mix foundry.project.context` (no module argument) returns
the full node corpus with edges and spec-kit index metadata.

### What uses full inclusion (not RAG)

The spec-kit documents — ADRs, runbooks, regulations — are parsed once to structured
`SpecKitDocument` values and included in the LLM context on every request. No indexing,
no embeddings, no vector search.

**Why not RAG:** At current and projected scale, the entire spec-kit fits comfortably in
a single context window (~4000 tokens at maturity, well within the ADR-010 budget).
RAG adds infrastructure complexity, staleness risk, and retrieval errors to solve a
problem that doesn't exist at this scale. Full inclusion is simpler, always current
(read from disk at request time), and more reliable — the copilot sees every constraint,
not just the ones a similarity search happened to surface.

**The corpus boundary is strict:** spec-kit docs only (`docs/adrs/`, `docs/runbooks/`,
`docs/regulations/`). Source files (`lib/`, `test/`) are never included wholesale —
those use structured DSL introspection. The combination of full spec-kit inclusion +
structured code retrieval gives the copilot complete context without the overhead of
a general-purpose embedding pipeline.

**Parsing:** Each spec-kit document is parsed once with MDEx to a `%MDEx.Document{}`
AST, cached in ETS by `{:spec_kit, file_path, mtime}`. Two consumers share the same
cached AST: the index builder (summary, tags, mtime — lightweight, runs at startup)
and the document server (full `SpecKitDocument` struct with sections, compliance_refs,
module_refs — produced on demand for the studio detail panel and diff view). One parse,
two views. The diff view of a spec-kit document uses the raw unified git diff, not
parsed sections — the same format developers already read in code review.

**Cache strategy:** The spec-kit AST cache is keyed on `{file_path, mtime}`. If no
file has changed since the last request, the cached AST is reused. Implemented via
Nebulex L1 (in-process ETS). No embedding pipeline, no vector index, no scheduled
sync jobs. Pre-warmed at Studio startup.

### Three-tier library documentation

**Tier 1 (always in every LLM prompt):**
```
Current stack: ash 3.4.1, ash_double_entry 1.0.3, ash_postgres 2.x, phoenix 1.7.x, ...
```
This prevents Ash 2.x vs 3.x confusion, the most common hallucination class.
Stack versions are sourced from `mix.lock` resolved values via the `stack` field
of `mix foundry.project.status`. `ContextBuilder` reads this field at Tier 1 assembly.

**Tier 2 (fetched on demand, cached 24h):**
ExDoc JSON for the specific DSL element being generated. When generating a resource
attribute, fetch `GET /api/docs/ash/Resource.Dsl.Attribute` — exact current options,
types, defaults. Not chunks. The exact API surface for the specific element.

The ExDoc cache uses per-library-per-version keys: `{:exdoc, library_name, version}`
(e.g., `{:exdoc, "ash", "3.4.1"}`). When `mix.exs` changes, only entries for libraries
whose versions changed are evicted. Other libraries' cached docs remain valid.
Implemented via Nebulex L1.

**Tier 3 (fetched on demand, no cache needed — it's in the project):**
The closest existing example of the pattern being generated, retrieved from the actual
codebase. When generating a new Rule, retrieve the simplest existing Rule. The agent
copies a working pattern from the same project instead of synthesizing from training
memory. Hallucination rate on Ash-specific syntax drops to near zero.

## Rationale

Classic RAG over code is wrong for this use case for three reasons:

**Staleness**: chunks indexed at a point in time. Ash resources change frequently during
active development. A chunk about `BonusAward.wagering_progress_minor` that's 2 days
old is wrong after a refactor.

**Wrong granularity**: vector search finds semantically similar paragraphs. The agent
needs attribute-level precision. "What does `wagering_progress_minor` track?" needs
the exact `@description` tag — not the surrounding module text.

**Hallucination amplification**: RAG retrieves plausible-looking text. With poor
metadata quality, it confidently returns wrong context. Structured introspection fails
explicitly when a module doesn't exist — it doesn't return something that looks like
it might be right.

For spec-kit documents, RAG is equally unnecessary: the entire corpus fits in context.
Similarity search would add infrastructure complexity and retrieval failures to a problem
that full inclusion solves trivially. The copilot should see *all* constraints every
time, not a similarity-ranked subset that might miss the relevant ADR.

## Consequences

- The `mix foundry.project.context` task is the critical path — its schema must be
  stable. Per-module access via `mix foundry.project.context <Module>` is the copilot's
  lazy lookup tool.
- Every piece of information the copilot uses for code decisions must be traceable to
  a live source
- Spec-kit docs are parsed once per mtime change, cached in ETS — no indexing pipeline,
  no embedding model dependency
- There is no RAG infrastructure in Foundry. If the spec-kit grows beyond ~15,000 tokens,
  the context strategy should be revisited — but this is not a near-term concern and
  should not be optimised for prematurely
- Nebulex is used for the spec-kit AST cache, ExDoc cache, project context cache, and
  project status cache — no additional cache infrastructure

## `mix foundry.project.context <Module>` Schema

This schema is the contract for both the per-module shell tool and each NodeEntry within
the bulk `mix foundry.project.context` output. Breaking changes require an ADR. Fields
marked `(new)` were added in the post-review pass to cover the full ecosystem.

```json
{
  "module": "MyApp.Finance.WithdrawalTransfer",
  "type": "transfer",
  "domain": "Finance",
  "app": null,
  "description": "...",
  "steps": [...],
  "rules": ["SufficientBalance", "SameSource", "WithdrawalLimit"],
  "compliance": ["RG-UK-014", "RG-MGA-007"],
  "runbook": "docs/runbooks/withdrawal_transfer.md",
  "invariants": [...],
  "related_resources": ["Wallet", "LedgerEntry", "WithdrawalRequest"],
  "adrs": ["ADR-002"],
  "last_modified": "2026-03-01",
  "sensitive": true,
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

  "api_routes": [],

  "telemetry_prefix": ["my_app", "finance", "withdrawal_transfer"],

  "money_attributes": [
    { "name": "amount", "type": "Ash.Type.Money", "cldr_backend": "MyApp.Cldr" }
  ],

  "authentication_subject": false,

  "oban_queues": [],

  "rate_limited": false,

  "feature_flags": [],

  "agent_steps": []
}
```

**`app`** — `null` for standard projects; umbrella app short name (e.g. `"igaming_core"`)
for umbrella projects.

**`rules`** — short names of policy or rule modules declared on this resource
(e.g. `["SufficientBalance", "SameSource"]`). Empty list if none.

**`agent_steps`** — empty list `[]` when the module has no AshAI agent step declarations.
A non-empty list requires AshAI v2 or later (ADR-017). The task warns (not fails) if
AshAI is present but the version cannot be determined.

Do not invent fields. If a field is absent from this schema, it does not exist.
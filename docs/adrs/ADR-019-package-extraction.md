# ADR-019: Package Extraction — Reusable Primitives vs Foundry-Internal Modules

**Status:** Deferred — write in full when first package is published to Hex
**Date:** 2026-03
**Deciders:** Platform team

---

## Context

Foundry is a meta-platform. Parts of it implement general-purpose primitives that any
Ash/Spark project could use: DSL introspection, lint rule running, human-in-the-loop
gates for Reactors. The question is which parts earn their own Hex package and which
parts are better kept internal.

The cost of extracting too early: premature abstraction, unstable API surfaces, maintenance
overhead before the design is proven. The cost of extracting too late: the logic becomes
entangled with Foundry internals and is harder to separate cleanly.

The decision criterion used: **extract if and only if there is a clear audience outside
Foundry who would use the package as-is, with no Foundry-specific configuration.**

---

## Decision

### Extracted as standalone packages

| Package | Rationale |
|---|---|
| `spark_meta` | Any Spark-based project wanting structured JSON/struct output of DSL state benefits from this. The generic walker requires no Foundry config. `SparkMeta.Extension` opt-in hook lets extension authors (e.g. AshPyro) provide richer output without modifying the core. |
| `spark_lint` | The rule runner protocol (behaviour + violation struct + mix task) is ~200 lines and completely domain-agnostic. Shipping it separately lets external teams publish their own rule packages. Foundry's actual rules ship in `Foundry.LintRules.*` (internal). |
| `reactor_human_gate` | Human-in-the-loop gates are useful to any AshAI team independently of Foundry. The `HumanGateTask` resource and `WaitForHumanStep` have no Foundry assumptions. Usable before Phase 8 of Foundry. |
| `reactor_agent_step` | The Spark DSL extension for Reactor agent step declarations (`agent_type`, `model`, `confidence_threshold`, `on_low_confidence`, `tools`, `telemetry_prefix`) is a natural companion to `reactor_human_gate`. Extraction confirmed alongside it. Depends on `reactor_human_gate`. |

### Rejected — stays internal

| Candidate | Why rejected |
|---|---|
| `ash_governed` (DSL annotation for sensitive resources) | Not needed for v1. `manifest.sensitive_resources` list is the declaration mechanism. A DSL annotation would improve developer ergonomics (co-location) but provides no new capability. Build if teams request it post-launch. |
| `spec_kit` (spec-kit document parser) | "Spec-kit" is Foundry vocabulary. No external audience for the document format yet. `Foundry.SpecKit` uses `MDEx` + `NimbleOptions` — ~150 lines of internal glue. Extract when a second tool wants to read the same ADR/runbook format. |
| `igniter_typed` / `igniter_ops` (typed Igniter protocol) | The describe/validate/run protocol lives in `Foundry.Operations.*`. Extract if a second tool needs the same protocol. Currently no such tool exists. |
| `ash_diff` (change classifier) | The ADR-005 classification rules are tightly coupled to the manifest sensitive-resources list and Foundry's four change classes. The underlying AST analysis uses `Sourceror` directly — the thin wrapper does not justify its own package. Lives in `Foundry.Diff`. |
| `Foundry.Proposals` (proposal state machine) | Coupled to git-backed storage (ADR-015) and blob-hash stale detection (ADR-009). Separating the state machine from the storage would require an abstraction whose API is unknown. Extract when a second use case appears. |

---

## Telemetry stance (recorded here for completeness)

Ash and Reactor already emit telemetry for all actions and steps. Foundry adds three
custom spans via `:telemetry.span/3`, no macros, no mandatory behaviour:

| Event name | Fields | Purpose |
|---|---|---|
| `[:foundry, :llm, :call]` | model, task_type, prompt_tokens, latency_ms, error | LLM API call observability |
| `[:foundry, :context, :subprocess]` | module, cached, latency_ms | `mix foundry.context` subprocess timing |
| `[:foundry, :proposal, :transition]` | proposal_id, from_state, to_state, change_class, approver_count | Proposal state machine audit |

Event name constants live in `Foundry.Telemetry`. This module contains only constants —
no macros, no `use` behaviour. Every instrumented call site is findable by grepping for
`Foundry.Telemetry`.

`reactor_agent_step` defines its own telemetry event names following the
`[app_name, domain_name, reactor_name, step_name]` convention (INV-017) — it does not
depend on `Foundry.Telemetry` (which would create a circular dependency).

---

## Consequences

- `spark_meta`, `spark_lint`, `reactor_human_gate`, `reactor_agent_step` appear in
  Foundry's `mix.exs` as regular Hex dependencies
- `Foundry.LintRules.*` contains INV-011..017 rule modules; they implement `SparkLint.Rule`
  and are registered in the Foundry application config
- External teams can ship their own `SparkLint.Rule` modules without depending on Foundry
- The `ash_governed` decision is explicitly deferred, not forgotten — if teams request
  co-located sensitive resource annotations, build it then
- This ADR must be written in full (replacing this stub) before the first package ships to Hex,
  so the Hex package README can reference it

---

## What to fill in when writing the full ADR

- Final Hex package names and initial version constraints
- `SparkMeta.Extension` behaviour specification
- `SparkLint.Rule` behaviour specification and violation struct fields
- `reactor_human_gate` install mechanics (`mix reactor_human_gate.install` scope)
- `reactor_agent_step` DSL surface (confirm matches INV-014..017 declarations)
- Link to published Hex packages

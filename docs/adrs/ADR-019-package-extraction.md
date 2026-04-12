# ADR-019: Package Extraction — Reusable Primitives vs Foundry-Internal Modules

**Status:** Stub — amended 2026-04: reactor_agent_step and reactor_human_gate decisions reversed; ash_ai supersedes both
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

| Package | Rationale | Status |
|---|---|---|
| `spark_meta` | Any Spark-based project wanting structured JSON/struct output of DSL state benefits from this. The generic walker requires no Foundry config. `SparkMeta.Extension` opt-in hook lets extension authors (e.g. AshPyro) provide richer output without modifying the core. Note: relationship and auth strategy extraction now delegated to `ash_diagram` (ADR-021) — `spark_meta` scope narrows to Foundry-specific governance metadata (sensitivity class, compliance IDs, runbook refs). | Active |
| `spark_lint` | The rule runner protocol (behaviour + violation struct + mix task) is ~200 lines and completely domain-agnostic. Shipping it separately lets external teams publish their own rule packages. Foundry's actual rules ship in `Foundry.LintRules.*` (internal). | Active |
| ~~`reactor_human_gate`~~ | **CANCELLED.** `ash_ai` v0.5 `AshAi.ToolLoop` provides human-in-the-loop capability natively as part of the tool loop. The `on_tool_start`/`on_tool_end` callbacks and `AshAi.ToolLoop.run/2` HITL pattern subsumes the use case. A separate extraction is no longer justified — there is no audience that needs `reactor_human_gate` independently of `ash_ai`. | Cancelled |
| ~~`reactor_agent_step`~~ | **CANCELLED.** `ash_ai` v0.5 `run prompt(model, tools: [...])` inside a Reactor step is the canonical agent step declaration. The `agent_type`, `model`, `confidence_threshold`, `on_low_confidence`, `tools`, `telemetry_prefix` DSL surface is provided by `ash_ai`'s own DSL. Extracting a parallel package would duplicate this with no benefit. INV-014..017 lint rules now check for `ash_ai` prompt action configuration rather than a custom `reactor_agent_step` DSL. | Cancelled |

### Rejected — stays internal

| Candidate | Why rejected | Notes |
|---|---|---|
| `ash_governed` (DSL annotation for sensitive resources) | Not needed for v1. `manifest.sensitive_resources` list is the declaration mechanism. A DSL annotation would improve developer ergonomics (co-location) but provides no new capability. Build if teams request it post-launch. | Unchanged |
| `spec_kit` (spec-kit document parser) | "Spec-kit" is Foundry vocabulary. No external audience for the document format yet. `Foundry.SpecKit` uses `MDEx` + `NimbleOptions` — ~150 lines of internal glue. Extract when a second tool wants to read the same ADR/runbook format. | Unchanged |
| `igniter_typed` / `igniter_ops` (typed Igniter protocol) | The describe/validate/run protocol lives in `Foundry.Operations.*`. Extract if a second tool needs the same protocol. Currently no such tool exists. | Unchanged |
| `ash_diff` (change classifier) | The ADR-005 classification rules are tightly coupled to the manifest sensitive-resources list and Foundry's four change classes. The underlying AST analysis uses `Sourceror` directly — the thin wrapper does not justify its own package. Lives in `Foundry.Diff`. | Unchanged |
| `Foundry.Proposals` (proposal state machine) | Coupled to git-backed storage (ADR-015) and blob-hash stale detection (ADR-009). Separating the state machine from the storage would require an abstraction whose API is unknown. Extract when a second use case appears. | Unchanged |

### Consumed (external packages Foundry depends on, not extracted from Foundry)

| Package | Role in Foundry | Why not extracted |
|---|---|---|
| `ash_diagram` | Data extraction for ERD, C4, policy flowcharts in `mix foundry.project.context`. Foundry implements `AshDiagram.Data.Extension` to annotate diagrams with governance metadata. | External package (team-alembic). Foundry consumes it. |
| `req_llm` | LLM HTTP client used internally by `ash_ai`. Foundry configures a dedicated Finch pool. | External package (agentjido). Foundry consumes it. |
| `ash_ai` | MCP server, tool declarations, prompt actions. | External package (ash-project). Foundry consumes it. |

---

## Telemetry stance (recorded here for completeness)

Ash and Reactor already emit telemetry for all actions and steps. Foundry adds three
custom spans via `:telemetry.span/3`, no macros, no mandatory behaviour:

| Event name | Fields | Purpose |
|---|---|---|
| `[:foundry, :llm, :call]` | model, task_type, prompt_tokens, latency_ms, error | LLM API call observability |
| `[:foundry, :context, :subprocess]` | module, cached, latency_ms | `mix foundry.context` subprocess timing |
| `[:foundry, :proposal, :transition]` | proposal_id, from_state, to_state, change_class, approver_count | Proposal state machine audit |

These spans follow OpenInference conventions (compatible with AgentObs / OpenTelemetry
collector backends) — field names are chosen to match the OpenInference span specification
for LLM calls. This ensures compatibility with any OTel-capable observability backend
without custom exporters. `[:req_llm, :token_usage]` is emitted by ReqLLM on every
LLM call with token counts and calculated costs — Foundry's `[:foundry, :llm, :call]`
span adds `task_type` and `proposal_id` context on top.

`reactor_agent_step` defines its own telemetry event names following the
`[app_name, domain_name, reactor_name, step_name]` convention (INV-017). With
`reactor_agent_step` cancelled, this convention now applies to `ash_ai` prompt action
steps declared in target platform Reactors. The `telemetry_prefix` option on
`run prompt(model, telemetry_prefix: [...])` controls this.

---

## Consequences

- `spark_meta`, `spark_lint`, `ash_ai`, `ash_diagram`, `req_llm` appear in
  Foundry's `mix.exs` as regular Hex dependencies
- `Foundry.LintRules.*` contains INV-011..017 rule modules; they implement `SparkLint.Rule`
  and are registered in the Foundry application config
- External teams can ship their own `SparkLint.Rule` modules without depending on Foundry
- The `ash_governed` decision remains explicitly deferred — if teams request
  co-located sensitive resource annotations, build it then
- `reactor_human_gate` and `reactor_agent_step` are removed from all dependency lists.
  Target platforms use `ash_ai` directly. INV-014..017 lint rules are updated to check
  `ash_ai` prompt action configuration rather than `reactor_agent_step` DSL.
- This ADR must be written in full (replacing this stub) before `spark_meta` or
  `spark_lint` ship to Hex, so the README can reference it.

---

## What to fill in when writing the full ADR

- Final Hex package names and initial version constraints
- `SparkMeta.Extension` behaviour specification
- `SparkLint.Rule` behaviour specification and violation struct fields
- `reactor_human_gate` install mechanics (`mix reactor_human_gate.install` scope)
- `reactor_agent_step` DSL surface (confirm matches INV-014..017 declarations)
- Link to published Hex packages

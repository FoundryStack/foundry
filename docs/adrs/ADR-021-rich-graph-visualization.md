# ADR-021: Rich Graph Visualization — Schema Extensions and Data Derivation

**Status:** Implemented — amended 2026-04 (ash_diagram delegation, ScenarioEntry, API route nodes)
**Date:** 2026-03-25
**Extends:** ADR-016 (visualization paradigm), ADR-020 (data source), ADR-012 (UX spec)

## Context

The Foundry Studio System Map currently shows nodes but has sparse edges, no structural sub-graphs, and limited data extraction. The iGaming reference project has rich domain structure (14 resources, 6 state machines, 3 reactors with steps, 8 rules, compliance links) that is not visually represented.

This ADR defines schema extensions to NodeEntry, EdgeEntry, and SparkMeta to capture and derive rich graph structures including:
- All resource relationships (belongs_to, has_many, has_one, many_to_many)
- Reactor step sub-graphs with step kinds and dependencies
- State machine sub-graphs with initial/terminal states
- Authentication flows (User → Token)
- Rule guards and policy applications
- External system integrations (databases, queues, payment providers)

## Decision

Extend the data layer with the following. **Key change from original spec:** relationship
and auth strategy extraction is now **delegated to `ash_diagram`** rather than implemented
in Foundry's own pipeline. Foundry implements `AshDiagram.Data.Extension` to receive the
already-extracted diagram structs and annotate them with governance metadata. The
`put_relationships/1` and `put_auth_strategies/1` pipeline stages listed below are removed
from Foundry's own `spark_meta` walker — they are replaced by the `ash_diagram` extension hook.

### 1. NodeEntry Schema Extensions

All additions are non-breaking (nil/empty defaults).

**New fields:**
- `relationships`: List of RelationshipEntry structs (replaces fragile attribute-embedded relationship data)
- `auth_strategies`: List of AuthStrategyEntry structs for AshAuthentication strategies
- `provider_behaviour` / `provider_name`: Provider adapter metadata
- `rule_compliance_links`: Links from rules to compliance requirements

**Extended StepEntry** (in steps list):
- `step_index`: 0-based position
- `wait_for`: Dependency step names
- `has_compensation`: Whether step has compensation
- `target_resource`: FQN of resource this step acts on
- `target_action`: Action name called
- `step_kind`: :read, :write, :run, :map, :compensation, :custom

**Extended state_machine map**:
- `initial_states`: From initial_states/1 DSL
- `terminal_states`: Computed: states with no outgoing transitions
- `default_initial_state`: Default initial state

### 2. EdgeEntry Schema Extensions

**New relation types:**
- `guards`: Rule guards a step or resource policy
- `sequence`: Step-to-step ordering within Reactor/Transfer
- `compensation`: Compensation path in saga
- `configures`: Blueprint configures a Reactor
- `authenticates`: AshAuthentication User → Token
- `persists_to`: Resource → external:postgres
- `queues_via`: Job/Reactor → external:oban_queue
- `calls_provider`: Transfer step → Provider → external system

**New metadata fields:**
- `step_name`: Step name for sequence edges
- `step_index`: Step index for ordering
- `action_name`: Action name for operation edges
- `compliance_ids`: Compliance tags on edge

### 3. SparkMeta Extraction — Revised Pipeline

The pipeline now delegates to `ash_diagram` for relationship and auth data:

- ~~**`put_relationships/1`**~~: **REMOVED** — delegated to `AshDiagram.Data.Extension`
- ~~**`put_auth_strategies/1`**~~: **REMOVED** — delegated to `AshDiagram.Data.Extension`
- **`put_reactor_steps/1`** (enhanced): Populate all StepEntry fields. For `ash_ai` prompt action steps, also extract `model`, `confidence_threshold`, `on_low_confidence`, `telemetry_prefix` from the `run prompt(...)` options.
- **`put_state_machine/1`** (enhanced): Extract initial/default/terminal states as before.
- **`put_oban_triggers/1`** (new): Extract `AshOban` trigger and scheduled action declarations. Each trigger becomes a `ScenarioEntry` — see below.
- **`put_json_api_routes/1`** (new): Extract `AshJsonApi` route declarations (`base`, `verb`, `action`). Each POST/PATCH route on a resource becomes an external entry point node in the Scenario perspective.
- **`put_graphql_mutations/1`** (new): Extract `AshGraphql` mutation declarations. Each mutation becomes an API scenario node.

**`AshDiagram.Data.Extension` integration:**
Foundry registers `Foundry.AshDiagramExtension` as an `AshDiagram.Data.Extension`.
This receives the already-derived `AshDiagram.ERD` and `AshDiagram.C4` diagram structs
and annotates their elements with Foundry governance metadata:

```elixir
defmodule Foundry.AshDiagramExtension do
  @behaviour AshDiagram.Data.Extension
  use Spark.Dsl.Extension

  @impl AshDiagram.Data.Extension
  def supports?(AshDiagram.Data.EntityRelationship), do: true
  def supports?(AshDiagram.Data.Architecture), do: true
  def supports?(_), do: false

  @impl AshDiagram.Data.Extension
  def extend_diagram(_type, diagram) do
    manifest = Foundry.Manifest.load!()
    diagram
    |> annotate_sensitive_nodes(manifest.sensitive_resources)
    |> add_compliance_edges(manifest)
    |> add_runbook_annotations(manifest)
  end
end
```

The extracted relationship and auth strategy data flows back into NodeEntry via the
diagram struct, not via a separate `spark_meta` pipeline stage.

### 4. GraphBuilder Edge Derivation

**Data-driven derivation** (replaces hardcoded rules):

- **Reactor edges**: Use `step.step_kind` + `step.target_resource` instead of name heuristics
- **Resource edges**: Use `relationships` list instead of attribute scanning
- **Auth edges**: User resource with `auth_strategies` → token resources
- **External edges**: From `persists_to`, `queues_via`, `calls_provider` patterns

### 5. Frontend Compound Node Rendering

**Not yet implemented** (Phase D):
- Reactor step sub-graphs with lazy expand/collapse
- FSM transition edges with initial/terminal state styling
- External node styling (dashed border, lower opacity)

---

## ScenarioEntry — New Struct

Scenario origins (triggers, API routes, events) are first-class nodes in the Scenario
perspective (ADR-016). Each is represented as a `ScenarioEntry` stored in NodeEntry:

```elixir
defstruct [
  :trigger_type,      # :cron | :condition | :json_api_route | :graphql_mutation | :auth_event
  :schedule,          # cron string, e.g. "0 0 * * *"
  :condition_expr,    # AshOban `where` expression as string, e.g. "status == :pending"
  :route_method,      # :get | :post | :patch | :delete (JSON:API routes)
  :route_path,        # e.g. "/wallets/:id/withdraw"
  :mutation_name,     # GraphQL mutation name
  :initiates_module,  # FQN of the first Reactor/Transfer this scenario triggers
  :description        # Human-readable description derived from action description
]
```

NodeEntry gains a `scenario_origins: [ScenarioEntry]` field (empty list default —
non-breaking). The Scenario perspective filter selects all nodes with non-empty
`scenario_origins` and places them at the canvas periphery.

**Data sources:**
- `AshOban.Info.oban_triggers(resource)` → `:cron` and `:condition` entries
- `AshOban.Info.oban_scheduled_actions(resource)` → additional `:cron` entries
- `AshJsonApi.Resource.Info.routes(resource)` → `:json_api_route` entries for POST/PATCH
- `AshGraphql.Resource.Info.mutations(resource)` → `:graphql_mutation` entries
- `AshAuthentication` strategy declarations → `:auth_event` entries (login, magic link, OAuth callback)

---

## AshAI Agent Step Fields in StepEntry

`ash_ai` v0.5 prompt action steps are identified by `step_kind: :agent` in StepEntry.
Additional fields for agent steps:

| Field | Source | Notes |
|---|---|---|
| `ai_model` | `run prompt(model, ...)` first arg | Model identifier string, e.g. `"anthropic:claude-sonnet-4-6"` |
| `confidence_threshold` | `run prompt(model, confidence_threshold: 0.7)` | INV-014 enforcement |
| `on_low_confidence` | `run prompt(model, on_low_confidence: :escalate_human)` | INV-015 enforcement |
| `ai_tools` | `run prompt(model, tools: [...])` | List of tool name atoms; INV-016 enforcement |
| `ai_telemetry_prefix` | `run prompt(model, telemetry_prefix: [...])` | INV-017 enforcement |

Lint rules INV-014..017 are updated to check these fields on `step_kind: :agent` entries
rather than looking for a custom `reactor_agent_step` DSL.

---

## Consequences

### Positive

- **Data-driven over heuristic**: Step derivation now uses DSL metadata, not fragile pattern matching
- **Richer relationships**: Bi-directional resource relationships (belongs_to, has_many, many_to_many)
- **Auth flows visible**: AshAuthentication strategies and token resources connected
- **Extensible metadata**: New edge fields (step_name, action_name, compliance_ids) enable future features
- **Supports sagas**: Compensation edges enable visualization of saga patterns

### Negative

- **Schema churn**: NodeEntry/EdgeEntry have more fields (mitigated by nil/empty defaults)
- **Phase D blocking**: Frontend changes needed for full benefit (step sub-graphs, FSM transitions)

## Alternatives Considered

1. **Embed step data as JSON**: Would avoid struct extensions but complicate frontend extraction
2. **Synthetic external nodes only**: Missed opportunity to declare external systems as first-class Ash resources
3. **Hardcode rule edges**: Avoid relationship inversion; chose data-driven for maintainability

## Implementation Notes

- All JSON serialization uses `@derive Jason.Encoder` (no custom encoders)
- Terminal state computation: states not appearing as `from` in any transition
- Relationship type `:many_to_many` generates edges in both directions
- Auth strategy extraction uses AshAuthentication Spark entities API
- Source file heuristic for custom steps provides graceful fallback when DSL data unavailable

## Verification

1. ✅ Compile and test pass
2. ⏳ Run `mix foundry.project.context` on reference_projects/igaming — verify Wallet → LedgerEntry relationship edges (via ash_diagram extension, not spark_meta)
3. ⏳ Verify Scenario perspective — cron/AshOban trigger nodes at canvas periphery
4. ⏳ Verify POST /wallets/:id/withdraw appears as a JSON:API scenario origin node
5. ⏳ Expand reactor step sub-graph (Phase D frontend) — verify agent step shows model+tools
6. ⏳ Verify FSM transitions rendered (Phase D frontend)
7. ⏳ Policy flowchart tab renders in detail drawer for Wallet resource

## References

- ADR-016: Node/edge taxonomy definition
- ADR-020: NodeEntry schema baseline
- ADR-012: UX rendering budget (≤3s per view)
- Ash.Resource.Relationship docs
- AshAuthentication strategy extraction API
- Reactor step DSL reference

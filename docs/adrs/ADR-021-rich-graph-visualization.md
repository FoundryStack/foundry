# ADR-021: Rich Graph Visualization — Schema Extensions and Data Derivation

**Status:** Implemented
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

Extend the data layer with:

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

### 3. SparkMeta Extraction Enhancements

**New pipeline stages:**

- **`put_relationships/1`**: Extract from Ash.Resource.Info.relationships
- **`put_auth_strategies/1`**: Extract from AshAuthentication strategies
- **Enhanced `put_reactor_steps/1`**: Populate all new StepEntry fields using DSL data + source heuristic fallback
- **Enhanced `put_state_machine/1`**: Extract initial/default/terminal states
- **Enhanced `put_oban_performs/1`**: Fallback pattern scan for @performs attribute

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
2. ⏳ Run `mix foundry.project.context` on reference_projects/igaming
3. ⏳ Load Studio System Map — verify Wallet → LedgerEntry relationship edges
4. ⏳ Expand reactor step sub-graph (Phase D frontend)
5. ⏳ Verify FSM transitions rendered (Phase D frontend)
6. ⏳ Verify external:postgres node at canvas periphery (Phase D frontend)

## References

- ADR-016: Node/edge taxonomy definition
- ADR-020: NodeEntry schema baseline
- ADR-012: UX rendering budget (≤3s per view)
- Ash.Resource.Relationship docs
- AshAuthentication strategy extraction API
- Reactor step DSL reference

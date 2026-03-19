# ADR-008: Visualization Paradigm — Read-Only Panels, Activity Feed Is the Only Change Interface

**Status:** Superseded
**Date:** 2026-03
**Deciders:** Platform team
**Superseded by:** ADR-016 (four C4 levels, 11 node types, agent visualization) and ADR-012 (full UX spec)

---

## Decision

All visualization panels are strictly read-only. All changes flow through the copilot engine
via the Activity Feed — enforced by architecture; no write paths exist in the visualization
layer. Five-panel layout, full interaction spec, and storage model: ADR-012 and ADR-016.

## Why Drag-and-Drop Was Rejected

Spatial editing fails for complex domain models: finding the right node in 50+ graphs
requires more effort than typing; spatial precision errors produce wrong connections with
no error signal; metadata like compliance links and rule applications have no natural
spatial representation; it implies the map is the model when the Ash code is the model.

Natural language intent through the Activity Feed is faster and auditable for every case
this tool targets.

## Consequences

- No write paths in System Map, Compliance Matrix, Operations Board, or Test Coverage Map
- `Cmd+K` palette is navigation-only — does not expose scaffold operations (ADR-012)
- Node detail drawer opens left to avoid spatial collision with Activity Feed (right) and review panel (bottom) — see ADR-012
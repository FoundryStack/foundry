# ADR-008: Visualization Paradigm — Read-Only Panels, Activity Feed Is the Only Change Interface

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Decision

The system map and all visualization panels are **strictly read-only**. All changes flow
through the copilot engine via the Activity Feed. This is enforced by architecture —
there are no write paths in the visualization layer.

The five panels and their roles:

| Panel | Purpose |
|---|---|
| System Map | D3 graph — nodes are Ash resources, edges are relationships, clustered by domain. Click a node → left-side detail drawer with intent shortcuts. |
| Compliance Matrix | RG-* requirements × implementation status. Click a gap → pre-populates Activity Feed. |
| Operations Board | Runbook status, adapter contract results, Reactor failure log. |
| Test Coverage Map | Domain coverage (not line coverage) by type. Click a gap → pre-populates Activity Feed. |
| Activity Feed | Persistent right sidebar. Event stream + chat input. The only change interface. |

Full interaction spec: ADR-012. Storage model: ADR-015.

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
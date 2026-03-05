# ADR-008: Visualization Paradigm — Read-Only Map, Copilot Is the Only Change Interface

**Status:** Accepted  
**Date:** 2026-03  
**Deciders:** Platform team

---

## Context

A system visualization with 50+ interconnected resources could be made interactive in two ways:
1. Drag-and-drop spatial editing (like Miro, Figma, workflow builders)
2. Read-only visualization that feeds intent to the copilot

The first approach was initially considered and rejected.

## Decision

**The system map and all visualization panels are strictly read-only. Changes happen only through the copilot.**

The one interactive element in visualizations: **click-to-select**. Clicking a node opens its
detail panel and pre-populates the copilot context with that module. This is navigation, not editing.

Visualizations serve three purposes:
1. Understanding the current state of the system
2. Navigating to a resource to work with
3. Identifying gaps (compliance gaps, test coverage gaps, runbook staleness)

## Why Drag-and-Drop Was Rejected

Spatial manipulation is appropriate for a small, fixed set of node types (Zapier: triggers → actions).
It fails for complex domain models because:

- Finding the right node in a 50+ node graph to drag from requires more cognitive effort than typing
- Spatial precision errors create wrong connections with no obvious error signal
- Complex metadata (compliance links, rule applications) has no natural spatial representation
- It implies the visualization IS the model, when the Ash code IS the model

"Drag an RG-* ID onto a module to link them" is slower and more error-prone than:
```
User: "Link requirement RG-UK-001 to StakeLimitRule"
Copilot: [shows diff of compliance: ["RG-UK-001"] added to StakeLimitRule] → approve
```

## The Five Visualization Panels

**1. System Map** — Interactive D3 graph. Nodes are Ash resources, edges are relationships.
Clusters are domains. Click a node → left-side detail drawer (moduledoc, attributes, actions,
linked ADRs, test status, contextual intent shortcuts).

**2. Compliance Matrix** — Rows: RG-* requirements. Columns: implementation module, test, last pass, status.
Color-coded. Click a gap → intent shortcut pre-populates the Activity Feed.

**3. Operations Board** — Runbook status, adapter verification schedule, last backup restore result,
failed Reactor log with runbook links, alert configuration preview.

**4. Test Coverage Map** — Domain coverage (not line coverage). By domain, by type (Transfers, Rules, etc.).
Click a gap → intent shortcut pre-populates the Activity Feed.

**5. Activity Feed** — The persistent right sidebar. A chronological event stream showing all
system activity (proposals, approvals, CI results, compliance events, copilot responses) with
a chat input at the bottom. All changes flow through the copilot engine via this feed.
The other four panels feed context into it via intent shortcuts; this is the only way anything
changes. Previously called "Copilot Panel" — renamed to reflect that it is primarily an event
stream with a chat input, not primarily a chat interface.

Layout and interaction details: ADR-012.

## Consequences

- No editing capabilities are built into the System Map, Compliance Matrix, Operations Board, or Test Coverage Map
- The Activity Feed is the bottleneck for all changes — this is intentional
- The visualization stack (D3 or equivalent) is used for rendering only
- All user intent for change is expressed as natural language in the Activity Feed input, or via contextual intent shortcuts in node detail drawers — both route to the same copilot engine
- The command palette (`Cmd+K`) is for navigation only — it does not expose scaffold operations
- The node detail drawer opens from the left side of the map to avoid spatial collision with the Activity Feed sidebar (right) and review panel (bottom) — see ADR-012
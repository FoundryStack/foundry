# ADR-016: Visualization Paradigm v2

**Status:** Accepted — §Data Source and §Diagram JSON Contract amended by ADR-020
**Date:** 2026-03
**Deciders:** Platform team
**Supersedes:** ADR-008 (retained for historical record)

---

## Context

ADR-008 established the read-only system map paradigm and the Activity Feed as the only
change interface. That decision stands. This ADR refines and finalizes the visual model:
the four C4 levels, the complete node and edge taxonomy, the authorization layer, and the
agent node type added in ADR-017. ADR-008 is not wrong — it is incomplete.

The design was arrived at through explicit rejection of two failure modes:
1. Mermaid-only output — loses all compliance signal; diagrams become documentation, not governance instruments
2. Over-engineered abstraction — renderer registries, semantic schema contracts, adapter layers. These are correct for a multi-stack product. Foundry is single-stack. The abstraction cost is not justified.

The right model is: Cytoscape.js canvas consuming the `mix foundry.project.context`
NodeEntry JSON directly, with Foundry-specific styling applied via a direct `switch`
on node type. No framework. No registry. A well-organized frontend module.

---

## Decision

### Four C4 Levels — All Present, Different Surfaces

**Level 1 — System Context (outermost zoom)**
Shows the system boundary, user personas, and external systems. Rendered as the fully
zoomed-out state of the main canvas. User personas and non-Elixir external system
descriptions are hand-authored in the spec-kit manifest YAML (`foundry.exs` or
`docs/system-context.yml`). Provider nodes (`⬚`) and API entry points are auto-derived.
This level is not a separate diagram — it is what the canvas shows at maximum zoom-out.

**Level 2 — Containers**
For monolithic Phoenix applications (Foundry's primary target), Level 2 is incorporated
into Level 1. Relevant external containers (Postgres, Redis, Oban queue, external providers)
appear as Provider nodes. Multi-service architectures are not a v1 target.

**Level 3 — Components (primary operating level)**
Domains as Cytoscape compound nodes. Resources, Transfers, Reactors, Rules, LiveViews as
node-level components inside domain clusters. This is the ambient canvas state at normal
zoom. All governance signal — compliance posture, test coverage, sensitivity — is expressed
here. This level drives all copilot navigation.

**Level 4 — Code detail (detail drawer)**
Full attribute list with types and sensitivity flags, action signatures with accept/return
types, policy logic with actor/condition/outcome, FSM transition conditions, step
input/output types. Level 4 is not a separate diagram; it is the content rendered in the
detail drawer when any Level 3 node is clicked. The full NodeEntry (already in memory
from the graph load) is the data source — no additional server fetch needed for
projects ≤200 modules. Beyond that threshold, the drawer fetches the single NodeEntry
on demand via `mix foundry.project.context <Module>`.

### Node Taxonomy — Final, 11 Types

| Type | Icon | Source | Represents |
|---|---|---|---|
| Resource | ⬡ | Ash.Resource | Persistent entity, data at rest |
| Transfer | ⇄ | Ash.Reactor + Transfer DSL | Multi-step saga with compensation |
| Reactor | ◈ | Ash.Reactor (standalone) | Async orchestration / background |
| Rule | ◆ | Custom Rule module | Guard / policy / constraint |
| Job | ⚡ | Oban.Worker | Background job, queue worker |
| LiveView | ▣ | Phoenix.LiveView | User-facing page or back-office UI |
| LiveResource | ⊞ | AshPyro / AshAdmin | Auto-generated back-office CRUD UI |
| Blueprint | ◇ | Custom config resource | Configuration template / operational params |
| Provider | ⬚ | External adapter module | External system boundary |
| Trigger | ▶ | api_routes / webhook / scheduler | Entry point — how flow starts |
| Terminal | ⟐ | Reactor return / error path | How flow ends (success / error / compensated) |

Agent steps are NOT a top-level node type on the canvas. They are rendered as inline step
nodes (⊕ icon, `agent` kind) inside the swimlane of the containing Transfer or Reactor.
See ADR-017 for the agent step visual specification.

No additional node types will be added without an ADR. The 11 above are sufficient for
the complete surface of a Foundry-built Elixir/Ash/Phoenix system.

### Edge Taxonomy — Final, 8 Types

| Edge | Meaning | When used |
|---|---|---|
| `──────▶` | Triggers / sequence flow | Trigger→Transfer, step→step |
| `- - -▶` | Async / message | Step spawns Job, crosses boundary |
| `·····▶` | Guards / constrains | Rule applied to step or resource |
| `══════▶` | Compensation / undo | Undo path in saga |
| `◇─────` | Reads (non-mutating) | Step reads Resource |
| `◆─────` | Writes (mutating) | Step creates/updates/deletes Resource |
| `──────○` | Renders / serves | LiveView serves Resource data |
| `──────▷` | Configured by | Reactor reads Blueprint at runtime |

### Status Indicators on Nodes

Every node carries a compact status badge row. The exact indicators:

| Indicator | Meaning |
|---|---|
| ◉ | Compliance-covered — all declared requirements have linked tests |
| ○ | Compliance gap — one or more requirements untested |
| ⬡ | Policy present — node has declared policies or rules |
| PSE | paper_trail + soft_delete + ecto — rendered only on `sensitive: true` nodes; shows which of the three are present (e.g. `PS·` means paper_trail and soft_delete present, ecto data layer absent or non-postgres) |
| ~ | Has runbook linked |
| 📖 | Has ADR linked |
| ↻ | Has pending migration |
| ⚠ | Active lint violation |

### Authorization Layer — Detail View Only

The authorization matrix is not rendered on the ambient canvas. It appears as a dedicated
tab in the detail drawer for any Resource node that has declared policies.

The matrix rows are actor roles; columns are actions; cells show authorized/forbidden
with conditions. Data is derived from `Ash.Policy.Authorizer` introspection, which exposes
the full policy structure including `action`, `actor`, `policies`, `resource`, `domain`,
and `scenarios`.

The drawer tab also shows policy test coverage: which actor/action combinations have
corresponding test cases in the test suite, and which are untested.

An "Authorization Trace" scenario mode (accessible from the canvas toolbar) draws
authorization edges between the actor-identity Resource and the Resources it can access,
labeled with the permitted actions. This mode is not on by default — it is available on
demand for security audits. It is not ambient because a system with 10 resources and
4 actor roles produces 40+ potential edges, overwhelming the canvas.

### Canvas Modes

The canvas supports four modes, selectable from the toolbar:

| Mode | Description |
|---|---|
| Default | Standard domain/component view — ambient operating mode |
| Scenario trace | Highlights the execution path for a selected scenario — shows which nodes and edges activate for a given request |
| Authorization | Shows auth edges between actor-identity resources and the resources they can access |
| Config view | Highlights Blueprint nodes and their `configured-by` edges — shows what is adjustable without a code change |

Mode switching is entirely client-side. The JS module computes which nodes and edges
to highlight from the already-loaded graph data — no round-trip to the server.

---

### Proposal Preview Mode — `ProposalGraphDelta`

When a DRAFT or PENDING_REVIEW proposal is active, the canvas enters preview mode.
The preview is driven by a `graph_delta` field stored in the proposal JSON (ADR-014),
not by re-running `mix foundry.project.context` against the proposal branch. No subprocess
is required — the delta is derived from operation parameters at plan confirmation time
and is available immediately when the proposal enters DRAFT.

**Note on naming:** The `graph_delta` field also appears in `mix foundry.project.context`
output (see `project_context_schema.md`). That field tracks live session state against
the baseline at session start — it is a different concern. The proposal canvas overlay
reads from `proposal.graph_delta` (the proposal JSON), not from the project context output.
The two fields have the same shape but different producers and consumers.

**Struct definition** (`Foundry.Proposals.GraphDelta`):

```elixir
defstruct [
  :proposal_id,
  :base_diagram_hash,   # sha256 of project.context output at base_commit
  nodes_added: [],      # phantom nodes — new modules being created
  nodes_modified: [],   # existing nodes touched by the proposal
  nodes_removed: [],    # rare — modules being deleted
  edges_added: [],      # new relationships / calls introduced
  edges_removed: []     # rare
]
```

Each entry in `nodes_added` is a minimal NodeEntry subset with `"state": "phantom"` added:

```json
{
  "id": "MyApp.Finance.WithdrawalLimitRule",
  "type": "rule",
  "name": "WithdrawalLimitRule",
  "domain": "finance",
  "sensitive": false,
  "state": "phantom"
}
```

`nodes_modified` carries node ID and a list of changed field names. The canvas renders
the existing node with an amber ring and a dot indicator in the detail drawer.

**Canvas rendering rules:**

| Delta entry | Canvas rendering |
|---|---|
| `nodes_added` | Dashed border, 50% opacity, amber ring, label suffixed `[proposed]` |
| `nodes_modified` | Amber ring on existing node, dot indicator in detail drawer |
| `edges_added` | Dashed amber edge line |
| `nodes_removed` | Dimmed node, strikethrough label |
| `edges_removed` | Dimmed dashed edge |

**Lifecycle:**
- Populated at plan confirmation time (before the generation pass starts)
- Available on canvas from the moment the proposal enters DRAFT
- Reverted to committed state on REJECTED or STALE
- Solidifies into real nodes on COMMITTED via the inotify watcher triggering
  a `mix foundry.project.context` reload — phantom nodes become live nodes

**What this is not:** The `graph_delta` shows structural intent — which modules are
added or touched. It does not show implementation detail. Implementation detail is
in the diff panel. The two surfaces are complementary: canvas for spatial orientation,
diff panel for code review.

---

### Data Source — `mix foundry.project.context`

**Amended by ADR-020.** The canonical studio data source is `mix foundry.project.context`,
not `mix foundry.diagram.generate`. The command performs one pass over all compiled
modules and returns the full NodeEntry corpus, EdgeEntry list, and spec-kit index in a
single response. Output lives in ETS (Nebulex L1), not in a committed JSON file.

`mix foundry.diagram.generate` is retained as a backward-compat alias and is not
documented as canonical.

The JS canvas receives the full `mix foundry.project.context` output embedded in the
page at mount (as a `data-context` attribute or equivalent). For projects ≤200 modules,
this is the only data fetch on page load — no channel join, no additional XHR. The
full NodeEntry corpus is sufficient for all canvas rendering, all mode switching,
all search, and all drawer content at this scale.

**Schema contract:** The NodeEntry and EdgeEntry schemas are defined in
`docs/project_context_schema.md`. That document is authoritative. This ADR does not
duplicate the schema — do not add schema details here.

**Fields the canvas renderer reads from NodeEntry** (the visual subset — the rest
is used only by the drawer):

| Field | Used for |
|---|---|
| `id`, `type`, `domain`, `app` | Node identity, cluster grouping |
| `sensitive` | PSE badge, sensitive border style |
| `description` | Tooltip on hover |
| `compliance[]`, `test_coverage` | ◉/○ compliance indicator |
| `paper_trail`, `archival`, `data_layer` | PSE badge computation |
| `pending_migrations` | ↻ badge |
| `runbook` | ~ badge |
| `adrs[]` | 📖 badge |
| `rules[]` | ⬡ badge |
| `steps[]` with `kind` | Step expansion inside Transfer/Reactor swimlanes |
| `agent_steps[]` | ⊕ inline agent step nodes (ADR-017) |
| `state_machine.present` | State expansion inside Resource nodes |

EdgeEntry fields used: `from`, `to`, `relation`, `cross_app`, `cross_project`.

---

### Implementation Stack

- **Canvas**: Cytoscape.js. Not D3, not a custom engine. Cytoscape handles layout,
  compound nodes, zoom, click/hover events.
- **Node styling**: Direct `switch` on `node.type` in the frontend module. Not a registry.
  Not a behaviour. A switch statement with 11 cases.
- **JS architecture**: Two plain JS modules. `CytoscapeGraph` — a pure Cytoscape.js
  wrapper with no LiveView or Foundry knowledge. `FoundryGraph` — configures
  `CytoscapeGraph` with Foundry-specific render functions, edge styles, indicator logic,
  search predicate, and mode definitions. No Elixir struct layer mirrors these in Elixir.
- **Detail drawer data**: The full NodeEntry is already in memory from the initial graph
  load. The drawer renders directly from it — no additional fetch for projects ≤200 modules.
  Above that threshold: `mix foundry.project.context <Module>` fetched on node click.
- **Live reload**: inotify watcher → Phoenix PubSub → `push_event("graph:delta")` →
  `CytoscapeGraph.applyDelta()`. The canvas re-renders on any source file change within
  2 seconds (performance budget per ADR-012). Full reload is not needed — incremental
  delta is applied directly to the live Cytoscape instance.
- **Mode switching, search, hover**: Entirely client-side. No round-trip to the server.
  The JS module computes active nodes and edges from already-loaded data.
- **Server round-trips that ARE required**: (1) initial graph load at mount, embedded
  in page — not a round-trip; (2) proposal delta pushed by server on proposal state
  change; (3) intent shortcut triggers, which must populate the Activity Feed; (4) node
  click above the 200-module threshold.

---

## Consequences

- ADR-008's "read-only system map" and "Activity Feed is the only change interface"
  decisions are inherited unchanged. ADR-016 adds visual specification; it does not
  change the interaction model.
- The 11 node types and 8 edge types are the complete visual vocabulary. Adding types
  requires an ADR with justification for why the existing taxonomy is insufficient.
- Mermaid output is a secondary artifact produced from `mix foundry.project.context`
  output by `mix foundry.diagram.mermaid`. The Cytoscape canvas is the primary
  governance instrument.
- Authorization matrix is Level 4 (drawer), not Level 3 (canvas), by explicit decision.
  The canvas edge approach is available in "Authorization" mode for on-demand use.
- The NodeEntry schema is frozen at the end of Phase 2. Adding fields requires an ADR.
  Agent step fields (ADR-017) are added as a non-breaking extension — new fields inside
  the existing `steps` array item, ignored by renderers that do not handle `"kind": "agent"`.
- `mix foundry.diagram.generate` is a deprecated alias. All new code targets
  `mix foundry.project.context`. CI staleness check uses `mix foundry.project.context --check`.
- The drawer does not require a server fetch for projects ≤200 modules — the full
  NodeEntry corpus is loaded at mount. This eliminates the click latency concern at the
  scale Foundry targets in v1.

---

## What This Is Not

This ADR does not define the copilot interaction model (ADR-013), the proposal lifecycle
(ADR-014), or the Studio UX panels beyond the system map (ADR-012). It defines only the
visual representation of the target platform's domain model.

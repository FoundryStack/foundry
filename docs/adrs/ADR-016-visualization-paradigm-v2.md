# ADR-016: Visualization Paradigm v2

**Status:** Accepted — §Data Source amended by ADR-020; §Zoom/C4, §Compound Nodes, §Scenario Perspective, §Clarity Patterns amended 2026-04
**Amended:** 2026-04 by ADR-022 (step sub-graph side-effect pills, status indicator for undeclared side effects)
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
NodeEntry JSON directly, with Foundry-specific semantics centralized in one frontend
module and consumed by the renderer, overlays, and detail affordances. No framework.
No registry. A well-organized Foundry-specific frontend module set.

---

## Zoom ↔ C4 Level Mapping

Cytoscape's zoom level maps directly to C4 abstraction depth. This is the primary
mechanism for the "progressive detail" UX — no separate panels, no mode button, just zoom.

| Zoom threshold | C4 equivalent | What becomes visible |
|---|---|---|
| < 0.4× | Context | Domain compound node labels only — no resources shown |
| 0.4–0.8× | Container | Resources appear as children inside domain compounds; FSM state nodes visible |
| 0.8–1.5× | Component (default) | Reactor steps, Transfer rules, action nodes; all status badges visible |
| > 1.5× | Code | Individual conditions, attribute names with types, Elixir function signatures |

Implementation: `cy.on('zoom', fn)` computes the current threshold and toggles CSS
classes on node groups. All data is already in the Cytoscape instance — no server round-trip.
Higher zoom simply reveals detail that was rendered but hidden at coarser levels.

---

## Compound Node Rendering

Cytoscape's compound node API is used for two purposes:

**1. Domain groups** — Each Ash domain is a Cytoscape compound parent node. Domain color
belongs to this grouping layer only. The domain boundary is dashed, lightly tinted, and
more spacious than inner compounds so the top-level structure stays legible in large maps.
Children are rendered eagerly; the current implementation does not use interactive
expand/collapse for domain compounds.

**2. Semantic boundaries inside domains** — Resource, Reactor, Transfer, and FSM compounds
render as nested boundaries inside the domain group. Their border color is semantic:
resource, transfer, reactor, and FSM compounds each use a distinct kind color. Their
fills are subtle and translucent so the graph reads as layered structure rather than
solid grouped slabs.

Step, action, and state nodes are rendered as child nodes inside their parent compound
when the data exists in `NodeEntry.steps[]`, `NodeEntry.actions[]`, and
`NodeEntry.state_machine`.

**Step-level side-effect pills (ADR-022)**
Each expanded step node renders its `side_effects[]` as subordinate pill nodes attached
below the step box. Pill rendering rules:

- `declared: true` side effects render in the **teal ramp** (teal-100 fill, teal-600 stroke)
- `declared: false` side effects render in the **coral ramp** (coral-100 fill, coral-600 stroke)
  and also carry the `⚠` lint violation badge inline
- Pill label: `{type}:{name}` truncated to 24 chars (e.g. `oban_emit:FraudCheck`)
- Clicking a pill opens the `SideEffectEntry` detail in the right detail drawer, showing:
  type, declaration status, idempotency, epistemic marker, and — if `declared: false` —
  the INV violation text and a "Declare this side effect ↗" copilot action button
- External system connections: a dashed `async/message` edge (ADR-016 edge taxonomy:
   `- - -▶`) runs from undeclared `external_http` pill nodes to the relevant adapter node
  when one exists in the graph. This makes the ungoverned external boundary crossing
  visible at the topology level without manual navigation.

**Compensation path display:** Steps with `compensation` set render a `══════▶`
compensation edge to the named compensation step. Compensation steps are styled with
the gray ramp and a `↩` prefix on the label. This answers "what rolls back if this
fails?" directly on the expanded canvas without opening the detail drawer.

---

## Scenario Perspective

A dedicated canvas perspective (selectable from the toolbar alongside Default, Authorization,
Config) that re-layouts the graph as a flow view with scenario origin nodes at the periphery.

**Scenario origin node types** (subset of the Trigger taxonomy, surfaced at canvas periphery):

| Origin type | Data source | Example label |
|---|---|---|
| Cron job | `NodeEntry.oban_triggers[].schedule` | `"0 0 * * *" → DeleteExpiredPosts` |
| Condition trigger | `NodeEntry.oban_triggers[].where` | `status == :pending → ProcessVideo` |
| API route (JSON:API) | `NodeEntry.json_api_routes[]` | `POST /wallets/:id/withdraw` |
| GraphQL mutation | `NodeEntry.graphql_mutations[]` | `mutation depositFunds` |
| Authentication event | `NodeEntry.authentication_strategies[]` | `password login → session` |

Each origin node has directed edges to the first Reactor or Transfer it initiates, which
then chains into downstream resource nodes. This answers "what runs and when" — the
complement to the Default view's "what exists".

**Layout**: Origin nodes arranged around the canvas periphery using a force-directed
radial layout. Domain compounds are de-emphasized (lower opacity) in this mode — the
flow path is the primary visual.

This perspective requires `ScenarioEntry` data in NodeEntry — see ADR-021 amendments.

---

## Clarity Protocol Patterns (learned, not adopted)

The Clarity introspection framework (team-alembic/clarity) uses a protocol-based vertex
model that Foundry's NodeEntry design has learned from. The following patterns are adopted:

**`Clarity.Vertex` protocol → `Foundry.Graph.Vertex` protocol**
NodeEntry implements three required callbacks (`id/1`, `name/1`, `type_label/1`) plus
optional secondary protocols:
- `Foundry.Graph.Vertex.GovernanceProvider` — returns sensitivity class, change class, compliance IDs
- `Foundry.Graph.Vertex.SourceLocationProvider` — returns `{file, line}` for "go to source" navigation
- `Foundry.Graph.Vertex.ProposalProvider` — returns active proposal preview if one exists

**Incremental introspection (Clarity subscription pattern)**
`Foundry.Graph.Server` uses the same subscription model as Clarity:
- `:full` introspection on initial load
- `{:incremental, app, modules_diff}` on file save events (inotify watcher)
- Events emitted: `:work_started`, `{:work_progress, queue_info}`, `:work_completed`
- Only changed modules are re-introspected — response time target <500ms per file save

**`graph_delta` contract**
When introspection runs, the diff between previous and new graph is computed as
`{added_vertices, removed_vertices, changed_vertices, changed_edges}` and emitted as a
structured delta. The LiveView calls `cy.add()`, `cy.remove()`, `cy.style()` on the
existing canvas rather than replacing the full graph.

**`SourceLocationProvider`** — clicking any resource node navigates directly to its
source file and line. Sourceror extracts `__ENV__.line` from the Ash DSL `do` block
during introspection and stores it in NodeEntry as `source_location: {file, line}`.

---

## Policy Flowchart (ash_diagram integration)

The detail drawer for any Resource node includes a "Policies" tab alongside
"Compliance Links" and "Test Coverage". This tab renders the authorization policy
flowchart produced by `AshDiagram.Data.Policy.for_resource/1`.

The flowchart shows: policy conditions, bypass paths, action-level authorization
decisions, and which actor roles are permitted or forbidden. It is derived from
`Ash.Resource.Info.authorizers/1` — always current, never a separate diagram to maintain.

This closes the audit gap: an auditor can follow
`RG-UK-014 node → Wallet resource → Policies tab → authorization flowchart`
and verify that the authorization conditions match the regulatory requirement.
The demonstrable claim standard (ADR-022) gains a new demo path for this flow.

Foundry should add all possible DSL blocks including actions and manual code.

---

## Decision

### Four C4 Levels — All Present, Different Surfaces

**Level 1 — System Context (outermost zoom)**
Shows the system boundary, user personas, and external systems. Rendered as the fully
zoomed-out state of the main canvas. User personas and non-Elixir external system
descriptions are hand-authored in the spec-kit manifest YAML (`foundry.exs` or
`docs/system-context.yml`). Adapter nodes (`⬚`) and API entry points are auto-derived.
This level is not a separate diagram — it is what the canvas shows at maximum zoom-out.

**Level 2 — Containers**
For monolithic Phoenix applications (Foundry's primary target), Level 2 is incorporated
into Level 1. Relevant external containers (Postgres, Redis, Oban queue, external systems)
appear as adapter nodes. Multi-service architectures are not a v1 target.

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

### Node Taxonomy — 11 Types + Side-Effect Pills

| Type | Icon | Source | Represents |
|---|---|---|---|
| Resource | ⬡ | Ash.Resource | Persistent entity, data at rest |
| Transfer | ⇄ | Ash.Reactor + Transfer DSL | Multi-step saga with compensation |
| Reactor | ◈ | Ash.Reactor (standalone) | Async orchestration / background |
| Rule | ◆ | Custom Rule module | Guard / policy / constraint |
| Job | ⚡ | Oban.Worker | Background job, queue worker |
| LiveView | ▣ | Phoenix.LiveView | User-facing page or back-office UI |
| LiveResource | ⊞ | AshPyro / AshAdmin | Auto-generated back-office CRUD UI |
| Blueprint | ◇ | Legacy configurable logic module | Legacy configuration boundary (supported, deprecated) |
| Adapter | ⬚ | Integration adapter module | Internal integration-facing module that calls an external system |
| Trigger | ▶ | api_routes / webhook / scheduler | Entry point — how flow starts |
| Terminal | ⟐ | Reactor return / error path | How flow ends (success / error / compensated) |

Agent steps are NOT a top-level node type. They are rendered as inline step nodes (⊕
icon, `agent` kind) inside the containing Transfer or Reactor.

**Side-effect pills are not a 12th node type.** They are sub-elements rendered inside
expanded step compound nodes. They do not appear in the ambient canvas at zoom < 0.8×
(Component level). They are only visible in the expanded step sub-graph at Code level
zoom (> 1.5×) or when a step is explicitly expanded via click. This preserves the
ambient canvas readability — governance detail is progressive, not ambient noise.

No additional top-level node types will be added without an ADR. The 11 above are
sufficient for the complete surface of a Foundry-built Elixir/Ash/Phoenix system.

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

Top-level nodes and compound boundaries may render a compact status icon row. Child
step/action/state nodes do not inherit these governance indicators from their parent.

The current ambient indicators are:

| Indicator | Meaning |
|---|---|
| check | Coverage >= 80% |
| slashed circle | Compliance coverage gap — one or more declared compliance links lack linked E2E coverage |
| warning triangle | Sensitive / regulated node |
| stacked lines | Paper Trail enabled |
| archive box | Archival / soft delete enabled |
| refresh arrows | Pending migrations |
| gear ring | Oban queues present |
| clock | Schedule declared |
| back-arrow | Rate limited |
| diamond state icon | State machine present |
| book | Runbook linked |

Compliance gap is scoped intentionally: it appears only on nodes with declared
compliance links. Nodes without compliance links do not render a compliance warning.

### Authorization Layer — Detail View Only

The authorization matrix is not rendered on the ambient canvas. It appears as a dedicated
tab in the detail drawer for any Resource node that has declared policies.

The matrix rows are actor roles; columns are actions; cells show authorized/forbidden
with conditions. Data is derived from `Ash.Policy.Authorizer` introspection, which exposes
the full policy structure including `action`, `actor`, `policies`, `resource`, `domain`,
and `scenarios`.

The drawer tab also shows policy test coverage: which actor/action combinations have
corresponding test cases in the test suite, and which are untested.

**Policy flowchart tab** — The detail drawer also renders an `ash_diagram` policy
flowchart for any Resource node that has declared authorizers. See §Policy Flowchart above.
The tab is rendered lazily — `AshDiagram.Data.Policy.for_resource/1` is called on first
tab open, not at graph load time.

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
| `id`, `type`, `domain`, `app` | Node identity, domain grouping, compound parenting |
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

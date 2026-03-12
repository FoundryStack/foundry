# ADR-016: Visualization Paradigm v2

**Status:** Accepted  
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

The right model is: Cytoscape.js canvas consuming a simple JSON contract produced by
`mix foundry.diagram.generate --json`, with Foundry-specific styling applied via a direct
`switch` on node type. No framework. No registry. A well-organized frontend module.

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
detail drawer when any Level 3 node is clicked. `mix foundry.context <Module>` is the
data source.

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

### What the Diagram JSON Contract Contains

Produced by `mix foundry.diagram.generate --json`. Schema is frozen — breaking changes
require an ADR.

```json
{
  "generated_at": "ISO8601",
  "domains": [
    {
      "id": "finance",
      "name": "Finance",
      "health": { "coverage": 0.78, "gaps": 2, "sensitive_gaps": 1 }
    }
  ],
  "nodes": [
    {
      "id": "MyApp.Finance.WithdrawalTransfer",
      "type": "transfer",
      "name": "WithdrawalTransfer",
      "domain": "finance",
      "sensitive": true,
      "health": {
        "compliance_posture": "gap",
        "test_coverage": 0.88,
        "has_runbook": true,
        "pending_migration": false
      },
      "triggers": ["POST /api/withdraw"],
      "reads": ["MyApp.Identity.Player", "MyApp.Finance.Wallet"],
      "writes": ["MyApp.Finance.Wallet", "MyApp.Finance.LedgerEntry"],
      "guards": ["MyApp.Compliance.KycCheck"],
      "terminals": ["committed", "kyc_error", "compensated"],
      "steps": [
        {
          "id": "validate_inputs",
          "kind": "step",
          "guards": ["MyApp.Compliance.KycCheck"],
          "reads": [], "writes": [],
          "error_paths": [{"type": "halt", "id": "kyc_error"}]
        }
      ]
    }
  ],
  "edges": [
    {
      "from": "POST /api/withdraw",
      "to": "MyApp.Finance.WithdrawalTransfer",
      "type": "triggers"
    }
  ]
}
```

Agent steps appear in `steps` with `"kind": "agent"` and the agent-specific fields defined
in ADR-017. They are not top-level nodes and do not appear in `nodes`.

The `kind` field is new in this schema version. All existing step objects that predate
this field are treated as `"kind": "step"` by the renderer — the field defaults to `"step"`
when absent, making the addition non-breaking for existing consumers. Valid `kind` values
are: `"step"` (generic step), `"update"` (Ash resource update), `"create"` (Ash resource
create), `"read"` (Ash resource read), and `"agent"` (Foundry agent step). Renderers that
do not recognise a `kind` value must fall back to `"step"` rendering rather than erroring.

### Implementation Stack

- **Canvas**: Cytoscape.js. Not D3, not a custom engine. Cytoscape handles layout,
  compound nodes, zoom, click/hover events.
- **Node styling**: Direct `switch` on `node.type` in the frontend module. Not a registry.
  Not a behaviour. A switch statement with 11 cases.
- **Detail drawer data**: `mix foundry.context <Module>` output rendered directly.
  No transformation layer between the Mix task output and the drawer template.
- **Live reload**: inotify watcher → Phoenix PubSub → LiveView push. The canvas re-renders
  on any source file change within 2 seconds (performance budget per ADR-012).
- **Diagram JSON generation**: `mix foundry.diagram.generate --json` is idempotent and
  fast (target: <500ms for a 50-module project). It must be runnable in CI for INV-008.

---

## Consequences

- ADR-008's "read-only system map" and "Activity Feed is the only change interface"
  decisions are inherited unchanged. ADR-016 adds visual specification; it does not
  change the interaction model.
- The 11 node types and 8 edge types are the complete visual vocabulary. Adding types
  requires an ADR with justification for why the existing taxonomy is insufficient.
- Mermaid output is a secondary artifact from the same JSON contract, used for GitHub
  README documentation and PR descriptions. `mix foundry.diagram.mermaid` produces it.
  The Cytoscape canvas is the primary governance instrument.
- Authorization matrix is Level 4 (drawer), not Level 3 (canvas), by explicit decision.
  The canvas edge approach is available in "Authorization" mode for on-demand use.
- The diagram JSON schema is frozen at the end of Phase 2. Adding fields requires an ADR.
  Agent step fields (ADR-017) are added as a non-breaking extension — new fields inside
  the existing `steps` array item, ignored by renderers that do not handle `"kind": "agent"`.

---

## What This Is Not

This ADR does not define the copilot interaction model (ADR-013), the proposal lifecycle
(ADR-014), or the Studio UX panels beyond the system map (ADR-012). It defines only the
visual representation of the target platform's domain model.
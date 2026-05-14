# ADR-027: UI Surface Nodes — LiveView, SDUI, and Dev Server Preview

**Status:** Accepted
**Date:** 2026-05-07
**Deciders:** Platform team
**Extends:** ADR-016 (visualization paradigm v2), ADR-021 (rich graph visualization)

---

## Context

ADR-016 defines 11 top-level node types as the complete visual vocabulary for Foundry-built
Elixir/Ash/Phoenix systems. One of those types is `LiveView` (▣), defined as "User-facing
page or back-office UI." The existing taxonomy is correct — no new top-level type is
needed — but the `LiveView` type currently has no data extraction, no graph edges derived
from it, and no frontend rendering semantics beyond the icon.

The igaming reference project requires:
- Home page (game collections, A/B feature flags)
- Game page (loads game, calls bet flow)
- Login / deposit / withdrawal pages (Ash action forms)

These pages need to appear in the system map graph, visually linked to the Ash actions
they call and the feature flags that gate them. The `ash_sdui` package (server-driven UI
built on Ash) provides the component and layout model; it should be represented in the
graph via the existing `LiveView` node type, extended with SDUI-specific metadata.

A secondary goal is an on-demand Phoenix dev server preview from the Foundry Studio
sidebar, allowing developers to navigate directly from a `LiveView` node to a running
preview of that page.

---

## Decision

### 1. LiveView Node — Extended, Not a New Type

The existing `LiveView` (▣) node type is extended rather than a new type being added.
ADR-016's constraint stands: no new top-level type without an ADR justifying why the
existing 11 are insufficient. `LiveView` is the correct type for all Phoenix-rendered
UI surfaces.

**Subtype field:** `page_subtype: :liveview | :sdui | :controller` is added to `NodeEntry`.
The subtype is inferred from code, not manually annotated (see §Detection below).
It affects only the detail drawer — the canvas node icon and styling remain uniform
across subtypes at Level 3 (Component) zoom. At Code zoom (>1.5×), the subtype badge
is rendered inline on the node.

### 2. Detection — Code-First, Annotate Only What Cannot Be Inferred

**Route path** — inferred by walking the project's `Phoenix.Router` module at introspection
time. All Phoenix routers expose `__routes__/0` at runtime. For each route where
`plug == Phoenix.LiveView.Plug`, extract `path` and `plug_opts` (the LiveView module).

```elixir
# RouterIntrospector — new module in Foundry.Context
def liveview_routes(router_module) do
  router_module.__routes__()
  |> Enum.filter(&(&1.plug == Phoenix.LiveView.Plug))
  |> Enum.map(fn r -> %{module: r.plug_opts, path: r.path, dynamic: String.contains?(r.path, ":")} end)
end
```

The router module is located by scanning `Application.spec(app, :modules)` for any
module exporting `__routes__/0`.

**SDUI subtype** — inferred from `function_exported?(mod, :__sdui_lookup__, 0)`. The
`use AshSDUI` macro is updated to inject `def __sdui_lookup__, do: ...` into the using
module. No manual annotation needed.

**Dynamic route** — inferred from `:` in the route path string (e.g. `/games/:id`).
One graph node is created per route template, not per record.

**Ash actions called** — inferred by a new `Foundry.SparkMeta.Analyzers.LiveViewActions`
analyzer using `Sourceror` to parse the LiveView module's source file. It scans
`handle_event/3`, `mount/3`, and `handle_info/2` callbacks for `Ash.*` call patterns:

```
Ash.read(ResourceModule, ...)        → reads ResourceModule
Ash.create(ResourceModule, ...)      → writes ResourceModule
ResourceModule |> Ash.read(...)      → reads ResourceModule
```

Produces a list of `{resource_module, :read | :write}` tuples stored in
`NodeEntry.calls_actions`. Approximate (AST heuristic, ~80% coverage).

**Supplement** — if `@calls_actions [...]` module attribute is present, it supplements
the inferred list rather than replacing it. This handles dynamic dispatch, indirect calls,
and cases the AST scanner misses without drifting away from observable code paths.

**Route fallback** — when router discovery is unavailable, static `AshSDUI` lookups can
infer a stable preview route from source (`{:static, "deposit"}` -> `"/deposit"`,
`{:static, "home"}` -> `"/"`). Plain LiveViews and dynamic lookups are not guessed from
their Ash action calls. An explicit `@page_route` remains an escape hatch for unusual cases.

**Page group** — the only annotation required. Cannot be inferred from code:

```elixir
@page_group :player   # :player | :operator | :anonymous | :admin
```

Used for graph clustering (same cluster as the domain compound? or a separate UI cluster?)
and node color. Default: `:unknown` (neutral gray in the graph).

**Feature flags** — extracted from existing `@feature_flags` module attribute mechanism,
already in `NodeEntry`. No change needed.

### 3. NodeEntry Extensions

New fields added to `NodeEntry` (nil/empty defaults — non-breaking):

```elixir
field :page_route, :string          # "/games/:id" — route template
field :page_group, :atom            # :player | :operator | :anonymous | :admin | :unknown
field :page_dynamic, :boolean       # true if route contains :param segments
field :page_subtype, :atom          # :sdui | :liveview | :controller
field :calls_actions, [{:module, :atom}]  # [{IgamingRef.Gaming.Game, :read}, ...]
```

`NodeEntry.type` remains `:live_page` (existing introspector value). The new fields are
drawer metadata.

### 4. Edge Extensions

**`calls_action` edge** — new relation type. From a `LiveView` node to a `Resource` node.
Represents "this page calls this resource's action."

- Direction: `LiveView → Resource`
- Visual: `──────○` ("Renders / serves" in ADR-016 taxonomy) — repurposed for action calls too
- Label: action name at Code zoom (>1.5×)
- Derived from `NodeEntry.calls_actions` in `GraphBuilder.derive_page_edges/2`

**`feature_flagged_by` edge** — new relation type. From a `LiveView` node to an
`external:feature_flag:{flag_name}` node.

- Direction: `LiveView → external:feature_flag:*`
- Visual: gray dotted (`·····▶`) — same as "Guards / constrains"
- Derived from `NodeEntry.feature_flags` (existing field)

**`external:feature_flag:{name}` nodes** — created by `GraphBuilder` as synthetic
external nodes, same pattern as `external:postgres`. One per unique flag name across
all LiveView nodes. No source module — purely structural.

### 5. `ash_sdui` Package Changes

`use AshSDUI` macro extended to accept page metadata options and inject the detection
function:

```elixir
use AshSDUI,
  lookup: {:from_params, :name},
  page_group: :player    # optional, still preferred as module attribute
```

Injected by the macro:
```elixir
def __sdui_lookup__, do: unquote(opts[:lookup])
```

Route binding comes from the router walk — not from `use AshSDUI`. The `page_group`
can be passed via the macro options OR as a `@page_group` module attribute. Module
attribute takes precedence (closer to the source of truth).

### 6. Frontend — LiveView Node Rendering

**`semantics.js`** — `live_page` node kind extended with subtype badge rendering:
```js
live_page: { icon: 'layout', label: 'Page', color: '#6366f1' }
```

At Code zoom (>1.5×), the subtype badge renders inline: `SDUI` (indigo) or `LV` (blue).
Dynamic routes render a `:dynamic` pill badge on the node label.

**`edge_catalog.js`** — two new entries:
- `calls_action`: purple dashed line, arrowhead
- `feature_flagged_by`: gray dotted line, open arrowhead

**`elements.js`** — page route rendered as the node label (replaces module FQDN for
`live_page` nodes at Component zoom). Module FQDN shown at Code zoom only.

**Sidebar (detail drawer)** — for `live_page` nodes:
- Route template with dynamic badge
- Page group badge
- Subtype badge (SDUI / LiveView)
- "Actions called" section — linked node list from `calls_actions`
- "Feature flags" section — linked external node list
- "Preview" button (if preview server is configured — see §Dev Server Preview)

### 7. Dev Server Preview (igaming Reference Project)

`manifest.exs` gains a `preview_server` configuration block:

```elixir
preview_server: [
  command: "mix phx.server",
  port: 4001,
  working_dir: ".",
  env: [{"MIX_ENV", "dev"}]
]
```

`Foundry.PreviewServer` — a new `GenServer` module added to Foundry's application
supervision tree (started only when `preview_server` is configured in the manifest):

```elixir
defmodule Foundry.PreviewServer do
  use GenServer
  # start_server/0, stop_server/0, status/0 → :stopped | :starting | :running | :error
  # Manages a System Port running the configured command
  # Broadcasts status changes via Phoenix PubSub: "preview_server:status"
end
```

**LiveView events in `SystemMapLive`:**
- `start_preview` → `Foundry.PreviewServer.start_server/0`
- `stop_preview` → `Foundry.PreviewServer.stop_server/0`
- Subscribes to `"preview_server:status"` for real-time status updates

**Sidebar UI additions:**
- Start/Stop button (disabled when preview_server not configured)
- Status indicator: ● Stopped | ◎ Starting | ● Running
- Preview link: `http://localhost:{port}{page_route}` — opens in new tab when status is `:running`

**Scope:** igaming reference project only in v1. Extensible to any project with
`preview_server` in manifest.

### 8. Phoenix.LiveViewTest Scenario Tests

Page scenario tests use `Phoenix.LiveViewTest` (not Wallaby — no browser dependency,
fast, integrates with Foundry's existing `scenario_refs` coverage tracking). Tagged
`@moduletag :scenario` for Foundry coverage pickup.

Located in `reference_projects/igaming/test/pages/`. Tests exercise:
- LiveView mount and initial render
- Form submission → Ash action call verification
- SDUI layout rendering (component tree snapshot)
- Feature flag gating (test both flag states)

---

## igaming Reference Web Layer

The igaming reference project gains a `lib/web/` directory with:

| File | Route | Page group | Notes |
|---|---|---|---|
| `web/router.ex` | — | — | Phoenix router, all page routes |
| `web/live/home_live.ex` | `/` | `:anonymous` | Game collections, A/B feature flag |
| `web/live/game_live.ex` | `/games/:id` | `:player` | Loads game, calls bet flow |
| `web/live/auth_live.ex` | `/login` | `:anonymous` | AshAuthentication integration |
| `web/live/deposit_live.ex` | `/deposit` | `:player` | Finance.Wallet deposit action form |
| `web/live/withdrawal_live.ex` | `/withdrawal` | `:player` | WithdrawalRequest.create action form |
| `web/components/game_card_component.ex` | — | — | SDUI component: single game tile |
| `web/components/game_collection_component.ex` | — | — | SDUI component: game grid |
| `web/layouts/home_layout.ex` | — | — | SDUI layout: home page tree |
| `web/layouts/deposit_layout.ex` | — | — | SDUI layout: deposit form |
| `web/layouts/withdrawal_layout.ex` | — | — | SDUI layout: withdrawal form |

---

## New Modules Summary

| Module | Location | Purpose |
|---|---|---|
| `Foundry.Context.RouterIntrospector` | `apps/foundry/lib/foundry/context/router_introspector.ex` | Walks Phoenix router `__routes__/0` |
| `Foundry.SparkMeta.Analyzers.LiveViewActions` | `apps/foundry/lib/foundry/spark_meta/analyzers/live_view_actions.ex` | Sourceror AST scanner for Ash action calls |
| `Foundry.PreviewServer` | `apps/foundry/lib/foundry/preview_server.ex` | GenServer managing Phoenix dev server Port |

---

## Consequences

- ADR-016's node taxonomy is unchanged (still 11 types). `LiveView` (▣) is extended
  with new metadata fields and graph edges — no new node type is added.
- `NodeEntry` gains 5 new fields (nil/empty defaults — non-breaking schema extension).
- Two new edge relation types: `calls_action` and `feature_flagged_by`.
- `external:feature_flag:*` synthetic nodes follow the same pattern as `external:postgres`.
- The Sourceror AST scanner provides ~80% action call coverage. The `@calls_actions`
  override handles edge cases. Perfect coverage is not a goal — useful coverage is.
- Dev server preview is opt-in (manifest `preview_server` key) and scoped to dev environment.
- Phoenix.LiveViewTest-based scenario tests integrate with Foundry's existing coverage model.

## References

- ADR-016: Node/edge taxonomy (11 types + 8 edges — this ADR extends `LiveView` type)
- ADR-021: NodeEntry schema extensions (non-breaking extension pattern)
- [AshSDUI package](packages/ash_sdui/)
- [igaming reference project](reference_projects/igaming/)
- Phoenix.Router `__routes__/0` introspection API
- Sourceror AST parsing library

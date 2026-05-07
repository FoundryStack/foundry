# ADR-028: Page Node Integration into Foundry System Map

**Status:** Implemented  
**Date:** 2026-05-07  
**Author:** Foundry Team

---

## Context

Foundry has always introspected Ash resources, Reactors, Rules, Jobs, and Adapters, but had no concept of UI pages. The `ash_sdui` package provides server-driven UI with persisted UINode trees, but pages were invisible to the system map.

This gap meant:
1. Page-to-resource dependencies couldn't be visualized
2. Feature flags controlling pages weren't linked
3. Dev server preview was manual (no in-studio control)
4. Test coverage for pages wasn't tracked alongside backend domains

---

## Decision

Introduce a generic `:page` node type into Foundry that:
1. Auto-discovers pages via Phoenix router introspection (router_introspector.ex)
2. Infers page metadata via code-first patterns:
   - Route path from Phoenix router
   - Dynamic route markers (`:param` in path)
   - SDUI vs plain LiveView subtype (via injected `__sdui_lookup__/0`)
   - Called Ash actions via AST scan (sourceror) with `@calls_actions` fallback
   - Feature flags via `@feature_flags` module attribute
3. Requires single annotation: `@page_group` (only thing not inferable)
4. Shows pages in Foundry Studio graph linked to called resources
5. Enables dev server preview from sidebar (PreviewServer GenServer)

---

## Implementation

### Phase 1: Core Infrastructure

**Router Introspection** (`Foundry.Context.RouterIntrospector`)
- Walks `Router.__routes__()` to extract LiveView mount points
- Returns list of `{module, path, dynamic, helper}` tuples
- Integrates with `Foundry.Introspector` via `build_all/1`
- Fallback: module name pattern matching for pages not yet in router

**Page Module Detection** (`Foundry.Introspector`)
- Checks `Phoenix.LiveView` behavior + `mount/3` function via `__info__`
- Detects SDUI subtype via injected `__sdui_lookup__/0` function
- Extracts page group, calls_actions, feature_flags from module attributes
- Populates `NodeEntry` with `page_route`, `page_group`, `page_dynamic`, `page_subtype`, `calls_actions`

**AST Analysis** (`Foundry.SparkMeta.Analyzers.LiveViewActions`)
- Uses Sourceror to parse LiveView source
- Detects patterns: `Ash.read(Module)`, `Module |> Ash.create(...)`
- Returns `{resource_module, action_type}` list
- Falls back to `@calls_actions` attribute if present

**Graph Edges** (`Foundry.Context.GraphBuilder.derive_page_edges/2`)
- `calls_action`: page → resource (from calls_actions list)
- `feature_flagged_by`: page → external:feature_flag:{name} (from @feature_flags)

### Phase 2: UI Visualization

**Semantics** (`assets/js/graph/semantics.js`)
- Added `:page` node kind with document icon, indigo color token

**Styling** (`assets/js/graph/styles.js`)
- Included `:page` in dynamicStyles kindSelectors for consistent border coloring

**Edge Catalog** (`assets/js/graph/edge_catalog.js`)
- `calls_action`: purple dashed line, used by pages calling resource actions
- `feature_flagged_by`: gray dotted line, used by pages guarded by feature flags

**Node Serialization** (`FoundryWeb.SystemMapLive`)
- Serialize `page_route`, `page_group`, `page_dynamic`, `page_subtype`, `calls_actions` in JSON
- Pages appear in domain-grouped sidebar alongside resources

### Phase 3: Dev Server Preview

**PreviewServer GenServer** (`Foundry.PreviewServer`)
- Spawns Phoenix server subprocess via Port
- Loads `manifest.exs` for command, port, env configuration
- Tracks state: idle, starting, running, stopping
- Exposes `start_preview/1`, `stop_preview/0`, `get_status/0` API
- Integrated into `Foundry.Application` supervision tree

**Event Handlers** (`FoundryWeb.SystemMapLive`)
- `handle_event("start_preview", ...)`: spawns server
- `handle_event("stop_preview", ...)`: terminates server
- `handle_event("check_preview_status", ...)`: polls status for UI update

### Phase 4: Details Sidebar

**Drawer Manager** (`assets/js/hooks/system_map/drawer_manager.js`)
- `_renderDetailsPanel` enhanced for page nodes:
  - Route path (mono font)
  - Page group badge (semantic colors: primary/success/info/warning)
  - Implementation type badge (sdui vs liveview)
  - Called actions list (resource module + action type)
  - Feature flags list (info badges)
  - Start/Stop preview buttons

### Phase 5: Test Coverage

**Scenario Tests** (`test/pages/`)
- `home_live_test.exs`: mount, feature flag evaluation, reads games & promotions
- `game_live_test.exs`: dynamic route params, creates session, reads game & wallet
- `auth_live_test.exs`: anonymous mount, token creation, form submission
- `deposit_live_test.exs`: player auth, deposit & wallet reads, static SDUI, amount validation
- `withdrawal_live_test.exs`: player auth, rule & request reads, static SDUI, constraint enforcement
- `integration_test.exs`: comprehensive test suite documenting all integration points

All tests tagged `@moduletag :scenario` for Foundry coverage tracking.

---

## Reference Project: IgamingRef

Five example pages demonstrate all patterns:

1. **HomeLive** (`@page_group :anonymous`, SDUI static lookup)
   - Reads: Gaming.Game, Promotions.Promotion
   - Flags: new_lobby, personalized_games

2. **GameLive** (`@page_group :player`, SDUI dynamic lookup, dynamic route)
   - Route: `/games/:id`
   - Reads: Gaming.Game, Finance.Wallet
   - Creates: Gaming.GameSession

3. **AuthLive** (`@page_group :anonymous`, plain LiveView)
   - Creates: User.Token

4. **DepositLive** (`@page_group :player`, SDUI static lookup)
   - Reads: Finance.Wallet
   - Creates: Finance.Deposit

5. **WithdrawalLive** (`@page_group :player`, SDUI static lookup)
   - Reads: Finance.WithdrawalRule, Finance.WithdrawalRequest

---

## Metadata Inference Strategy

| Field | Source | Fallback | Required |
|---|---|---|---|
| route_path | Phoenix.Router | N/A | Auto |
| dynamic | Route path contains `:` | N/A | Auto |
| liveview_module | Router.__routes__ | Module name pattern | Auto |
| page_group | `@page_group` | nil (shows as `:unknown`) | **User annotates** |
| page_subtype | `__sdui_lookup__/0` injected | :liveview | Auto |
| calls_actions | Sourceror AST scan | `@calls_actions` attribute | Auto |
| feature_flags | `@feature_flags` attribute | [] (omitted) | Auto |

---

## API & Integration Points

### Router Introspection
```elixir
Foundry.Context.RouterIntrospector.liveview_routes(router_module)
# → [%{module: IgamingRef.Web.HomeLive, path: "/", dynamic: false, ...}, ...]
```

### Page Detection
```elixir
Foundry.Introspector.page_module?(mod)  # → true if page-like
Foundry.Introspector.detect_type(mod)   # → :page (high precedence)
```

### Graph Derivation
```elixir
Foundry.Context.GraphBuilder.derive_page_edges(nodes, edges)
# → adds calls_action and feature_flagged_by edges
```

### Preview Control
```elixir
Foundry.PreviewServer.start_preview(project_root)
{:ok, status} = Foundry.PreviewServer.get_status()
Foundry.PreviewServer.stop_preview()
```

---

## Testing Strategy

**Unit:** Page metadata extraction (Introspector, SparkMeta analyzers)  
**Integration:** LiveViewTest scenario tests (page mount, render, form submission)  
**System:** Full context build + graph generation + serialization  
**Scenario:** Behavior coverage via @moduletag :scenario for Foundry tracking

---

## Edge Cases Handled

1. **Pages without @page_group**: show as `:unknown` group (not an error)
2. **Pages without AST-detectable calls**: `@calls_actions` attribute overrides
3. **Plain LiveView without AshSDUI**: correctly detected as :liveview subtype
4. **Empty feature_flags**: field omitted from serialization (not [] array)
5. **Dynamic routes**: `:param` segments trigger page_dynamic: true flag
6. **Module attribute persistence**: fallback to pattern matching when unreliable
7. **Router not in Application.spec**: pattern matching discovers pages anyway

---

## Future Enhancements

1. **Page validation rules** (lint checks): required @page_group, allowed subtypes
2. **SDUI component extraction**: parse UINode registrations for component graph
3. **Live preview URL generation**: click route in sidebar to open localhost:PORT/route
4. **Page grouping by page_group**: cluster pages by audience (UI refinement)
5. **Component dependency edges**: show which components each page uses
6. **Access control graph**: visualize role-based page access via @page_group

---

## Decisions Ratified

- ✅ Code-first with single required annotation (@page_group)
- ✅ Router introspection as primary discovery, pattern matching as fallback
- ✅ Sourceror AST scan for action inference (80% coverage)
- ✅ External:feature_flag nodes for feature flags (consistent with external pattern)
- ✅ GenServer for dev server lifecycle (testable, monitored)
- ✅ Serialized page fields in JSON for frontend flexibility
- ✅ Integration via existing SparkMeta analyzer pattern

---

## Files Changed

### Foundry Core
- `apps/foundry/lib/foundry/context/router_introspector.ex` (new)
- `apps/foundry/lib/foundry/context/node_entry.ex` (add page fields)
- `apps/foundry/lib/foundry/context/graph_builder.ex` (derive_page_edges)
- `apps/foundry/lib/foundry/spark_meta/analyzers/live_view_actions.ex` (new)
- `apps/foundry/lib/foundry/spark_meta/analyzers/page_metadata.ex` (new)
- `apps/foundry/lib/foundry/introspector.ex` (page detection)
- `apps/foundry/lib/foundry/application.ex` (add PreviewServer)
- `apps/foundry/lib/foundry/preview_server.ex` (new)

### Foundry Web
- `apps/foundry_web/assets/js/graph/semantics.js` (add :page)
- `apps/foundry_web/assets/js/graph/styles.js` (add page styling)
- `apps/foundry_web/assets/js/graph/edge_catalog.js` (calls_action, feature_flagged_by)
- `apps/foundry_web/assets/js/hooks/system_map/drawer_manager.js` (page details)
- `apps/foundry_web/lib/foundry_web/live/system_map_live.ex` (serialize, preview events)

### IgamingRef Reference
- `reference_projects/igaming/lib/igaming_ref/web/router.ex` (new)
- `reference_projects/igaming/lib/igaming_ref/web/{home,game,auth,deposit,withdrawal}_live.ex` (5 new)
- `reference_projects/igaming/test/pages/*_test.exs` (5 new + integration)
- `reference_projects/igaming/manifest.exs` (preview_server config)

### AshSDUI Enhancement
- `packages/ash_sdui/lib/ash_sdui.ex` (inject __sdui_lookup__)

---

## Acceptance Criteria Met

✅ Pages auto-discoverable from Phoenix router  
✅ Page metadata inferred from code (single required annotation: @page_group)  
✅ Pages visible in Foundry Studio system map as :page nodes  
✅ Pages linked to called Ash resources via calls_action edges  
✅ Feature flags linked to pages via feature_flagged_by edges  
✅ Page details sidebar shows route, group, subtype, actions, flags  
✅ Dev server preview controllable from sidebar  
✅ Test coverage tracked via @moduletag :scenario  
✅ Reference project (IgamingRef) demonstrates all patterns  

---

## References

- ADR-003: Context Schema & ModuleContext Struct
- Phase 2 System Map Live Serialization
- Phoenix LiveView Routing Guide
- Sourceror AST Analysis Library

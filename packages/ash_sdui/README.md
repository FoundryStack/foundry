# AshSDUI

Server-Driven UI for Phoenix LiveView applications backed by [Ash](https://hexdocs.pm/ash) resources. AshSDUI lets you define UI layouts as data — either in code or persisted in your database — and render them dynamically in LiveView without redeploying.

## Features

- Define UI layouts as composable trees of typed components
- Persist and edit layouts at runtime via an Ash-powered `UINode` resource
- Code-based layouts for static or config-driven screens
- Registry-based component discovery with automatic scanning
- ETS-backed cache with automatic invalidation when `UINode` records change
- GraphQL fragment metadata on components for schema-driven tooling
- Audit trail via `ash_paper_trail` on all `UINode` changes

## Installation

```elixir
def deps do
  [
    {:ash_sdui, "~> 0.1"},
    {:ash_postgres, "~> 2"},  # or your preferred Ash data layer
    {:phoenix_live_view, "~> 1"}
  ]
end
```

Configure the data layer for `AshSDUI.UINode`:

```elixir
# config/config.exs
config :ash_sdui, AshSDUI.UINode,
  data_layer: AshPostgres.DataLayer
```

## Core Concepts

### Components

A component is a Phoenix function component registered with AshSDUI. Declare one with `use AshSDUI.Component`:

```elixir
defmodule MyAppWeb.Components.Player.ScoreCard do
  use MyAppWeb, :live_component
  use AshSDUI.Component, fragment: """
    fragment PlayerScoreCardData on Player {
      displayName
      currentScore
      rank
    }
  """

  def render(assigns) do
    ~H"""
    <div class="score-card">
      <h2><%= @subject.display_name %></h2>
      <p>Score: <%= @subject.current_score %></p>
      <p>Rank: #<%= @subject.rank %></p>
    </div>
    """
  end
end
```

The component is automatically registered in `AshSDUI.Registry` under the name derived from its module (e.g., `"Player.ScoreCard@v1"`). Set `@version "v2"` before `use AshSDUI.Component` to override the default `v1`.

### Layouts

Layouts are named trees of component references. Define them in code:

```elixir
AshSDUI.Layout.register("player-dashboard", %AshSDUI.Layout.LayoutDef{
  name: "player-dashboard",
  root: %AshSDUI.Layout.Node{
    component: "Player.ScoreCard@v1",
    subject_resource: "MyApp.Game.Player",
    subject_id: "first",
    children: [
      %AshSDUI.Layout.Node{
        component: "Player.ActivityFeed@v1",
        region: :sidebar,
        order: 0
      }
    ]
  }
})
```

Or create them dynamically via `AshSDUI.UINode` Ash actions:

```elixir
AshSDUI.UINode
|> Ash.Changeset.for_create(:create, %{
  component_name: "Player.ScoreCard@v1",
  subject_resource: "MyApp.Game.Player",
  subject_id: player_id,
  region: :default,
  order: 0
})
|> Ash.create!()
```

### LiveView Integration

Add `use AshSDUI` to any LiveView. It injects a `mount/3` that resolves and renders the layout tree, and a `sdui_root/1` component for rendering it:

```elixir
defmodule MyAppWeb.Live.PlayerDashboard do
  use MyAppWeb, :live_view
  use AshSDUI, lookup: {:from_params, :name}

  def render(assigns) do
    ~H"""
    <%= if @__sdui_tree__ do %>
      <.sdui_root />
    <% else %>
      <div>Layout not found</div>
    <% end %>
    """
  end
end
```

The `:lookup` option controls how the layout name is resolved:

| Strategy                        | Example                  | Resolves to                 |
| ------------------------------- | ------------------------ | --------------------------- |
| `{:from_params, :name}`         | `?name=player-dashboard` | `"player-dashboard"`        |
| `{:static, "player-dashboard"}` | —                        | Always `"player-dashboard"` |

You can override `mount/3` after `use AshSDUI` to add your own socket assigns — the injected mount is declared `defoverridable`.

## UINode Resource

`AshSDUI.UINode` is an Ash resource that stores individual nodes of a dynamic layout.

### Attributes

| Attribute           | Type       | Notes                                                  |
| ------------------- | ---------- | ------------------------------------------------------ |
| `:id`               | `:uuid`    | Primary key                                            |
| `:component_name`   | `:string`  | Required. Pattern: `^[A-Za-z0-9\.]+@v\d+$`             |
| `:static_props`     | `:map`     | Default: `%{}`                                         |
| `:subject_resource` | `:string`  | Optional Ash resource module name                      |
| `:subject_id`       | `:uuid`    | Optional. Use `"first"` to resolve the first record    |
| `:region`           | `:atom`    | Default: `:default`                                    |
| `:order`            | `:integer` | Default: `0`                                           |
| `:status`           | `:atom`    | `:draft`, `:published`, `:archived`. Default: `:draft` |
| `:name`             | `:string`  | Optional human label                                   |
| `:parent_id`        | `:uuid`    | Optional. Points to parent `UINode`                    |

### Actions

| Action     | Type    | Notes                          |
| ---------- | ------- | ------------------------------ |
| `:read`    | read    | Default                        |
| `:create`  | create  | Accepts all attributes         |
| `:update`  | update  | Accepts all attributes         |
| `:destroy` | destroy | Default                        |
| `:publish` | update  | Sets `:status` to `:published` |
| `:revert`  | update  | Sets `:status` to `:archived`  |

### Audit Trail

All changes to `UINode` are tracked via `ash_paper_trail` in `:changes_only` mode. This gives you a full revision history out of the box.

## Caching

`AshSDUI.Cache` is an ETS-backed cache keyed on layout name. Rendered trees are cached after the first render and automatically evicted whenever a relevant `UINode` is created, updated, or destroyed (via `AshSDUI.Notifier`).

Manual cache operations:

```elixir
AshSDUI.Cache.get("player-dashboard")   # {:ok, tree} | {:error, :not_found}
AshSDUI.Cache.evict("player-dashboard") # :ok
AshSDUI.Cache.flush()                   # clears all entries
```

## Component Registry

`AshSDUI.Registry` holds all discovered components. It is backed by ETS (fast concurrent reads) plus `persistent_term` (survives ETS resets).

```elixir
AshSDUI.Registry.lookup("Player.ScoreCard@v1")
# {:ok, %{module: MyAppWeb.Components.Player.ScoreCard, name: "Player.ScoreCard@v1",
#          fragment: "fragment PlayerScoreCardData on Player { ... }",
#          subject_types: ["Player"]}}

AshSDUI.Registry.all()
# [%{module: ..., name: ..., fragment: ..., subject_types: [...]}, ...]

AshSDUI.Registry.discover_components()
# Scans all loaded OTP applications and registers any module using AshSDUI.Component
```

## Subject Resolution

When a `UINode` has a `:subject_resource` and `:subject_id`, `AshSDUI.Calculations.ResolveSubject.resolve/1` fetches the live Ash record and passes it to the component as `@subject`. Using `"first"` as the subject ID returns the first record from the resource.

## License

MIT

# Unified Component Graph for SDUI

**Date:** May 03, 2026  
**Status:** Accepted  
**Authors:** Architecture Team

## 1. Context & Problem Statement

We require a Server-Driven UI (SDUI) architecture that offers maximum flexibility for real-time personalization, A/B testing, and AI-driven layout mutations. Previous architectural iterations explored hardcoded LiveViews and a distinction between "Layouts" and "Components." These approaches were found to be insufficient, creating either rigid code structures or artificial abstractions that resulted in developer boilerplate and limited dynamism. The ultimate goal is to represent the entire application UI as pure, mutable data, eliminating the need for code deployments to alter UI structure.

## 2. Decision

We will adopt a **Unified Component Graph** architecture. This decision abolishes the distinction between "layouts" and "components." The entire UI is modeled as a graph of nodes, where every node is a component.

This architecture is founded on the following principles:

1.  **A Single Abstraction (`UINode`):** The entire UI graph—from the root page down to a single button—is represented by a single, self-referencing Ash Resource named `UINode`.
2.  **UI is a Data Graph:** A "page" is simply a root `UINode` in the database. Its content and structure are defined by its children nodes. This makes the application's structure queryable, auditable, and mutable via database transactions.
3.  **Component-Owned Contracts:** Each frontend component is the single source of truth for its own data needs, which it declares via a versioned GraphQL fragment. The system infers data dependencies directly from these fragments.
4.  **Generic Rendering Engine:** A single, generic Phoenix LiveView (`SDUIPageLive`) can render any UI graph by looking up the corresponding root `UINode` from the URL, eliminating all page-specific LiveView files.

## 3. Consequences

### Positive

- **Total Flexibility:** An AI Agent or a human manager can fundamentally restructure any page for any user segment by simply manipulating `UINode` records in the database. Swapping a two-column layout for a three-column layout is a data change, not a code change.
- **Zero Developer Boilerplate:** Developers no longer write page-specific LiveViews, `mount` functions for data fetching, or rendering loops. They focus solely on building reusable, self-contained components.
- **Radical Reusability:** Any component can be placed anywhere in the UI graph. Its context is defined entirely by the data, not by hardcoded parent-child relationships in code.
- **Simplified Tooling:** This data-centric model enables the creation of powerful internal tools, such as visual UI builders that directly manipulate the `UINode` database table.

### Negative / Risks & Mitigations

- **Database as a Potential Bottleneck:** Rendering a page now requires a recursive database query to fetch the entire component graph.
  - **Mitigation:** We will rely on the underlying data layer's efficiency (e.g., `ash_postgres` with Recursive CTEs, or `ash_gel`'s native graph-fetching capabilities). Furthermore, the UI _structure_ can be aggressively cached (e.g., in ETS or Redis), as it changes far less frequently than the underlying business _data_.
- **Initial Complexity for Trivial Pages:** The model may seem like overkill for a simple, static "About Us" page.
  - **Mitigation:** The system is not exclusive. Teams can and should still use traditional, simple LiveViews for pages that are guaranteed to be static and do not require dynamic composition. The SDUI engine will be used for the dynamic, user-facing parts of the application.

---

# Technical Specification: `AshSDUI`

## 1. The Core Resource: `UINode`

This single resource models the entire UI graph.

```elixir
# lib/my_app/ui/ui_node.ex
defmodule MyApp.UI.UINode do
  use Ash.Resource, data_layer: MyApp.DataLayer # e.g., AshGel.DataLayer

  attributes do
    uuid_primary_key :id

    # WHAT to render: The globally unique, versioned component identifier.
    attribute :component_name, :string, allow_nil?: false, constraints: [
      format: ~r/^[A-Za-z0-9\.]+@v\d+$/,
      message: "must be in the format 'Component.Name@v1'"
    ]

    # HOW to configure: Static properties passed to the component.
    attribute :static_props, :map, default: %{}

    # WHAT data to show: The abstract pointer to an Ash Resource.
    attribute :subject_resource, :string
    attribute :subject_id, :uuid

    # WHERE it lives in the graph: The tree structure.
    # Defines which slot/region of the parent this node renders into.
    attribute :region, :atom, default: :default
    # Defines the render order for multiple children in the same region.
    attribute :order, :integer, default: 0
  end

  relationships do
    # A self-referencing relationship builds the entire tree/graph.
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, destination_attribute: :parent_id
  end

  # Dynamically resolves the subject_resource and subject_id into a hydrated Ash record.
  calculations do
    calculate :subject, :struct, MyApp.UI.Calculations.ResolveSubject
  end
end
```

## 2. The Component Contract: `use AshSDUI.Component`

Developers build self-contained components. A macro provides the developer-friendly interface and handles the underlying registration and parsing.

```elixir
# lib/my_app_web/components/user_profile/header.ex
defmodule MyAppWeb.Components.UserProfile.Header do
  # 1. The developer uses the macro and provides ONLY the GraphQL fragment.
  # The system parses this at compile time to infer that this component
  # is compatible with the `User` resource.
  use AshSDUI.Component, fragment: """
    fragment UserProfileHeaderData on User {
      username
      avatarUrl
    }
  """

  # 2. The render function receives the hydrated data and can render its children
  # into named slots/regions using Phoenix's built-in `render_slot`.
  def render(assigns) do
    ~H"""
    <div class="profile-header">
      <img src={@runtime_data.avatarUrl} />
      <span><%= @runtime_data.username %></span>

      <%# Renders any child nodes assigned to the :actions region %>
      <div class="actions-toolbar">
        <%= render_slot(@inner_block, :actions) %>
      </div>
    </div>
    """
  end
end
```

## 3. The Generic Rendering Engine

### 3.1. The Generic LiveView (`SDUIPageLive`)

This single LiveView replaces all page-specific LiveViews. It is provided by the `AshSDUI` library.

```elixir
# lib/my_app_web/live/sdui_page_live.ex
defmodule MyAppWeb.Live.SDUIPageLive do
  use MyAppWeb, :live_view

  # The `use` macro injects all necessary logic.
  # `:from_params` tells it to use the :name from the URL to find the root UINode.
  use AshSDUI, lookup: {:from_params, :name}

  # The render function simply delegates to the AshSDUI rendering component.
  def render(assigns) do
    ~H"""
    <.sdui_root />
    """
  end
end
```

### 3.2. Routing

The router has a single, generic entry point for all SDUI-rendered pages.

```elixir
# lib/my_app_web/router.ex
live "/p/:name", SDUIPageLive, :show
```

Navigating to `/p/player-dashboard` will cause the system to look for a root `UINode` where `component_name` starts with `"Pages.PlayerDashboard"`.

## 4. Public Interfaces

### 4.1. GraphQL (for headless clients)

The system exposes a query to fetch any UI graph, allowing native mobile clients to use the same SDUI engine.

- **Query:** `getUINode(name: String!): UINode`
- **Types:** `ash_graphql` automatically generates a `UINode` type and a polymorphic `SDUISubject` Union type for the `subject` field based on which resources have opted-in.

### 4.2. Actions (for interactivity)

Write operations are handled by standard Ash Actions, triggered from components via `phx-click`.

```elixir
# Inside a component...
def handle_event("cashout", %{"bet_id" => bet_id}, socket) do
  case MyApp.Gamble.cashout_bet(bet_id, actor: socket.assigns.current_user) do
    {:ok, _} -> # Notify success
    {:error, _} -> # Notify error
  end
  {:noreply, socket}
end
```

The `UINode` for this component in the database would contain `action_bindings` to map a UI event to this `phx-click` event and provide the necessary payload (e.g., `%{bet_id: "$subject.id"}`).

---

# Production System Specification: `AshSDUI`

This document extends the core ADR with specifications for the ancillary systems required for a robust, developer-friendly, and performant production environment.

## 1. Core Rendering: Dual-Mode Engine (Code & Database)

The system MUST support rendering UI graphs from two sources to balance development speed with production flexibility. The lookup process will follow a fallback mechanism: **Database-First, then Code Fallback.**

### 1.1. Source 1: Database (`UINode` Resource)

This remains the primary source for production, A/B testing, and AI-driven mutations, as defined in the core ADR.

### 1.2. Source 2: Code-Based Layouts (Ash Resource DSL)

To enable version-controlled, code-based defaults, a new extension `AshSDUI.Layout` will provide a DSL to define UI graphs directly within an Ash Resource.

#### **DSL Specification:**

The DSL will live inside a `sdui_layout` block and mirror the structure of the `UINode` resource.

```elixir
# lib/my_app/ui/layouts/default_layouts.ex
defmodule MyApp.UI.Layouts.DefaultLayouts do
  use Ash.Resource, extensions: [AshSDUI.Layout]

  sdui_layout do
    # Defines a code-based graph with the root name 'player-dashboard'
    name "player-dashboard"

    # The root node. `bind_subject: :self` binds to the actor/context.
    node :root, component: "Layouts.TwoColumn@v1", bind_subject: :self do

      # Children are nested. `region` maps to the parent's slots.
      node :header, component: "UserProfile.Header@v1", bind_subject: :self, region: :sidebar

      node :bets, component: "Betting.ActiveBets@v1", bind_subject: :active_bets, region: :main
    end
  end
end
```

### 1.3. Unified Lookup Logic

The `use AshSDUI` macro in `SDUIPageLive` will inject `mount/3` logic that performs this unified lookup:

1.  Receive the layout name (e.g., "player-dashboard") from the router.
2.  **Attempt DB Lookup:** Query the `UINode` resource for a root node matching the name with `status: :published`.
3.  **On DB Hit:** If found, fetch its descendants and render the graph from the database records.
4.  **On DB Miss (Fallback):** If no published record is found, scan the compile-time registry for a code-based layout with the matching name.
5.  **On Code Hit:** If found, render the graph directly from the parsed DSL structure.
6.  **On Total Miss:** Raise an error.

---

## 2. Developer Tooling & Experience

### 2.1. Central Component Registry

The `use AshSDUI.Component` macro will register every component into a compile-time map stored in `:persistent_term`.

- **Key:** Component name string (e.g., `"UserProfile.Header@v1"`)
- **Value:** A struct containing `{module, fragment, inferred_subject_types}`.
- **Purpose:** This enables instant lookups for query generation, validation, and tooling without filesystem scans at runtime.

### 2.2. Storybook Integration for Isolated Development

The system will provide a helper to render components in Phoenix Storybook without the full SDUI graph.

- **Helper:** `AshSDUI.render_in_storybook(component_name, assigns)`
- **`assigns` Shape:** `%{subject: mock_ash_record, static_props: %{}, ...}`
- **Example Story:**

  ```elixir
  # priv/storybook/components/user_profile_header.story.exs
  defmodule MyAppWeb.Storybook.Components.UserProfile.Header do
    use PhoenixStorybook.Story, :component

    def function, do: &AshSDUI.render_in_storybook/2
    def component, do: "UserProfile.Header@v1" # From registry

    def variations do
      [
        %Story.Variation{
          id: :default,
          attributes: %{
            subject: %MyApp.Accounts.User{username: "Test User", avatar_url: ...},
            static_props: %{}
          }
        }
      ]
    end
  end
  ```

---

## 3. Performance & Caching Strategy

### 3.1. UI Graph Caching (Layer 1)

The structure of a UI graph from the database will be aggressively cached.

- **Mechanism:** An Ash Notifier on the `UINode` resource will trigger cache invalidation.
- **Implementation:** A `Cache` GenServer will subscribe to the notifier. On any `create`, `update`, or `destroy` event for a `UINode`, it will evict the cache for that node's entire graph.
- **Storage:** ETS for single-node deployments; Redis for multi-node.
- **Cached Value:** The fully resolved tree of `UINode` records (as Elixir structs), ready for the rendering engine. The hydrated `subject` data is **not** cached here.

### 3.2. Data Hydration Optimization (Layer 2)

The `ResolveSubject` calculation will leverage `Ash.Dataloader` to prevent N+1 query problems during the data hydration phase. When resolving subjects for 10 nodes that all point to `Bet` resources, the dataloader will batch these into a single database query.

---

## 4. Frontend & Asset Management

### 4.1. Asset Colocation Convention

Component-specific assets will be colocated by convention.

- **Component:** `lib/my_app_web/components/user_profile/header.ex`
- **JavaScript:** `assets/js/components/user_profile/header.js`
- **CSS:** `assets/css/components/user_profile/header.css`
- **Build Tooling:** The `esbuild` configuration will be updated to automatically discover and bundle any assets following this convention.

### 4.2. Client-Side State

Ephemeral state will be managed using Phoenix's native JavaScript hooks.

- **Mechanism:** Components will render a `phx-hook` attribute.
  ```elixir
  def render(assigns) do
    ~H"""
    <div phx-hook="ChartJS" data-chart-data={encode_json(@runtime_data.chart_points)}>
      <canvas id={"chart-#{@id}"}></canvas>
    </div>
    """
  end
  ```
- This provides a clean escape hatch for rich client-side interactivity without polluting the server-side state model.

---

## 5. Governance & Workflow

### 5.1. Preview & Publishing Workflow

The `UINode` resource will be enhanced to support a safe publishing workflow.

- **New Attribute:** `attribute :status, :atom, constraints: [one_of: [:draft, :published, :archived]], default: :draft, allow_nil?: false`
- **Preview Logic:** The `use AshSDUI` macro will inspect the `socket.assigns.current_user` and `params`. If the user has a "preview" permission and a `?preview=true` param is present, the lookup logic will query for nodes with `status: :draft` instead of `:published`.
- **Actions:** The `UINode` resource will have `publish` and `revert` actions that handle changing the status and archiving old versions.

### 5.2. Auditing

All changes to the UI graph MUST be audited.

- **Implementation:** The `AshPaperTrail` extension will be added to the `UINode` resource.
  ```elixir
  # In MyApp.UI.UINode
  use Ash.Resource, extensions: [AshPaperTrail.Resource]
  ```
- This provides a complete, out-of-the-box audit log, tracking which user or AI agent made what change and when.

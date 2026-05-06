defmodule AshSDUI do
  @moduledoc """
  Server-Driven UI for Phoenix LiveView applications backed by Ash resources.

  AshSDUI lets you define UI layouts as data — either in code or persisted in your
  database — and render them dynamically in LiveView without redeploying.

  ## Key modules

  - `AshSDUI.Component` — macro for declaring and registering SDUI components
  - `AshSDUI.Registry` — ETS-backed registry of all discovered components
  - `AshSDUI.Layout` — code-based layout registry for static or config-driven screens
  - `AshSDUI.UINode` — Ash resource for persisting dynamic layout trees
  - `AshSDUI.Renderer` — builds a `TreeNode` tree from a layout name or `UINode` records
  - `AshSDUI.Cache` — ETS-backed cache with automatic invalidation on `UINode` changes
  - `AshSDUI.Notifier` — Ash notifier that evicts cache entries on resource changes
  - `AshSDUI.Calculations.ResolveSubject` — resolves `{subject_resource, subject_id}` to a live record
  - `AshSDUI.Components.SDUIRoot` — Phoenix component that recursively renders a tree

  ## Usage in a LiveView

  Add `use AshSDUI` with a lookup strategy and call `<.sdui_root />` in your template:

      defmodule MyAppWeb.Live.PlayerDashboard do
        use MyAppWeb, :live_view
        use AshSDUI, lookup: {:from_params, :name}

        def render(assigns) do
          ~H\"""
          <%= if @__sdui_tree__ do %>
            <.sdui_root />
          <% else %>
            <div>Layout not found</div>
          <% end %>
          \"""
        end
      end

  You must reference `@__sdui_tree__` in your template so Phoenix includes it in the
  assigns passed to `sdui_root`. The injected `mount/3` is declared `defoverridable`
  — you can override it to add your own socket assigns.

  ## Lookup strategies

  - `{:from_params, :name}` — reads the layout name from the socket params map
  - `{:static, "layout-name"}` — always renders the named layout

  ## Defining a component

      defmodule MyAppWeb.Components.Player.ScoreCard do
        use MyAppWeb, :live_component
        use AshSDUI.Component, fragment: \"""
          fragment PlayerScoreCardData on Player {
            displayName
            currentScore
          }
        \"""

        def render(assigns) do
          ~H\"""
          <div>
            <h2><%= @subject.display_name %></h2>
            <p>Score: <%= @subject.current_score %></p>
          </div>
          \"""
        end
      end

  Components are registered automatically under a name derived from the module
  (e.g., `"Player.ScoreCard@v1"`). Set `@version "v2"` before `use AshSDUI.Component`
  to override the default version suffix.

  See the [README](https://hexdocs.pm/ash_sdui) for full usage, layout definitions,
  UINode actions, and caching details.
  """

  defmacro __using__(opts) do
    lookup = Keyword.fetch!(opts, :lookup)

    quote do
      @impl true
      def mount(params, session, socket) do
        name = AshSDUI.__resolve_name__(unquote(lookup), params)

        case AshSDUI.Renderer.to_tree(name) do
          {:ok, tree} ->
            {:ok, assign(socket, :__sdui_tree__, tree)}

          {:error, reason} ->
            {:ok, assign(socket, :__sdui_tree__, nil)}
        end
      end

      defoverridable mount: 3

      def sdui_root(assigns) do
        tree = Map.get(assigns, :tree) || Map.get(assigns, :__sdui_tree__)
        AshSDUI.Components.SDUIRoot.render(
          Map.put(assigns, :tree, tree)
        )
      end
    end
  end

  @doc false
  def __resolve_name__({:from_params, key}, params) do
    Map.get(params, to_string(key))
  end

  def __resolve_name__({:static, name}, _params) do
    name
  end
end

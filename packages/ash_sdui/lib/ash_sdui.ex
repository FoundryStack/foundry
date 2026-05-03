defmodule AshSDUI do
  @moduledoc """
  Server-Driven UI library for Phoenix LiveView applications backed by Ash resources.

  ## Usage in a LiveView

      defmodule MyAppWeb.Live.PlayerDashboard do
        use MyAppWeb, :live_view
        use AshSDUI, lookup: {:from_params, :name}

        def render(assigns) do
          ~H\"""
          <%= if @__sdui_tree__ do %>
            <.sdui_root />
          <% else %>
            <div>Loading...</div>
          <% end %>
          \"""
        end
      end

  The key is that you must reference `@__sdui_tree__` in your render template
  (even if just for the conditional check) so that Phoenix includes it in the
  assigns passed to the `sdui_root` component.

  ## Lookup strategies

  - `{:from_params, :name}` — reads the layout name from socket params
  - `{:static, "layout-name"}` — always renders the named layout
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

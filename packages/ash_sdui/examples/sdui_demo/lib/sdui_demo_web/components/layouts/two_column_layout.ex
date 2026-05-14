defmodule SduiDemoWeb.Components.Layouts.TwoColumnLayout do
  use AshSDUI.Component,
    fragment: """
    fragment TwoColumnLayoutData on Layout {
      id
    }
    """

  use Phoenix.Component

  def render(assigns) do
    sidebar_children = Map.get(assigns.children || %{}, :sidebar, [])
    main_children = Map.get(assigns.children || %{}, :main, [])

    assigns =
      assigns
      |> Phoenix.Component.assign(:sidebar_children, sidebar_children)
      |> Phoenix.Component.assign(:main_children, main_children)

    ~H"""
    <div class="two-column-layout" data-testid="two-column-layout">
      <aside class="sidebar">
        <%= for child <- @sidebar_children do %>
          <%= child %>
        <% end %>
      </aside>
      <main class="main-content">
        <%= for child <- @main_children do %>
          <%= child %>
        <% end %>
      </main>
    </div>
    """
  end
end

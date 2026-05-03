defmodule SduiDemoWeb.Components.ActionButton do
  use AshSDUI.Component,
    fragment: """
    fragment ActionButtonData on Action {
      label
      url
    }
    """

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <a href={Map.get(@props, "url", "#")} class="btn action-button" data-testid="action-button">
      <%= Map.get(@props, "label", "Click") %>
    </a>
    """
  end
end

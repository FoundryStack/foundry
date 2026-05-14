defmodule SduiDemoWeb.Components.UserCard do
  use AshSDUI.Component,
    fragment: """
    fragment UserCardData on User {
      username
      avatarUrl
    }
    """

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="user-card" data-testid="user-card">
      <%= if @subject do %>
        <img src={@subject.avatar_url} alt={@subject.username} class="avatar" />
        <h2><%= @subject.username %></h2>
        <p><%= @subject.email %></p>
      <% else %>
        <p>No user loaded</p>
      <% end %>
    </div>
    """
  end
end

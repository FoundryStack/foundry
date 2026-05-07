defmodule IgamingRefWeb.GameLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:from_params, :name}

  @page_group :player
  @calls_actions [
    {IgamingRef.Gaming.Game, :read},
    {IgamingRef.Finance.Wallet, :read},
    {IgamingRef.Gaming.GameSession, :create}
  ]

  @moduledoc "GameLive - #{@page_group} page"

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    game = Ash.read_one!(IgamingRef.Gaming.Game, filter: [id: game_id])
    wallet = Ash.read_one!(IgamingRef.Finance.Wallet, filter: [user_id: socket.assigns.user_id])

    {:ok, socket |> assign(game: game, wallet: wallet)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1><%= @game.name %></h1>
    <p>Balance: <%= @wallet.balance %></p>
    """
  end
end

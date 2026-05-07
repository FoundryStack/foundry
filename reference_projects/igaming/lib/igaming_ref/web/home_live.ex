defmodule IgamingRef.Web.HomeLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:static, "home"}

  @page_group :anonymous
  @feature_flags [:new_lobby, :personalized_games]
  @calls_actions [{IgamingRef.Gaming.Game, :read}, {IgamingRef.Promotions.BonusCampaign, :read}]

  @moduledoc "HomeLive - #{@page_group} page with feature flags: #{inspect(@feature_flags)}"

  @impl true
  def mount(_params, _session, socket) do
    games = Ash.read!(IgamingRef.Gaming.Game)
    promos = Ash.read!(IgamingRef.Promotions.BonusCampaign)

    {:ok, socket |> assign(games: games, promos: promos)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Welcome to Gaming Platform</h1>
    <p>Featured Games</p>
    """
  end
end

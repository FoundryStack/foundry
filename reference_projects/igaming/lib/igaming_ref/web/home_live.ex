defmodule IgamingRef.Web.HomeLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:static, "home"}

  alias IgamingRef.Web.PreviewSupport

  @page_group :anonymous
  @feature_flags [:new_lobby, :personalized_games]

  @moduledoc "HomeLive - #{@page_group} page with feature flags: #{inspect(@feature_flags)}"

  @impl true
  def mount(_params, _session, socket) do
    games = PreviewSupport.safe_read(fn -> Ash.read!(IgamingRef.Gaming.Game) end, [])
    Foundry.TestScenario.RuntimeCapture.trace_node("IgamingRef.Gaming.Game", action_kind: :read)

    promos =
      PreviewSupport.safe_read(fn -> Ash.read!(IgamingRef.Promotions.BonusCampaign) end, [])
    Foundry.TestScenario.RuntimeCapture.trace_node("IgamingRef.Promotions.BonusCampaign", action_kind: :read)

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

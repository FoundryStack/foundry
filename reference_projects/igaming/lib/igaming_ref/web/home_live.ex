defmodule IgamingRef.Web.HomeLive do
  use Phoenix.LiveView
  use AshSDUI, lookup: {:static, "home"}

  alias IgamingRef.Web.PreviewSupport

  @page_group :anonymous
  @feature_flags [:new_lobby, :personalized_games]

  @moduledoc "HomeLive - #{@page_group} page with feature flags: #{inspect(@feature_flags)}"

  @impl true
  def mount(_params, _session, socket) do
    games = PreviewSupport.safe_read(fn -> Ash.read!(IgamingRef.Gaming.Game, authorize?: false) end, [])

    promos =
      PreviewSupport.safe_read(
        fn -> Ash.read!(IgamingRef.Promotions.BonusCampaign, authorize?: false) end,
        []
      )

    {:ok, socket |> assign(games: games, promos: promos)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Welcome to Gaming Platform</h1>
    <p>Featured Games</p>
    <ul id="featured-games">
      <li :for={game <- @games}>{game_name(game)}</li>
      <li :if={Enum.empty?(@games)}>No featured games available</li>
    </ul>
    <p>Active Promotions</p>
    <ul id="active-promotions">
      <li :for={promo <- @promos}>{promo.name}</li>
      <li :if={Enum.empty?(@promos)}>No active promotions available</li>
    </ul>
    """
  end

  defp game_name(%{title: title}) when is_binary(title), do: title
  defp game_name(%{name: name}) when is_binary(name), do: name
  defp game_name(_game), do: "Unknown Game"
end

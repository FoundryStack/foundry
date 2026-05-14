defmodule IgamingRef.Web.PagesIntegrationTest do
  use IgamingRef.ConnCase, async: false
  use IgamingRef.DataCase

  import Phoenix.LiveViewTest

  alias IgamingRef.PageFixtures
  alias IgamingRef.Web.Router

  test "router exposes the expected liveview routes" do
    routes =
      Router
      |> Phoenix.Router.routes()
      |> Enum.map(& &1.path)

    assert "/" in routes
    assert "/auth" in routes
    assert "/deposit" in routes
    assert "/withdrawal" in routes
    assert "/games/:id" in routes
  end

  test "pages mount through the router with real data, not just preview fallbacks" do
    player = PageFixtures.player_fixture()
    wallet = PageFixtures.wallet_fixture(player, %{balance: Money.new(:GBP, "50.00")})
    game = PageFixtures.game_fixture(%{title: "Golden Harbor"})
    _campaign = PageFixtures.bonus_campaign_fixture(%{name: "Starter Spins"})

    {:ok, _home, home_html} = live(build_conn(), "/")
    {:ok, _auth, auth_html} = live(build_conn(), "/auth")

    {:ok, _deposit, deposit_html} =
      live(build_conn(%{"player_id" => player.id}), "/deposit")

    {:ok, _withdrawal, withdrawal_html} =
      live(build_conn(%{"player_id" => player.id}), "/withdrawal")

    {:ok, game_view, game_html} =
      live(build_conn(%{"player_id" => player.id}), "/games/#{game.id}")

    assert home_html =~ "Starter Spins"
    assert auth_html =~ "Sign In"
    assert deposit_html =~ to_string(wallet.balance)
    assert withdrawal_html =~ to_string(wallet.balance)
    assert game_html =~ "Golden Harbor"
    assert PageFixtures.view_assigns(game_view).game.id == game.id
  end
end

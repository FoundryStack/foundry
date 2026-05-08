defmodule IgamingRef.Web.GameLiveTest do
  use IgamingRef.ConnCase, async: false
  use IgamingRef.DataCase

  import Phoenix.LiveViewTest
  import Foundry.TestScenario

  alias IgamingRef.PageFixtures

  describe "game page" do
    test "loads the routed game and the current player's wallet" do
      player = PageFixtures.player_fixture()
      wallet = PageFixtures.wallet_fixture(player, %{balance: Money.new(:GBP, "75.50")})
      game = PageFixtures.game_fixture(%{title: "Mega Volcano"})

      capture do
        {:ok, view, html} =
          live(build_conn_with_trace(%{"player_id" => player.id}), "/games/#{game.id}")

        assert html =~ "Mega Volcano"
        assert html =~ to_string(wallet.balance)
        assert has_element?(view, "button", "Play")
      end
    end

    test "clicking play creates a game session for the routed game" do
      player = PageFixtures.player_fixture()
      _wallet = PageFixtures.wallet_fixture(player, %{balance: Money.new(:GBP, "25.00")})
      game = PageFixtures.game_fixture(%{title: "Crystal River"})

      capture do
        {:ok, view, _html} =
          live(build_conn_with_trace(%{"player_id" => player.id}), "/games/#{game.id}")

        render_click(element(view, "button", "Play"))
        session = PageFixtures.session_for(player.id, game.id)

        assert session.status == :active
        assert PageFixtures.flash(view, :info) == "Game session started"
        assert PageFixtures.normalize_text(render(view)) =~ "Session ID:"
      end
    end

    test "preview fallback route still renders and failed start shows an error" do
      capture do
        {:ok, view, html} = live(build_conn(), "/games/preview")

        assert html =~ "Preview Game"
        assert html =~ "£1,250.00"

        render_click(element(view, "button", "Play"))
        assert PageFixtures.flash(view, :error) == "Could not start session"
      end
    end
  end
end

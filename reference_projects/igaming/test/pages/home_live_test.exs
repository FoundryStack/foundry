defmodule IgamingRef.Web.HomeLiveTest do
  use IgamingRef.ConnCase, async: false
  use IgamingRef.DataCase

  import Phoenix.LiveViewTest
  import Foundry.TestScenario

  alias IgamingRef.PageFixtures

  describe "home page" do
    test "renders featured games and active promotions from live data" do
      game = PageFixtures.game_fixture(%{title: "Neon Atlas"})
      campaign = PageFixtures.bonus_campaign_fixture(%{name: "Friday Reload"})

      capture do
        {:ok, _view, html} = live(build_conn_with_trace(), "/")

        assert html =~ "Welcome to Gaming Platform"
        assert html =~ "Featured Games"
        assert html =~ game.title
        assert html =~ "Active Promotions"
        assert html =~ campaign.name
      end
    end

    test "shows stable empty states when no data is available" do
      capture do
        {:ok, _view, html} = live(build_conn_with_trace(), "/")

        assert html =~ "No featured games available"
        assert html =~ "No active promotions available"
      end
    end
  end
end

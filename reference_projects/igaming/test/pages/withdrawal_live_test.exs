defmodule IgamingRef.Web.WithdrawalLiveTest do
  use IgamingRef.ConnCase, async: false
  use IgamingRef.DataCase

  import Phoenix.LiveViewTest
  import Foundry.TestScenario

  alias IgamingRef.PageFixtures

  describe "withdrawal page" do
    test "mounts with the player's real wallet balance and active form controls" do
      player = PageFixtures.player_fixture()
      wallet = PageFixtures.wallet_fixture(player, %{balance: Money.new(:GBP, "215.00")})

      capture do
        {:ok, view, html} =
          live(build_conn_with_trace(%{"player_id" => player.id}), "/withdrawal")

        assert html =~ "Withdraw Funds"
        assert html =~ to_string(wallet.balance)
        assert has_element?(view, "form[phx-submit=submit_withdrawal]")
        assert has_element?(view, "input[name=amount][type=number]")
        assert has_element?(view, "button", "Withdraw")
      end
    end

    test "submitting the form creates a withdrawal request and shows success" do
      player = PageFixtures.player_fixture()
      wallet = PageFixtures.wallet_fixture(player, %{balance: Money.new(:GBP, "300.00")})

      capture do
        {:ok, view, _html} =
          live(build_conn_with_trace(%{"player_id" => player.id}), "/withdrawal")

        view
        |> form("form", %{"amount" => "50.00"})
        |> render_submit()

        request = PageFixtures.withdrawal_for_wallet(wallet.id)

        assert request.player_id == player.id
        assert request.amount == Money.new(:GBP, "50.00")
        assert request.status == :pending
        assert PageFixtures.flash(view, :info) == "Withdrawal requested"
      end
    end

    test "preview fallback still mounts safely and failed submission shows an error" do
      capture do
        {:ok, view, html} = live(build_conn(), "/withdrawal")

        assert html =~ "£1,250.00"

        view
        |> form("form", %{"amount" => "50.00"})
        |> render_submit()

        assert PageFixtures.flash(view, :error) == "Withdrawal failed"
      end
    end
  end
end

defmodule IgamingRef.Web.DepositLiveTest do
  use IgamingRef.ConnCase, async: false
  use IgamingRef.DataCase

  import Phoenix.LiveViewTest

  alias IgamingRef.PageFixtures

  test "mounts with the player's real wallet balance and active form controls" do
    player = PageFixtures.player_fixture()
    wallet = PageFixtures.wallet_fixture(player, %{balance: Money.new(:GBP, "1250.00")})

    {:ok, view, html} = live(build_conn_with_trace(%{"player_id" => player.id}), "/deposit")

    assert html =~ "Deposit Funds"
    assert html =~ to_string(wallet.balance)
    assert has_element?(view, "form[phx-submit=submit_deposit]")
    assert has_element?(view, "input[name=amount][type=number]")
    assert has_element?(view, "button", "Deposit")
  end

  test "submitting the form records a deposit transfer and shows success" do
    player = PageFixtures.player_fixture()
    wallet = PageFixtures.wallet_fixture(player, %{balance: Money.new(:GBP, "100.00")})
    {:ok, view, _html} = live(build_conn_with_trace(%{"player_id" => player.id}), "/deposit")

    html =
      view
      |> form("form", %{"amount" => "100.00"})
      |> render_submit()

    transfer = PageFixtures.transfer_for_wallet(wallet.id)

    assert transfer.reason == "deposit"
    assert transfer.amount == Money.new(:GBP, "100.00")
    assert PageFixtures.normalize_text(html) =~ "Deposit successful"
  end

  test "preview fallback still mounts safely and failed submission shows an error" do
    {:ok, view, html} = live(build_conn_with_trace(), "/deposit")

    assert html =~ "£1,250.00"

    failed_html =
      view
      |> form("form", %{"amount" => "100.00"})
      |> render_submit()

    assert PageFixtures.normalize_text(failed_html) =~ "Deposit failed"
  end
end

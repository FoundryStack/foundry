defmodule IgamingRef.Web.DepositLiveTest do
  use IgamingRef.ConnCase, async: false
  use IgamingRef.DataCase

  require Ash.Query

  import Phoenix.LiveViewTest
  import Foundry.TestScenario

  alias IgamingRef.Finance.LedgerEntry
  alias IgamingRef.PageFixtures

  describe "deposit page" do
    test "mounts with the player's real wallet balance and active form controls" do
      player = PageFixtures.player_fixture()
      wallet = PageFixtures.wallet_fixture(player, %{balance: Money.new(:GBP, "987.65")})

      capture do
        {:ok, view, html} = live(build_conn_with_trace(%{"player_id" => player.id}), "/deposit")

        assert html =~ "Deposit Funds"
        assert html =~ to_string(wallet.balance)
        assert has_element?(view, "form[phx-submit=submit_deposit]")
        assert has_element?(view, "input[name=amount][type=number]")
        assert has_element?(view, "button", "Deposit")
      end
    end

    test "submitting the form records a deposit transfer and shows success" do
      player = PageFixtures.player_fixture()
      wallet = PageFixtures.wallet_fixture(player, %{balance: Money.new(:GBP, "100.00")})

      capture do
        {:ok, view, _html} = live(build_conn_with_trace(%{"player_id" => player.id}), "/deposit")

        html = render_submit(view, "submit_deposit", %{"amount" => "100.00"})
        retry_html = render_submit(view, "submit_deposit", %{"amount" => "100.00"})

        # Verify UI updated: balance re-rendered in the template (proof state changed)
        assert html =~ "£200.00"
        assert retry_html =~ "£200.00"

        # Verify server-side state: transfer created
        transfer = PageFixtures.transfer_for_wallet(wallet.id)
        assert transfer.reason == "deposit"
        assert transfer.amount == Money.new(:GBP, "100.00")
        assert transfer.reference_id

        {:ok, [ledger_entry]} =
          LedgerEntry
          |> Ash.Query.filter(wallet_id: wallet.id, reference_id: transfer.reference_id)
          |> Ash.read(actor: %{is_system: true})

        assert ledger_entry.kind == :deposit
        assert ledger_entry.direction == :credit
        assert ledger_entry.amount == Money.new(:GBP, "100.00")
        assert ledger_entry.idempotency_key == "deposit:#{transfer.reference_id}"

        # Verify server-side state: wallet balance updated in database
        updated_wallet = Ash.get!(IgamingRef.Finance.Wallet, wallet.id, actor: %{is_system: true})
        assert updated_wallet.balance == Money.new(:GBP, "200.00")
      end
    end

    test "preview mode mounts with sample wallet and deposit updates balance" do
      capture do
        {:ok, view, html} = live(build_conn(), "/deposit")

        assert html =~ "£1,250.00"

        html = render_submit(view, "submit_deposit", %{"amount" => "100.00"})

        # Verify UI updated: balance re-rendered with new amount (proof state changed)
        assert html =~ "£1,350.00"
      end
    end

    test "submitting with invalid amount doesn't change balance" do
      player = PageFixtures.player_fixture()
      wallet = PageFixtures.wallet_fixture(player, %{balance: Money.new(:GBP, "100.00")})

      capture do
        {:ok, view, _html} = live(build_conn_with_trace(%{"player_id" => player.id}), "/deposit")

        html = render_submit(view, "submit_deposit", %{"amount" => "abc"})

        # Verify balance still shown as original amount (no state change)
        assert html =~ "£100.00"

        # Verify server-side state: wallet balance unchanged
        updated_wallet = Ash.get!(IgamingRef.Finance.Wallet, wallet.id, actor: %{is_system: true})
        assert updated_wallet.balance == Money.new(:GBP, "100.00")
      end
    end
  end
end

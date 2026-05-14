defmodule IgamingRef.Finance.WithdrawalTransferIntegrationTest do
  use ExUnit.Case, async: false
  use Foundry.TestScenario
  use IgamingRef.DataCase

  import Ecto.Query

  alias IgamingRef.Finance.{LedgerEntry, Wallet, WithdrawalRequest, WithdrawalTransfer}
  alias IgamingRef.Players.Player

  describe "Flow: Player withdrawal request is approved and enters provider processing" do
    @scenario category: :compliance, compliance_links: ["RG-UK-014", "RG-MGA-003", "RG-MGA-007"]

    test "creates, approves, and processes a withdrawal through the provider boundary", context do
      capture(context, fn ->
        {:ok, player} =
          Ash.create(
            Player,
            %{
              email: unique_email(),
              username: unique_username(),
              date_of_birth: ~D[1990-01-01],
              country_code: "GB"
            },
            action: :register
          )

        {:ok, player} =
          player
          |> Ash.Changeset.for_update(
            :update_kyc_status,
            %{kyc_status: :verified, risk_level: :low}
          )
          |> Ash.update(actor: %{is_system: true})

        {:ok, wallet} =
          Ash.create(
            Wallet,
            %{player_id: player.id, currency: "GBP"},
            action: :create,
            actor: %{is_system: true}
          )

        {:ok, wallet} =
          wallet
          |> Ash.Changeset.for_update(:credit, %{amount: Money.new(1_000_00, :GBP)})
          |> Ash.update(actor: %{is_system: true})

        {:ok, withdrawal_request} =
          Ash.create(
            WithdrawalRequest,
            %{
              player_id: player.id,
              wallet_id: wallet.id,
              amount: Money.new(250_00, :GBP)
            },
            action: :create,
            actor: %{id: player.id}
          )

        assert withdrawal_request.status == :pending

        {:ok, approved_request} =
          withdrawal_request
          |> Ash.Changeset.for_update(:approve, %{provider: "stripe"})
          |> Ash.update(actor: %{role: :operator})

        assert approved_request.status == :approved
        assert approved_request.provider == "stripe"

        assert {:ok, processed_request} =
                 Reactor.run(
                   WithdrawalTransfer,
                   %{withdrawal_request_id: approved_request.id, actor: %{is_system: true}},
                   %{},
                   async?: false
                 )

        assert processed_request.status == :processing
        assert processed_request.provider == "stripe"

        assert processed_request.provider_reference ==
                 "stripe-wd-" <> String.slice(approved_request.id, 0, 8)

        {:ok, reloaded_wallet} = Ash.get(Wallet, wallet.id, actor: %{is_system: true})
        assert reloaded_wallet.balance == Money.new(750_00, :GBP)

        ledger_entries =
          LedgerEntry
          |> where([entry], entry.reference_id == ^approved_request.id)
          |> Repo.all()

        assert length(ledger_entries) == 1

        [ledger_entry] = ledger_entries
        assert ledger_entry.wallet_id == wallet.id
        assert ledger_entry.kind == :withdrawal
        assert ledger_entry.direction == :debit
        assert ledger_entry.amount == Money.new(250_00, :GBP)
        assert ledger_entry.idempotency_key == "withdrawal:" <> approved_request.id

        {:ok, reloaded_request} =
          Ash.get(WithdrawalRequest, approved_request.id, actor: %{is_system: true})

        assert reloaded_request.status == :processing
        assert reloaded_request.provider_reference == processed_request.provider_reference
      end)
    end

    test "sums withdrawal totals in the wallet currency", context do
      capture(context, fn ->
        {:ok, player} =
          Ash.create(
            Player,
            %{
              email: unique_email(),
              username: unique_username(),
              date_of_birth: ~D[1990-01-01],
              country_code: "GB"
            },
            action: :register
          )

        {:ok, wallet} =
          Ash.create(
            Wallet,
            %{player_id: player.id, currency: "EUR"},
            action: :create,
            actor: %{is_system: true}
          )

        {:ok, ledger_entry} =
          Ash.create(
            LedgerEntry,
            %{
              wallet_id: wallet.id,
              amount: Money.new(250_00, :EUR),
              direction: :debit,
              kind: :withdrawal,
              idempotency_key: "withdrawal-total-#{wallet.id}",
              reference_id: "withdrawal-total-#{wallet.id}"
            },
            action: :record,
            actor: %{is_system: true}
          )

        assert ledger_entry.amount == Money.new(250_00, :EUR)
        assert WithdrawalTransfer.fetch_daily_withdrawal_total(wallet) == Money.new(250_00, :EUR)
      end)
    end
  end

  defp unique_email do
    "withdrawal_flow_#{System.unique_integer([:positive])}@example.test"
  end

  defp unique_username do
    "withdrawal_flow_#{System.unique_integer([:positive])}"
  end
end

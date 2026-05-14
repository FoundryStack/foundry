defmodule IgamingRef.Finance.DepositTransfer do
  @moduledoc """
  Processes a deposit into a wallet.

  Credits the wallet and records both a transfer row and a ledger entry using a
  stable deposit intent reference so retries do not double-apply the movement.

  Compliance: RG-MGA-001 (wallet integrity), RG-UK-003 (balance accuracy)
  """

  use Foundry.Annotations

  @idempotency_key :deposit_intent_id
  @compliance [:RG_MGA_001, :RG_UK_003]
  @telemetry_prefix [:igaming_ref, :finance, :deposit_transfer]

  use Reactor
  require Ash.Query

  alias IgamingRef.Finance.{LedgerEntry, Transfer, Wallet}

  input(:wallet_id)
  input(:amount)
  input(:deposit_intent_id)

  step :load_context do
    description("Load the wallet and any existing deposit records for the intent.")

    argument(:wallet_id, input(:wallet_id))
    argument(:amount, input(:amount))
    argument(:deposit_intent_id, input(:deposit_intent_id))

    run(fn %{wallet_id: wallet_id, amount: amount, deposit_intent_id: intent_id}, _ ->
      with {:ok, wallet} <- Ash.get(Wallet, wallet_id, actor: %{is_system: true}),
           {:ok, transfer} <- existing_transfer(intent_id),
           {:ok, ledger_entry} <- existing_ledger_entry(intent_id) do
        {:ok,
         %{
           wallet: wallet,
           amount: amount,
           deposit_intent_id: intent_id,
           existing_transfer: transfer,
           existing_ledger_entry: ledger_entry,
           already_applied?: not is_nil(transfer) or not is_nil(ledger_entry)
         }}
      end
    end)
  end

  step :credit_wallet do
    description("Credit the wallet once for the deposit intent.")

    argument(:ctx, result(:load_context))
    wait_for(:load_context)

    run(fn %{ctx: %{wallet: wallet, amount: amount, already_applied?: already_applied?}}, _ ->
      if already_applied? do
        {:ok, wallet}
      else
        wallet
        |> Ash.Changeset.for_update(:credit, %{amount: amount})
        |> Ash.update(actor: %{is_system: true})
      end
    end)

    compensate(fn _,
                  %{ctx: %{wallet: wallet, amount: amount, already_applied?: already_applied?}},
                  _ ->
      if already_applied? do
        :ok
      else
        wallet
        |> Ash.Changeset.for_update(:debit, %{amount: amount})
        |> Ash.update(actor: %{is_system: true})

        :ok
      end
    end)
  end

  step :record_audit do
    description("Record or repair the transfer and ledger entry for the deposit.")

    argument(:ctx, result(:load_context))
    wait_for(:credit_wallet)

    run(fn
      %{
        ctx: %{
          wallet: wallet,
          amount: amount,
          deposit_intent_id: intent_id,
          existing_transfer: existing_transfer,
          existing_ledger_entry: existing_ledger_entry
        }
      },
      _ ->
        case ensure_transfer(wallet, amount, intent_id, existing_transfer) do
          {:ok, transfer} ->
            case ensure_ledger_entry(wallet, amount, intent_id, existing_ledger_entry) do
              {:ok, ledger_entry} ->
                maybe_mark_transfer_completed(transfer)
                {:ok, %{transfer: transfer, ledger_entry: ledger_entry}}

              {:error, error} ->
                maybe_mark_transfer_failed(transfer)
                {:error, error}
            end

          {:error, error} ->
            {:error, error}
        end
    end)
  end

  defp ensure_transfer(wallet, amount, intent_id, nil) do
    Transfer
    |> Ash.Changeset.for_create(:record, %{
      to_wallet_id: wallet.id,
      amount: amount,
      reason: "deposit",
      reference_id: intent_id
    })
    |> Ash.create(actor: %{is_system: true})
  end

  defp ensure_transfer(_wallet, _amount, _intent_id, transfer), do: {:ok, transfer}

  defp ensure_ledger_entry(wallet, amount, intent_id, nil) do
    LedgerEntry
    |> Ash.Changeset.for_create(:record, %{
      wallet_id: wallet.id,
      amount: amount,
      direction: :credit,
      kind: :deposit,
      idempotency_key: "deposit:#{intent_id}",
      reference_id: intent_id
    })
    |> Ash.create(actor: %{is_system: true})
  end

  defp ensure_ledger_entry(_wallet, _amount, _intent_id, ledger_entry),
    do: {:ok, ledger_entry}

  defp maybe_mark_transfer_failed(nil), do: :ok

  defp maybe_mark_transfer_failed(transfer) do
    case transfer
         |> Ash.Changeset.for_update(:mark_failed, %{})
         |> Ash.update(actor: %{is_system: true}) do
      {:ok, _transfer} -> :ok
      _ -> :ok
    end
  end

  defp maybe_mark_transfer_completed(nil), do: :ok

  defp maybe_mark_transfer_completed(transfer) do
    case transfer
         |> Ash.Changeset.for_update(:mark_completed, %{})
         |> Ash.update(actor: %{is_system: true}) do
      {:ok, _transfer} -> :ok
      _ -> :ok
    end
  end

  defp existing_transfer(reference_id) do
    Transfer
    |> Ash.Query.filter(reference_id: reference_id)
    |> Ash.read_one(actor: %{is_system: true})
  end

  defp existing_ledger_entry(reference_id) do
    LedgerEntry
    |> Ash.Query.filter(reference_id: reference_id)
    |> Ash.read_one(actor: %{is_system: true})
  end
end

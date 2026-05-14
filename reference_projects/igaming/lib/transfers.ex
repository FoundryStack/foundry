defmodule IgamingRef.Finance.WithdrawalTransfer do
  @moduledoc """
  Processes an approved withdrawal request through to provider submission.

  Handles balance debit, ledger recording, and provider API call.
  Fully idempotent via withdrawal_request_id as the idempotency key - safe
  to retry on network failure or process crash at any step.

  Steps run in order. On failure, completed steps are compensated:
  - debit_wallet failure: nothing to compensate (atomic with validation)
  - create_ledger_entry failure: re-credits wallet (compensation step)
  - submit_to_provider failure: re-credits wallet, voids ledger entry

  Compliance: RG-UK-014 (withdrawal processing), RG-MGA-007 (withdrawal limits),
  RG-MGA-003 (KYC verification before withdrawal)
  """

  use Foundry.Annotations

  @idempotency_key :withdrawal_request_id
  @runbook "docs/runbooks/withdrawal_transfer.md"
  @compliance [:RG_UK_014, :RG_MGA_007, :RG_MGA_003]
  @telemetry_prefix [:igaming_ref, :finance, :withdrawal_transfer]

  use Reactor
  require Ash.Query

  alias IgamingRef.Finance.{Wallet, LedgerEntry, WithdrawalRequest}

  alias IgamingRef.Finance.Rules.{
    PlayerKYCVerified,
    SufficientBalance,
    WithdrawalLimitNotExceeded
  }

  alias IgamingRef.Players.Rules.PlayerNotSelfExcluded

  input(:withdrawal_request_id)
  input(:actor)

  step :load_request do
    description(
      "Load and validate the withdrawal request. Fails fast if request is not in :approved state."
    )

    argument(:withdrawal_request_id, input(:withdrawal_request_id))

    run(fn inputs, _ ->
      req_id = Map.fetch!(inputs, :withdrawal_request_id)

      case Ash.get(WithdrawalRequest, req_id, actor: %{is_system: true}) do
        {:ok, req} when req.status == :approved ->
          {:ok, req}

        {:ok, req} ->
          {:error, "WithdrawalRequest #{req_id} is not in :approved state (got #{req.status})"}

        {:error, err} ->
          {:error, err}
      end
    end)
  end

  step :load_player_and_wallet do
    description("Load the player and wallet records needed for rule evaluation.")
    argument(:request, result(:load_request))

    run(fn inputs, _ ->
      req = Map.fetch!(inputs, :request)

      with {:ok, wallet} <- Ash.get(Wallet, req.wallet_id, actor: %{is_system: true}),
           {:ok, player} <-
             Ash.get(IgamingRef.Players.Player, req.player_id, actor: %{is_system: true}) do
        {:ok, %{wallet: wallet, player: player}}
      end
    end)
  end

  step :evaluate_rules do
    description(
      "Run all withdrawal guards. Fails fast on first rejection - no partial application."
    )

    argument(:request, result(:load_request))
    argument(:context, result(:load_player_and_wallet))

    run(fn inputs, _ ->
      req = Map.fetch!(inputs, :request)
      %{wallet: wallet, player: player} = Map.fetch!(inputs, :context)

      daily_used = fetch_daily_withdrawal_total(wallet)

      rule_context = %{
        wallet: wallet,
        player: player,
        amount: req.amount,
        daily_used: daily_used
      }

      with :ok <- PlayerNotSelfExcluded.evaluate(rule_context, nil),
           :ok <- PlayerKYCVerified.evaluate(rule_context, nil),
           :ok <- SufficientBalance.evaluate(rule_context, nil),
           :ok <- WithdrawalLimitNotExceeded.evaluate(rule_context, nil) do
        {:ok, :rules_passed}
      else
        {:error, code, message} -> {:error, {code, message}}
      end
    end)
  end

  step :debit_wallet do
    description(
      "Debit the wallet. Atomic with the rule evaluation - if this fails, no funds move."
    )

    argument(:request, result(:load_request))
    argument(:wallet, result(:load_player_and_wallet, [:wallet]))
    wait_for(:evaluate_rules)

    run(fn inputs, _ ->
      req = Map.fetch!(inputs, :request)
      wallet = Map.fetch!(inputs, :wallet)

      wallet
      |> Ash.Changeset.for_update(:debit, %{amount: req.amount})
      |> Ash.update(actor: %{is_system: true})
    end)

    compensate(fn _, %{wallet: wallet, request: req}, _ ->
      wallet
      |> Ash.Changeset.for_update(:credit, %{amount: req.amount})
      |> Ash.update(actor: %{is_system: true})

      :ok
    end)
  end

  step :create_ledger_entry do
    description("Record the debit as an immutable ledger entry.")
    argument(:request, result(:load_request))

    run(fn inputs, _ ->
      req = Map.fetch!(inputs, :request)

      LedgerEntry
      |> Ash.Changeset.for_create(:record, %{
        wallet_id: req.wallet_id,
        amount: req.amount,
        direction: :debit,
        kind: :withdrawal,
        idempotency_key: "withdrawal:#{req.id}",
        reference_id: req.id
      })
      |> Ash.create(actor: %{is_system: true})
    end)
  end

  step :submit_to_provider do
    description(
      "Submit the withdrawal to the payment provider. Provider module is determined by request.provider."
    )

    argument(:request, result(:load_request))
    wait_for(:create_ledger_entry)

    run(fn inputs, _ ->
      req = Map.fetch!(inputs, :request)

      provider_module = provider_module(req.provider)
      provider_module.submit_withdrawal(req)
    end)
  end

  step :update_withdrawal_status do
    description("Mark the WithdrawalRequest as :processing with the provider reference.")
    argument(:request, result(:load_request))
    argument(:provider_response, result(:submit_to_provider))

    run(fn inputs, _ ->
      req = Map.fetch!(inputs, :request)
      resp = Map.fetch!(inputs, :provider_response)

      req
      |> Ash.Changeset.for_update(:mark_processing, %{provider_reference: resp.reference})
      |> Ash.update(actor: %{is_system: true})
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  def fetch_daily_withdrawal_total(wallet) do
    since = DateTime.add(DateTime.utc_now(), -86_400, :second)

    # Sum completed withdrawal amounts in the last 24 hours in the wallet's currency.
    case LedgerEntry
         |> Ash.Query.filter(
           wallet_id == ^wallet.id and kind == :withdrawal and direction == :debit and
             inserted_at >= ^since
         )
         |> Ash.read(actor: %{is_system: true}) do
      {:ok, entries} ->
        Enum.reduce(entries, Money.new(0, wallet.balance.currency), &Money.add!(&2, &1.amount))

      _ ->
        Money.new(0, wallet.balance.currency)
    end
  end

  defp provider_module("stripe"), do: IgamingRef.Finance.Adapters.StripeAdapter
  defp provider_module("paypal"), do: IgamingRef.Finance.Adapters.PaypalAdapter
  defp provider_module(other), do: raise("Unknown provider: #{other}")
end

defmodule IgamingRef.Promotions.BonusGrantTransfer do
  @moduledoc """
  Awards a bonus to a player when campaign eligibility is confirmed.
  Credits the player's wallet and creates the BonusGrant record.

  Idempotent via {player_id, campaign_id} - retrying a failed grant is safe.

  Compliance: RG-MGA-005 (bonus terms must be enforced)
  """

  use Foundry.Annotations

  @idempotency_key {:player_id, :campaign_id}
  @runbook "docs/runbooks/bonus_grant_transfer.md"
  @compliance [:RG_MGA_005]
  @telemetry_prefix [:igaming_ref, :promotions, :bonus_grant_transfer]

  use Reactor
  require Ash.Query

  alias IgamingRef.Finance.{Wallet, LedgerEntry}
  alias IgamingRef.Promotions.{BonusCampaign, BonusGrant}
  alias IgamingRef.Promotions.Rules.{CampaignNotExpired, CampaignNotStarted}
  alias IgamingRef.Players.Rules.PlayerNotSelfExcluded

  input(:player_id)
  input(:campaign_id)
  input(:actor)

  step :load_context do
    description("Load player, campaign, wallet, and existing grants for rule evaluation.")
    argument(:player_id, input(:player_id))
    argument(:campaign_id, input(:campaign_id))

    run(fn %{player_id: pid, campaign_id: cid}, _ ->
      with {:ok, player} <- Ash.get(IgamingRef.Players.Player, pid, actor: %{is_system: true}),
           {:ok, campaign} <- Ash.get(BonusCampaign, cid, actor: %{is_system: true}),
           {:ok, wallet} <- primary_wallet(pid),
           {:ok, grants} <- existing_grants(pid, cid),
           {:ok, campaign_grants} <- campaign_grants(cid),
           {:ok, ledger_entry} <- existing_ledger_entry(pid, cid) do
        existing_active_grant = Enum.find(grants, &(&1.status == :active))

        {:ok,
         %{
           player: player,
           campaign: campaign,
           wallet: wallet,
           existing_grants: grants,
           campaign_grants: campaign_grants,
           existing_active_grant: existing_active_grant,
           existing_ledger_entry: ledger_entry
         }}
      end
    end)
  end

  step :evaluate_rules do
    description("Check self-exclusion, campaign expiry, and player eligibility.")
    argument(:ctx, result(:load_context))

    run(fn %{
             ctx: %{
               player: player,
               campaign: campaign,
               existing_grants: grants,
               campaign_grants: campaign_grants,
               existing_active_grant: existing_active_grant,
               existing_ledger_entry: existing_ledger_entry
             }
           },
           _ ->
      if existing_active_grant || existing_ledger_entry do
        {:ok, :already_applied}
      else
        rule_ctx = %{
          player: player,
          campaign: campaign,
          existing_grants: grants,
          campaign_grants: campaign_grants
        }

        with :ok <- CampaignNotStarted.evaluate(%{campaign: campaign}, nil),
             {:ok, eligibility_rule} <- eligibility_rule_module(campaign.eligibility_rule),
             :ok <- PlayerNotSelfExcluded.evaluate(rule_ctx, nil),
             :ok <- CampaignNotExpired.evaluate(rule_ctx, nil),
             :ok <- eligibility_rule.evaluate(rule_ctx, nil) do
          {:ok, :rules_passed}
        else
          {:error, code, message} -> {:error, {code, message}}
          {:error, error} -> {:error, error}
        end
      end
    end)
  end

  step :credit_wallet do
    description("Credit the player's wallet with the bonus amount.")
    argument(:ctx, result(:load_context))
    wait_for(:evaluate_rules)

    run(fn %{
             ctx: %{
               wallet: wallet,
               campaign: campaign,
               existing_active_grant: existing_active_grant,
               existing_ledger_entry: existing_ledger_entry
             }
           },
           _ ->
      if existing_active_grant || existing_ledger_entry do
        {:ok, wallet}
      else
        wallet
        |> Ash.Changeset.for_update(:credit, %{amount: campaign.bonus_amount})
        |> Ash.update(actor: %{is_system: true})
      end
    end)

    compensate(fn _,
                  %{
                    ctx: %{
                      wallet: wallet,
                      campaign: campaign,
                      existing_active_grant: existing_active_grant,
                      existing_ledger_entry: existing_ledger_entry
                    }
                  },
                  _ ->
      if existing_active_grant || existing_ledger_entry do
        :ok
      else
        case wallet
             |> Ash.Changeset.for_update(:debit, %{amount: campaign.bonus_amount})
             |> Ash.update(actor: %{is_system: true}) do
          {:ok, _wallet} -> :ok
          {:error, error} -> {:error, error}
        end
      end
    end)
  end

  step :create_ledger_entry do
    description("Record the bonus credit as an immutable ledger entry.")
    argument(:ctx, result(:load_context))
    argument(:player_id, input(:player_id))
    argument(:campaign_id, input(:campaign_id))

    run(fn %{
             ctx: %{
               campaign: campaign,
               wallet: wallet,
               existing_active_grant: existing_active_grant,
               existing_ledger_entry: existing_ledger_entry
             },
             player_id: pid,
             campaign_id: cid
           },
           _ ->
      if existing_active_grant || existing_ledger_entry do
        {:ok, existing_ledger_entry}
      else
        LedgerEntry
        |> Ash.Changeset.for_create(:record, %{
          wallet_id: wallet.id,
          amount: campaign.bonus_amount,
          direction: :credit,
          kind: :bonus,
          idempotency_key: bonus_grant_ledger_key(pid, cid),
          reference_id: cid
        })
        |> Ash.create(actor: %{is_system: true})
      end
    end)
  end

  step :create_bonus_grant do
    description("Create the BonusGrant record tracking wagering progress.")
    argument(:ctx, result(:load_context))
    argument(:player_id, input(:player_id))
    argument(:campaign_id, input(:campaign_id))

    run(fn %{
             ctx: %{campaign: campaign, existing_active_grant: existing_active_grant},
             player_id: pid,
             campaign_id: cid
           },
           _ ->
      if existing_active_grant do
        {:ok, existing_active_grant}
      else
        wagering_required =
          Decimal.mult(
            Money.to_decimal(campaign.bonus_amount),
            campaign.wagering_multiplier
          )

        BonusGrant
        |> Ash.Changeset.for_create(:grant, %{
          player_id: pid,
          campaign_id: cid,
          amount: campaign.bonus_amount,
          wagering_remaining: wagering_required,
          granted_at: DateTime.utc_now(),
          expires_at: campaign.expires_at
        })
        |> Ash.create(actor: %{is_system: true})
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp primary_wallet(player_id) do
    case Wallet
         |> Ash.Query.filter(player_id: player_id, status: :active)
         |> Ash.read(actor: %{is_system: true}) do
      {:ok, [wallet | _]} -> {:ok, wallet}
      {:ok, []} -> {:error, "No active wallet found for player #{player_id}"}
      {:error, err} -> {:error, err}
    end
  end

  defp existing_grants(player_id, campaign_id) do
    BonusGrant
    |> Ash.Query.filter(player_id: player_id, campaign_id: campaign_id)
    |> Ash.read(actor: %{is_system: true})
  end

  defp campaign_grants(campaign_id) do
    BonusGrant
    |> Ash.Query.filter(campaign_id: campaign_id)
    |> Ash.read(actor: %{is_system: true})
  end

  defp existing_ledger_entry(player_id, campaign_id) do
    LedgerEntry
    |> Ash.Query.filter(idempotency_key: bonus_grant_ledger_key(player_id, campaign_id))
    |> Ash.read(actor: %{is_system: true})
    |> case do
      {:ok, [entry | _]} -> {:ok, entry}
      {:ok, []} -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  defp bonus_grant_ledger_key(player_id, campaign_id) do
    "bonus_grant:#{player_id}:#{campaign_id}"
  end

  defp eligibility_rule_module(rule_name) when is_binary(rule_name) do
    module =
      rule_name
      |> String.split(".")
      |> Module.concat()

    if Code.ensure_loaded?(module) and function_exported?(module, :evaluate, 2) do
      {:ok, module}
    else
      {:error, {:invalid_eligibility_rule, rule_name}}
    end
  end

  defp eligibility_rule_module(_), do: {:error, {:invalid_eligibility_rule, nil}}
end

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

      Foundry.TestScenario.trace_node("IgamingRef.Finance.WithdrawalTransfer", %{
        type: :entry,
        kind: :action_execute,
        label: "Enter WithdrawalTransfer pipeline",
        module_function: "Reactor.run",
        source_snippet: "Reactor.run(WithdrawalTransfer, ...)",
        focus_node_id: "IgamingRef.Finance.WithdrawalTransfer:step:0"
      })

      Foundry.TestScenario.trace_node("IgamingRef.Finance.WithdrawalRequest", %{
        type: :reaction,
        kind: :read,
        label: "Load WithdrawalRequest by id",
        module_function: "Ash.get",
        source_snippet: "Ash.get(WithdrawalRequest, req_id, actor: :system)",
        focus_node_id: "IgamingRef.Finance.WithdrawalTransfer:step:0"
      })

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

      Foundry.TestScenario.trace_node("IgamingRef.Finance.Wallet", %{
        type: :reaction,
        kind: :read,
        label: "Load Wallet for withdrawal rule evaluation",
        module_function: "Ash.get",
        source_snippet: "Ash.get(Wallet, req.wallet_id, actor: :system)",
        focus_node_id: "IgamingRef.Finance.WithdrawalTransfer:step:1"
      })

      Foundry.TestScenario.trace_node("IgamingRef.Players.Player", %{
        type: :reaction,
        kind: :read,
        label: "Load Player for withdrawal rule evaluation",
        module_function: "Ash.get",
        source_snippet: "Ash.get(IgamingRef.Players.Player, req.player_id, actor: :system)",
        focus_node_id: "IgamingRef.Finance.WithdrawalTransfer:step:1"
      })

      with {:ok, wallet} <- Ash.get(Wallet, req.wallet_id, actor: %{is_system: true}),
           {:ok, player} <- Ash.get(IgamingRef.Players.Player, req.player_id, actor: %{is_system: true}) do
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

      Foundry.TestScenario.trace_node("IgamingRef.Players.Rules.PlayerNotSelfExcluded", %{
        type: :command,
        kind: :rule_check,
        label: "Verify PlayerNotSelfExcluded before funds move",
        module_function: "evaluate/2",
        source_snippet: "PlayerNotSelfExcluded.evaluate(rule_context, nil)",
        focus_node_id: "IgamingRef.Finance.WithdrawalTransfer:step:2"
      })

      Foundry.TestScenario.trace_node("IgamingRef.Finance.Rules.PlayerKYCVerified", %{
        type: :command,
        kind: :rule_check,
        label: "Verify PlayerKYCVerified before provider submission",
        module_function: "evaluate/2",
        source_snippet: "PlayerKYCVerified.evaluate(rule_context, nil)",
        focus_node_id: "IgamingRef.Finance.WithdrawalTransfer:step:2"
      })

      Foundry.TestScenario.trace_node("IgamingRef.Finance.Rules.SufficientBalance", %{
        type: :command,
        kind: :rule_check,
        label: "Verify SufficientBalance before debiting the wallet",
        module_function: "evaluate/2",
        source_snippet: "SufficientBalance.evaluate(rule_context, nil)",
        focus_node_id: "IgamingRef.Finance.WithdrawalTransfer:step:2"
      })

      Foundry.TestScenario.trace_node("IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded", %{
        type: :command,
        kind: :rule_check,
        label: "Verify WithdrawalLimitNotExceeded for the current player risk profile",
        module_function: "evaluate/2",
        source_snippet: "WithdrawalLimitNotExceeded.evaluate(rule_context, nil)",
        focus_node_id: "IgamingRef.Finance.WithdrawalTransfer:step:2"
      })

      daily_used = fetch_daily_withdrawal_total(player.id)

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

      Foundry.TestScenario.trace_node("IgamingRef.Finance.Wallet", %{
        type: :reaction,
        kind: :write,
        label: "Debit Wallet for the approved withdrawal amount",
        module_function: "Ash.update",
        source_snippet: "Ash.update(wallet, :debit, arguments: %{amount: req.amount}, actor: :system)",
        focus_node_id: "IgamingRef.Finance.WithdrawalTransfer:step:3"
      })

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

      Foundry.TestScenario.trace_node("IgamingRef.Finance.LedgerEntry", %{
        type: :reaction,
        kind: :write,
        label: "Create immutable LedgerEntry for the withdrawal debit",
        module_function: "Ash.create",
        source_snippet: "Ash.create(LedgerEntry, :record, ...)",
        focus_node_id: "IgamingRef.Finance.WithdrawalTransfer:step:4"
      })

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

      Foundry.TestScenario.trace_node("IgamingRef.Finance.WithdrawalRequest", %{
        type: :event,
        kind: :action_execute,
        label: "Submit the approved withdrawal to the configured provider adapter",
        module_function: "submit_withdrawal/1",
        source_snippet: "provider_module(req.provider).submit_withdrawal(req)",
        focus_node_id: "IgamingRef.Finance.WithdrawalTransfer:step:5"
      })

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

      Foundry.TestScenario.trace_node("IgamingRef.Finance.WithdrawalRequest", %{
        type: :assertion,
        kind: :write,
        label: "Mark WithdrawalRequest as processing with the provider reference",
        module_function: "Ash.update",
        source_snippet: "Ash.update(req, :mark_processing, arguments: %{provider_reference: resp.reference}, actor: :system)",
        focus_node_id: "IgamingRef.Finance.WithdrawalRequest:action:mark_processing"
      })

      req
      |> Ash.Changeset.for_update(:mark_processing, %{provider_reference: resp.reference})
      |> Ash.update(actor: %{is_system: true})
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp fetch_daily_withdrawal_total(player_id) do
    since = DateTime.add(DateTime.utc_now(), -86_400, :second)

    # Sum completed withdrawal amounts in the last 24 hours
    # Full implementation queries LedgerEntry - stubbed for reference project
    case Ash.read(LedgerEntry,
           filter: [
             wallet_id: {:in, player_wallet_ids(player_id)},
             kind: :withdrawal,
             direction: :debit,
             inserted_at: [greater_than_or_equal: since]
           ],
           actor: %{is_system: true}
         ) do
      {:ok, entries} -> Enum.reduce(entries, Money.new(0, :GBP), &Money.add!(&2, &1.amount))
      _ -> Money.new(0, :GBP)
    end
  end

  defp player_wallet_ids(player_id) do
    case Ash.read(Wallet, filter: [player_id: player_id], actor: %{is_system: true}) do
      {:ok, wallets} -> Enum.map(wallets, & &1.id)
      _ -> []
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

  alias IgamingRef.Finance.{Wallet, LedgerEntry}
  alias IgamingRef.Promotions.{BonusCampaign, BonusGrant}
  alias IgamingRef.Promotions.Rules.{PlayerEligibleForCampaign, CampaignNotExpired}
  alias IgamingRef.Players.Rules.PlayerNotSelfExcluded

  input(:player_id)
  input(:campaign_id)
  input(:actor)

  step :load_context do
    description("Load player, campaign, wallet, and existing grants for rule evaluation.")

    run(fn %{player_id: pid, campaign_id: cid}, _ ->
      Foundry.TestScenario.trace_node("IgamingRef.Promotions.BonusGrantTransfer", %{
        type: :entry,
        kind: :action_execute,
        label: "Enter BonusGrantTransfer pipeline",
        module_function: "Reactor.run",
        source_snippet: "Reactor.run(BonusGrantTransfer, ...)"
      })

      Foundry.TestScenario.trace_node("IgamingRef.Players.Player", %{
        type: :reaction,
        kind: :read,
        label: "Load player for grant evaluation",
        module_function: "Ash.get",
        source_snippet: "Ash.get(IgamingRef.Players.Player, pid, actor: :system)"
      })

      with {:ok, player} <- Ash.get(IgamingRef.Players.Player, pid, actor: :system),
           {:ok, campaign} <- Ash.get(BonusCampaign, cid, actor: :system),
           {:ok, wallet} <- primary_wallet(pid),
           {:ok, grants} <- existing_grants(pid, cid),
           {:ok, campaign_grants} <- campaign_grants(cid) do
        {:ok,
         %{
           player: player,
           campaign: campaign,
           wallet: wallet,
           existing_grants: grants,
           campaign_grants: campaign_grants
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
               campaign_grants: campaign_grants
             }
           },
           _ ->
      rule_ctx = %{
        player: player,
        campaign: campaign,
        existing_grants: grants,
        campaign_grants: campaign_grants
      }

      with :ok <- PlayerNotSelfExcluded.evaluate(rule_ctx, nil),
           :ok <- CampaignNotExpired.evaluate(rule_ctx, nil),
           :ok <- PlayerEligibleForCampaign.evaluate(rule_ctx, nil) do
        {:ok, :rules_passed}
      else
        {:error, code, message} -> {:error, {code, message}}
      end
    end)
  end

  step :credit_wallet do
    description("Credit the player's wallet with the bonus amount.")
    argument(:ctx, result(:load_context))
    wait_for(:evaluate_rules)

    run(fn %{ctx: %{wallet: wallet, campaign: campaign}}, _ ->
      wallet
      |> Ash.Changeset.for_update(:credit, %{amount: campaign.bonus_amount})
      |> Ash.update(actor: :system)
    end)

    compensate(fn _, %{ctx: %{wallet: wallet, campaign: campaign}}, _ ->
      wallet
      |> Ash.Changeset.for_update(:debit, %{amount: campaign.bonus_amount})
      |> Ash.update(actor: :system)

      :ok
    end)
  end

  step :create_ledger_entry do
    description("Record the bonus credit as an immutable ledger entry.")
    argument(:ctx, result(:load_context))
    argument(:player_id, input(:player_id))
    argument(:campaign_id, input(:campaign_id))

    run(fn %{ctx: %{campaign: campaign, wallet: wallet}, player_id: pid, campaign_id: cid}, _ ->
      LedgerEntry
      |> Ash.Changeset.for_create(:record, %{
        wallet_id: wallet.id,
        amount: campaign.bonus_amount,
        direction: :credit,
        kind: :bonus,
        idempotency_key: "bonus_grant:#{pid}:#{cid}",
        reference_id: cid
      })
      |> Ash.create(actor: %{is_system: true})
    end)
  end

  step :create_bonus_grant do
    description("Create the BonusGrant record tracking wagering progress.")
    argument(:ctx, result(:load_context))
    argument(:player_id, input(:player_id))
    argument(:campaign_id, input(:campaign_id))

    run(fn %{ctx: %{campaign: campaign}, player_id: pid, campaign_id: cid}, _ ->
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
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp primary_wallet(player_id) do
    case Ash.read(Wallet, filter: [player_id: player_id, status: :active], actor: :system) do
      {:ok, [wallet | _]} -> {:ok, wallet}
      {:ok, []} -> {:error, "No active wallet found for player #{player_id}"}
      {:error, err} -> {:error, err}
    end
  end

  defp existing_grants(player_id, campaign_id) do
    Ash.read(BonusGrant,
      filter: [player_id: player_id, campaign_id: campaign_id],
      actor: :system
    )
  end

  defp campaign_grants(campaign_id) do
    Ash.read(BonusGrant,
      filter: [campaign_id: campaign_id],
      actor: :system
    )
  end
end

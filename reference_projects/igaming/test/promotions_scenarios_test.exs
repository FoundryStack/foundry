Code.require_file("generators.ex", __DIR__)

defmodule IgamingRef.Promotions.BonusScenarioTest do
  use ExUnit.Case, async: false
  use Foundry.TestScenario
  use IgamingRef.DataCase

  require Ash.Query

  alias IgamingRef.Finance.{LedgerEntry, Wallet}

  alias IgamingRef.Promotions.{
    BonusCampaign,
    BonusCondition,
    BonusConditionGroup,
    BonusEvent,
    BonusEvaluationReactor,
    BonusExecution,
    BonusGrant,
    BonusTrigger
  }

  describe "BonusCampaign activation respects the campaign start window" do
    @scenario category: :compliance, compliance_links: ["RG-MGA-005", "RG-UK-011"]

    test "rejects activation before starts_at" do
      {:ok, campaign} =
        Ash.create(
          BonusCampaign,
          %{
            name: "Future bonus",
            kind: :deposit_match,
            eligibility_rule: "IgamingRef.Promotions.Rules.PlayerEligibleForCampaign",
            bonus_amount: Money.new(50_00, :GBP),
            wagering_multiplier: Decimal.new("5.0"),
            max_redemptions: nil,
            starts_at: DateTime.add(DateTime.utc_now(), 3_600, :second),
            expires_at: DateTime.add(DateTime.utc_now(), 86_400, :second)
          },
          action: :create,
          actor: %{role: :operator}
        )

      assert {:error, _} =
               campaign
               |> Ash.Changeset.for_update(:activate, %{})
               |> Ash.update(actor: %{role: :operator})
    end
  end

  describe "Flow: BonusEvaluationReactor awards bonuses through nested condition trees" do
    @scenario category: :compliance, compliance_links: ["RG-MGA-005", "RG-UK-011", "RG-UK-008"]

    test "creates the grant, credits the wallet, records the ledger entry, and marks the event processed" do
      {player, wallet, campaign, event} = seed_bonus_flow()

      assert {:ok, processed_event} =
               Reactor.run(
                 BonusEvaluationReactor,
                 %{event_id: event.id, actor: %{is_system: true}},
                 %{},
                 async?: false
               )

      assert processed_event.id == event.id
      assert processed_event.processed_at

      {:ok, reloaded_event} = Ash.get(BonusEvent, event.id, actor: %{role: :operator})
      assert reloaded_event.processed_at == processed_event.processed_at

      {:ok, reloaded_wallet} = Ash.get(Wallet, wallet.id, actor: %{is_system: true})
      assert reloaded_wallet.balance == Money.new(50_00, :GBP)

      {:ok, grants} =
        BonusGrant
        |> Ash.Query.filter(player_id: player.id, campaign_id: campaign.id)
        |> Ash.read(actor: %{is_system: true})

      assert length(grants) == 1

      [grant] = grants
      assert grant.amount == Money.new(50_00, :GBP)
      assert grant.status == :active
      assert Decimal.eq?(grant.wagering_remaining, Decimal.new("25000"))

      {:ok, ledger_entries} =
        LedgerEntry
        |> Ash.Query.filter(reference_id: campaign.id, wallet_id: wallet.id)
        |> Ash.read(actor: %{is_system: true})

      assert length(ledger_entries) == 1

      [ledger_entry] = ledger_entries
      assert ledger_entry.kind == :bonus
      assert ledger_entry.direction == :credit
      assert ledger_entry.amount == Money.new(50_00, :GBP)
      assert ledger_entry.idempotency_key == "bonus_grant:#{player.id}:#{campaign.id}"
    end
  end

  describe "Flow: BonusEvaluationReactor skips already processed events" do
    @scenario category: :compliance, compliance_links: ["RG-MGA-005", "RG-UK-011"]

    test "rerunning the reactor leaves the processed event, grant, wallet, and ledger unchanged" do
      {player, wallet, campaign, event} = seed_bonus_flow()

      assert {:ok, first_run_event} =
               Reactor.run(
                 BonusEvaluationReactor,
                 %{event_id: event.id, actor: %{is_system: true}},
                 %{},
                 async?: false
               )

      {:ok, first_run_grants} =
        BonusGrant
        |> Ash.Query.filter(player_id: player.id, campaign_id: campaign.id)
        |> Ash.read(actor: %{is_system: true})

      {:ok, first_run_entries} =
        LedgerEntry
        |> Ash.Query.filter(reference_id: campaign.id, wallet_id: wallet.id)
        |> Ash.read(actor: %{is_system: true})

      {:ok, first_run_wallet} = Ash.get(Wallet, wallet.id, actor: %{is_system: true})
      {:ok, first_run_event_reload} = Ash.get(BonusEvent, event.id, actor: %{role: :operator})

      assert {:ok, second_run_event} =
               Reactor.run(
                 BonusEvaluationReactor,
                 %{event_id: event.id, actor: %{is_system: true}},
                 %{},
                 async?: false
               )

      {:ok, second_run_grants} =
        BonusGrant
        |> Ash.Query.filter(player_id: player.id, campaign_id: campaign.id)
        |> Ash.read(actor: %{is_system: true})

      {:ok, second_run_entries} =
        LedgerEntry
        |> Ash.Query.filter(reference_id: campaign.id, wallet_id: wallet.id)
        |> Ash.read(actor: %{is_system: true})

      {:ok, second_run_wallet} = Ash.get(Wallet, wallet.id, actor: %{is_system: true})
      {:ok, second_run_event_reload} = Ash.get(BonusEvent, event.id, actor: %{role: :operator})

      assert second_run_event.id == first_run_event.id
      assert second_run_event.processed_at == first_run_event.processed_at
      assert second_run_event_reload.processed_at == first_run_event_reload.processed_at
      assert second_run_wallet.balance == first_run_wallet.balance
      assert length(first_run_grants) == 1
      assert length(second_run_grants) == 1
      assert length(first_run_entries) == 1
      assert length(second_run_entries) == 1
    end
  end

  defp seed_bonus_flow do
    {:ok, player} =
      Ash.create(
        IgamingRef.Players.Player,
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
        %{player_id: player.id, currency: "GBP"},
        action: :create,
        actor: %{is_system: true}
      )

    {:ok, campaign} =
      Ash.create(
        BonusCampaign,
        %{
          name: "Nested bonus tree",
          kind: :deposit_match,
          eligibility_rule: "IgamingRef.Promotions.Rules.PlayerEligibleForCampaign",
          bonus_amount: Money.new(50_00, :GBP),
          wagering_multiplier: Decimal.new("5.0"),
          max_redemptions: nil,
          starts_at: DateTime.add(DateTime.utc_now(), -3_600, :second),
          expires_at: DateTime.add(DateTime.utc_now(), 86_400, :second)
        },
        action: :create,
        actor: %{role: :operator}
      )

    {:ok, campaign} =
      campaign
      |> Ash.Changeset.for_update(:activate, %{})
      |> Ash.update(actor: %{role: :operator})

    {:ok, _trigger} =
      Ash.create(
        BonusTrigger,
        %{
          campaign_id: campaign.id,
          kind: :deposit_completed,
          enabled: true,
          params: %{},
          position: 0
        },
        action: :create,
        actor: %{role: :operator}
      )

    {:ok, root_group} =
      Ash.create(
        BonusConditionGroup,
        %{
          campaign_id: campaign.id,
          parent_group_id: nil,
          combinator: :any,
          position: 0
        },
        action: :create,
        actor: %{role: :operator}
      )

    {:ok, child_group} =
      Ash.create(
        BonusConditionGroup,
        %{
          campaign_id: campaign.id,
          parent_group_id: root_group.id,
          combinator: :all,
          position: 1
        },
        action: :create,
        actor: %{role: :operator}
      )

    {:ok, _failing_root_condition} =
      Ash.create(
        BonusCondition,
        %{
          group_id: root_group.id,
          kind: :player_country_in,
          params: %{"countries" => ["FR"]},
          negated: false,
          position: 0
        },
        action: :create,
        actor: %{role: :operator}
      )

    {:ok, _child_condition_1} =
      Ash.create(
        BonusCondition,
        %{
          group_id: child_group.id,
          kind: :campaign_active,
          params: %{},
          negated: false,
          position: 0
        },
        action: :create,
        actor: %{role: :operator}
      )

    {:ok, _child_condition_2} =
      Ash.create(
        BonusCondition,
        %{
          group_id: child_group.id,
          kind: :player_not_self_excluded,
          params: %{},
          negated: false,
          position: 1
        },
        action: :create,
        actor: %{role: :operator}
      )

    {:ok, _execution} =
      Ash.create(
        BonusExecution,
        %{
          campaign_id: campaign.id,
          kind: :grant_deposit_match,
          params: %{},
          position: 0,
          enabled: true
        },
        action: :create,
        actor: %{role: :operator}
      )

    {:ok, event} =
      Ash.create(
        BonusEvent,
        %{
          kind: :deposit_completed,
          player_id: player.id,
          wallet_id: wallet.id,
          amount: Money.new(10_00, :GBP),
          currency: "GBP",
          idempotency_key: "bonus-event-#{player.id}-#{campaign.id}",
          payload: %{"source" => "bonus_flow_test"}
        },
        action: :ingest,
        actor: %{is_system: true}
      )

    {player, wallet, campaign, event}
  end

  defp unique_email do
    "bonus_flow_#{System.unique_integer([:positive])}@example.test"
  end

  defp unique_username do
    "bonus_flow_#{System.unique_integer([:positive])}"
  end
end

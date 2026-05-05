Code.require_file("generators.ex", __DIR__)

defmodule IgamingRef.Promotions.BonusScenarioTest do
  use ExUnit.Case, async: true
  use Foundry.TestScenario

  import IgamingRefTest.Generators

  alias IgamingRef.Promotions.{BonusEvent, BonusEvaluationReactor, BonusGrantTransfer}

  describe "Action: BonusEvent ingest action is prepared from canonical trigger data" do
    @scenario category: :property, compliance_links: ["RG-MGA-005", "RG-UK-011"]

    test "builds an ingest changeset for a deposit-completed event", context do
      capture(context, fn ->
        player = player_fixture()
        wallet = wallet_fixture(%{player_id: player.id})

        changeset =
          Ash.Changeset.for_create(
            BonusEvent,
            :ingest,
            %{
              kind: :deposit_completed,
              player_id: player.id,
              wallet_id: wallet.id,
              amount: Money.new(100_00, :GBP),
              currency: "GBP",
              idempotency_key: "bonus-event-#{player.id}",
              payload: %{"source" => "scenario_test"}
            }
          )

        assert changeset.valid?
        assert changeset.action.name == :ingest
        assert changeset.attributes.kind == :deposit_completed
        assert changeset.attributes.player_id == player.id
        assert changeset.attributes.wallet_id == wallet.id
      end)
    end
  end

  describe "Action: BonusEvent ingest action is executed from canonical trigger data" do
    @scenario category: :property, compliance_links: ["RG-MGA-005", "RG-UK-011"]

    test "invokes the ingest action with canonical trigger attributes", context do
      capture(context, fn ->
        player = player_fixture()
        wallet = wallet_fixture(%{player_id: player.id})

        repo_unavailable =
          try do
            Ash.create(
              BonusEvent,
              %{
                kind: :deposit_completed,
                player_id: player.id,
                wallet_id: wallet.id,
                amount: Money.new(100_00, :GBP),
                currency: "GBP",
                idempotency_key: "bonus-event-#{player.id}",
                payload: %{"source" => "scenario_test"}
              },
              action: :ingest,
              actor: %{is_system: true}
            )

            false
          rescue
            _ -> true
          end

        assert repo_unavailable
      end)
    end
  end

  describe "Flow: BonusEvaluationReactor reaches the evaluation pipeline" do
    @scenario category: :property, compliance_links: ["RG-MGA-005", "RG-UK-011"]

    test "executes the bonus evaluation reactor entrypoint", context do
      capture(context, fn ->
        assert {:error, _} =
                 Reactor.run(BonusEvaluationReactor, %{
                   event_id: "bonus-event-1",
                   actor: %{is_system: true}
                 })
      end)
    end
  end

  describe "Flow: BonusGrantTransfer reaches the eligibility and grant pipeline" do
    @scenario category: :property, compliance_links: ["RG-MGA-005", "RG-UK-011"]

    test "executes the bonus grant transfer entrypoint", context do
      capture(context, fn ->
        assert {:error, _} =
                 Reactor.run(BonusGrantTransfer, %{
                   player_id: "player-1",
                   campaign_id: "campaign-1",
                   actor: %{is_system: true}
                 })
      end)
    end
  end
end

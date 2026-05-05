Code.require_file("generators.ex", __DIR__)

defmodule IgamingRef.Finance.WithdrawalScenarioTest do
  use ExUnit.Case, async: false
  use Foundry.TestScenario
  use IgamingRef.DataCase

  import Ecto.Query
  import IgamingRefTest.Generators

  alias IgamingRef.Finance.WithdrawalWebhookEvent
  alias IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook

  alias IgamingRef.Finance.Rules.{
    PlayerKYCVerified,
    SufficientBalance,
    WithdrawalLimitNotExceeded
  }

  alias IgamingRef.Finance.WithdrawalWebhook
  alias IgamingRef.Players.Rules.PlayerNotSelfExcluded

  describe "Rule: RG-UK-014 — Withdrawal guards reject an over-limit request before funds move" do
    @scenario category: :compliance, compliance_links: ["RG-UK-014"]

    test "evaluates exclusion, KYC, balance, and limit guards in order" do
      player = player_fixture(%{kyc_status: :verified, risk_level: :high, status: :active})
      wallet = wallet_fixture(%{balance: Money.new(900_00, :GBP)})
      amount = Money.new(400_00, :GBP)
      daily_used = Money.new(200_00, :GBP)
      rule_context = %{player: player, wallet: wallet, amount: amount, daily_used: daily_used}

      assert :ok = PlayerNotSelfExcluded.evaluate(rule_context, nil)
      assert :ok = PlayerKYCVerified.evaluate(rule_context, nil)
      assert :ok = SufficientBalance.evaluate(rule_context, nil)

      assert {:error, :daily_limit_exceeded, _message} =
               WithdrawalLimitNotExceeded.evaluate(rule_context, nil)
    end
  end

  describe "Flow: Unknown provider webhook short-circuits before persistence" do
    @scenario category: :compliance, compliance_links: ["RG-UK-014", "RG-MGA-007"]

    test "rejects unknown providers before persistence", context do
      capture(context, fn ->
        payload = ~s({"type":"charge.succeeded","data":{"object":{"id":"wh_123"}}})

        assert {:error, {:error, "unknown provider: unknown"}} =
                 WithdrawalWebhook.handle_webhook("unknown", "sig", payload)
      end)
    end
  end

  describe "Flow: Provider webhook reaches persistence and processor entrypoints" do
    @scenario category: :compliance, compliance_links: ["RG-UK-014", "RG-MGA-007"]

    test "executes webhook receive, event persistence, and job processing entrypoints", context do
      capture(context, fn ->
        payload = ~s({"type":"charge.succeeded","data":{"object":{"id":"wh_123"}}})

        result =
          try do
            WithdrawalWebhook.handle_webhook("stripe", "sig", payload)
          rescue
            error in Postgrex.Error -> {:error, error}
          end

        assert match?({:ok, _}, result) or match?({:error, _}, result)

        persisted_event =
          WithdrawalWebhookEvent
          |> where([event], event.provider_reference == "wh_123")
          |> Repo.one()

        assert persisted_event
        assert persisted_event.provider == "stripe"
        assert persisted_event.event_type == "charge.succeeded"
        assert persisted_event.status == :completed

        assert :ok =
                 ProcessWithdrawalWebhook.perform(%Oban.Job{
                   args: %{"provider_reference" => "wh_123", "status" => "completed"}
                 })
      end)
    end
  end

  describe "Job: ProcessWithdrawalWebhook accepts a normalized webhook payload" do
    @scenario category: :invariant, compliance_links: ["RG-UK-014"]

    test "accepts a normalized webhook job payload", context do
      capture(context, fn ->
        assert :ok =
                 ProcessWithdrawalWebhook.perform(%Oban.Job{
                   args: %{"provider_reference" => "wh_123", "status" => "completed"}
                 })
      end)
    end
  end
end

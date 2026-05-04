defmodule IgamingRef.Finance.WithdrawalScenarioTest do
  use ExUnit.Case, async: true

  describe "RG-UK-014 — Withdrawal within limit proceeds to review" do
    @moduletag category: :compliance
    @moduletag compliance_links: ["RG-UK-014"]
    @moduletag nodes: [
      "Finance.WithdrawalTransfer",
      "Finance.Rules.WithdrawalLimitNotExceeded",
      "Players.Player",
      "Finance.Wallet"
    ]
    @moduletag graph_path: [
      "Players.Player",
      "Finance.WithdrawalTransfer",
      "Finance.Rules.WithdrawalLimitNotExceeded",
      "Finance.Wallet"
    ]
    @moduletag steps: %{
      given: [
        "A player with KYC-verified status",
        "A wallet with balance >= withdrawal amount",
        "The player is not self-excluded"
      ],
      when: ["The player requests a withdrawal within their daily limit"],
      then: [
        "The withdrawal request is created in :pending state",
        "The player balance is not yet debited",
        "A compliance audit event is logged"
      ]
    }

    test "creates withdrawal request in pending state" do
      :ok
    end
  end

  describe "RG-MGA-007 — KYC required before withdrawal" do
    @moduletag category: :compliance
    @moduletag compliance_links: ["RG-MGA-007"]
    @moduletag nodes: ["Players.Player", "Finance.WithdrawalTransfer"]
    @moduletag graph_path: ["Players.Player", "Finance.WithdrawalTransfer"]
    @moduletag steps: %{
      given: [
        "A player with pending KYC status"
      ],
      when: ["The player requests a withdrawal"],
      then: [
        "The withdrawal is rejected",
        "The player sees 'KYC verification required' message"
      ]
    }

    test "rejects withdrawal without KYC" do
      :ok
    end
  end

  describe "Sufficient Balance — rejects when exceeds" do
    @moduletag category: :invariant
    @moduletag nodes: ["Finance.WithdrawalTransfer", "Finance.Rules.SufficientBalance"]
    @moduletag graph_path: [
      "Finance.WithdrawalTransfer",
      "Finance.Rules.SufficientBalance",
      "Finance.Wallet"
    ]
    @moduletag steps: %{
      given: [
        "A wallet with balance £500"
      ],
      when: ["A withdrawal of £600 is requested"],
      then: [
        "The withdrawal is rejected",
        "The balance remains £500"
      ]
    }

    test "balance invariant holds" do
      :ok
    end
  end
end

defmodule IgamingRef.Finance.BonusScenarioTest do
  use ExUnit.Case, async: true

  describe "Wagering requirement state machine" do
    @moduletag category: :state_machine
    @moduletag nodes: ["Finance.Bonus", "Finance.WageringRequirement"]
    @moduletag graph_path: ["Finance.Bonus", "Finance.WageringRequirement"]
    @moduletag steps: %{
      given: [
        "A bonus with a £10 wagering requirement"
      ],
      when: [
        "Player completes £5 worth of qualifying bets",
        "Player completes another £5 of qualifying bets"
      ],
      then: [
        "Bonus progresses through pending → in_progress → completed states",
        "Wagering requirement reaches 100%"
      ]
    }

    test "wagering requirement progresses correctly" do
      :ok
    end
  end

  describe "Property: Bonus value never exceeds deposit" do
    @moduletag category: :property
    @moduletag nodes: ["Finance.Bonus"]
    @moduletag graph_path: ["Finance.Bonus"]
    @moduletag steps: %{
      given: [
        "A player makes a deposit"
      ],
      when: [
        "Bonuses are calculated"
      ],
      then: [
        "Total bonus value <= deposit * max_bonus_multiplier"
      ]
    }

    test "bonus never exceeds limits" do
      :ok
    end
  end
end

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
    @moduletag nodes: ["Promotions.BonusGrant", "Promotions.BonusCampaign"]
    @moduletag graph_path: ["Promotions.BonusCampaign", "Promotions.BonusGrant"]
    @moduletag steps: %{
      given: [
        "An active bonus campaign with a wagering multiplier",
        "A granted player bonus with wagering remaining"
      ],
      when: [
        "The player applies qualifying wagers to the bonus grant",
        "The remaining wagering reaches zero"
      ],
      then: [
        "The bonus grant progresses through active -> wagered state",
        "The campaign terms remain the source of the wagering requirement"
      ]
    }

    test "wagering requirement progresses correctly" do
      :ok
    end
  end

  describe "Property: Bonus value never exceeds deposit" do
    @moduletag category: :property
    @moduletag nodes: ["Promotions.BonusCampaign", "Promotions.BonusGrantTransfer", "Promotions.BonusGrant"]
    @moduletag graph_path: ["Promotions.BonusCampaign", "Promotions.BonusGrantTransfer", "Promotions.BonusGrant"]
    @moduletag steps: %{
      given: [
        "A deposit-triggered bonus campaign is active",
        "A player makes a qualifying deposit"
      ],
      when: [
        "The bonus grant transfer evaluates and awards the campaign"
      ],
      then: [
        "The granted bonus amount matches the configured campaign amount",
        "The created bonus grant cannot exceed the awarded transfer amount"
      ]
    }

    test "bonus never exceeds limits" do
      :ok
    end
  end
end

defmodule IgamingRefTest.Generators do
  @moduledoc """
  Shared data generators for the IgamingRef reference project test suite.

  All generated test skeletons reference generators from this module by
  convention name. Add generators here before referencing them in tests.
  This module is read by the Foundry copilot before generating any test
  that references fixtures (ADR-007 §Generators are the shared foundation).
  """

  use ExUnitProperties

  # ---------------------------------------------------------------------------
  # Player generators
  # ---------------------------------------------------------------------------

  def player_fixture(overrides \\ %{}) do
    Map.merge(%{
      id:            Ash.UUID.generate(),
      email:         "player_#{:rand.uniform(99999)}@test.example",
      username:      "player_#{:rand.uniform(99999)}",
      date_of_birth: ~D[1990-01-15],
      country_code:  "GB",
      kyc_status:    :verified,
      risk_level:    :low,
      status:        :active
    }, overrides)
  end

  def self_excluded_player_fixture do
    player_fixture(%{status: :self_excluded})
  end

  def gen_player_status do
    StreamData.member_of([:active, :suspended, :self_excluded, :closed])
  end

  def gen_risk_level do
    StreamData.member_of([:low, :medium, :high])
  end

  # ---------------------------------------------------------------------------
  # Wallet generators
  # ---------------------------------------------------------------------------

  def wallet_fixture(overrides \\ %{}) do
    Map.merge(%{
      id:        Ash.UUID.generate(),
      player_id: Ash.UUID.generate(),
      currency:  "GBP",
      balance:   Money.new(10_000_00, :GBP),
      status:    :active
    }, overrides)
  end

  def frozen_wallet_fixture do
    wallet_fixture(%{status: :frozen})
  end

  def zero_balance_wallet_fixture do
    wallet_fixture(%{balance: Money.new(0, :GBP)})
  end

  def gen_positive_money do
    StreamData.positive_integer()
    |> StreamData.map(&Money.new(&1, :GBP))
  end

  def gen_wallet_status do
    StreamData.member_of([:active, :frozen, :closed])
  end

  # ---------------------------------------------------------------------------
  # Withdrawal generators
  # ---------------------------------------------------------------------------

  def withdrawal_request_fixture(overrides \\ %{}) do
    Map.merge(%{
      id:        Ash.UUID.generate(),
      player_id: Ash.UUID.generate(),
      wallet_id: Ash.UUID.generate(),
      amount:    Money.new(100_00, :GBP),
      status:    :approved,
      provider:  "stripe"
    }, overrides)
  end

  # ---------------------------------------------------------------------------
  # Campaign generators
  # ---------------------------------------------------------------------------

  def campaign_fixture(overrides \\ %{}) do
    Map.merge(%{
      id:                  Ash.UUID.generate(),
      name:                "Test Campaign",
      kind:                :deposit_match,
      status:              :active,
      eligibility_rule:    "IgamingRef.Promotions.Rules.PlayerEligibleForCampaign",
      bonus_amount:        Money.new(50_00, :GBP),
      wagering_multiplier: Decimal.new("5.0"),
      max_redemptions:     nil,
      starts_at:           DateTime.add(DateTime.utc_now(), -3600, :second),
      expires_at:          DateTime.add(DateTime.utc_now(), 86_400, :second)
    }, overrides)
  end

  def expired_campaign_fixture do
    campaign_fixture(%{
      status:     :expired,
      expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
    })
  end
end

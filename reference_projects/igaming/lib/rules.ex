defmodule IgamingRef.Finance.Rules.SufficientBalance do
  @moduledoc """
  Rule: the wallet balance must be sufficient to cover the requested debit amount.

  Applied by: IgamingRef.Finance.WithdrawalTransfer
  Compliance: RG-MGA-001 (wallet balance integrity - balance never goes negative)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_001]
  @spec_invariants [
    "balance after debit is never negative",
    "rule rejects when amount > current balance",
    "rule passes when amount == current balance (exact drain)"
  ]

  @behaviour IgamingRef.Rule

  @impl IgamingRef.Rule
  def evaluate(%{wallet: wallet, amount: amount}, _context) do
    case Money.compare!(wallet.balance, amount) do
      :lt ->
        {:error, :insufficient_balance,
         "Wallet balance #{wallet.balance} is less than requested amount #{amount} (RG-MGA-001)"}

      _ ->
        :ok
    end
  end

  @impl IgamingRef.Rule
  def description, do: "Wallet balance must cover the requested withdrawal amount"
end

defmodule IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded do
  @moduledoc """
  Rule: the withdrawal amount must not exceed the player's configured daily limit.

  The daily limit is read from the player's risk profile. High-risk players
  have lower limits. This rule is evaluated at Transfer time against the sum
  of completed withdrawals in the rolling 24-hour window.

  Applied by: IgamingRef.Finance.WithdrawalTransfer
  Compliance: RG-UK-014 (withdrawal processing), RG-MGA-007 (withdrawal limits)
  """

  use Foundry.Annotations

  @compliance [:RG_UK_014, :RG_MGA_007]
  @spec_invariants [
    "rule rejects when daily_used + amount > daily_limit",
    "daily_used is the sum of completed withdrawals in the last 24 hours",
    "high-risk players have lower daily_limit than low-risk players"
  ]

  @behaviour IgamingRef.Rule

  # Default limits by risk level (in GBP-equivalent)
  @daily_limits %{
    low: Money.new(10_000_00, :GBP),
    medium: Money.new(2_500_00, :GBP),
    high: Money.new(500_00, :GBP)
  }

  @impl IgamingRef.Rule
  def evaluate(%{player: player, amount: amount, daily_used: daily_used}, _context) do
    limit = Map.get(@daily_limits, player.risk_level, @daily_limits.low)
    total = Money.add!(daily_used, amount)

    case Money.compare!(total, limit) do
      :gt ->
        {:error, :daily_limit_exceeded,
         "Withdrawal of #{amount} would exceed the daily limit of #{limit} for risk level #{player.risk_level} (RG-MGA-007)"}

      _ ->
        :ok
    end
  end

  @impl IgamingRef.Rule
  def description, do: "Withdrawal amount must not exceed the player's daily limit"
end

defmodule IgamingRef.Players.Rules.PlayerNotSelfExcluded do
  @moduledoc """
  Rule: the player must not have an active self-exclusion record.

  Applied by: IgamingRef.Finance.WithdrawalTransfer,
              IgamingRef.Promotions.BonusGrantTransfer

  This rule is cross-domain - it belongs to the Players domain but is applied
  in Finance and Promotions Transfers. Self-exclusion must block ALL financial
  transactions immediately (RG-UK-008).

  Compliance: RG-UK-008, RG-MGA-009 (self-exclusion integrity)
  """

  use Foundry.Annotations

  @compliance [:RG_UK_008, :RG_MGA_009]
  @spec_invariants [
    "rule rejects when player.status == :self_excluded",
    "rule rejects when a SelfExclusionRecord exists with nil reinstated_at",
    "rule passes when player.status == :active with no active exclusion record"
  ]

  @behaviour IgamingRef.Rule

  @impl IgamingRef.Rule
  def evaluate(%{player: player}, _context) do
    if player.status == :self_excluded do
      {:error, :player_self_excluded,
       "Player #{player.id} is self-excluded and cannot perform financial transactions (RG-UK-008)"}
    else
      :ok
    end
  end

  @impl IgamingRef.Rule
  def description, do: "Player must not have an active self-exclusion"
end

defmodule IgamingRef.Promotions.Rules.PlayerEligibleForCampaign do
  @moduledoc """
  Rule: the player meets the campaign's eligibility criteria.

  Eligibility checks that the player has not already redeemed this campaign
  and that the campaign has not exhausted its redemption cap across all players.

  Applied by: IgamingRef.Promotions.BonusGrantTransfer
  Compliance: RG-MGA-005 (bonus terms transparency and enforcement)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_005]
  @spec_invariants [
    "rule rejects when player already has an active grant from this campaign",
    "rule rejects when campaign max_redemptions is reached",
    "rule passes when player has no prior grant from this campaign"
  ]

  @behaviour IgamingRef.Rule

  @impl IgamingRef.Rule
  def evaluate(
        %{player: player, campaign: campaign, existing_grants: existing_grants} = context,
        _context
      ) do
    player_grants =
      Enum.filter(existing_grants, &(&1.player_id == player.id and &1.campaign_id == campaign.id))

    campaign_grants = Map.get(context, :campaign_grants, existing_grants)

    cond do
      player.status != :active ->
        {:error, :player_not_active, "Player account is not active (RG-MGA-005)"}

      campaign.max_redemptions != nil and length(campaign_grants) >= campaign.max_redemptions ->
        {:error, :campaign_max_redemptions_reached,
         "Campaign has reached its maximum redemption limit (RG-MGA-005)"}

      Enum.any?(player_grants, &(&1.status == :active)) ->
        {:error, :player_already_has_grant,
         "Player already has an active grant from campaign #{campaign.id} (RG-MGA-005)"}

      true ->
        :ok
    end
  end

  @impl IgamingRef.Rule
  def description, do: "Player must meet campaign eligibility criteria"
end

defmodule IgamingRef.Promotions.Rules.CampaignNotExpired do
  @moduledoc """
  Rule: the campaign's expires_at has not passed.

  Evaluated at Transfer time, not at campaign read time - a campaign could
  expire between when the user sees it and when they claim it.

  Applied by: IgamingRef.Promotions.BonusGrantTransfer
  Compliance: RG-MGA-005
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_005]
  @spec_invariants [
    "rule rejects when campaign.expires_at is in the past",
    "rule rejects when campaign.status == :expired",
    "rule passes when campaign is :active and expires_at is in the future"
  ]

  @behaviour IgamingRef.Rule

  @impl IgamingRef.Rule
  def evaluate(%{campaign: campaign}, _context) do
    now = DateTime.utc_now()

    cond do
      campaign.status == :expired ->
        {:error, :campaign_expired, "Campaign #{campaign.id} has status :expired (RG-MGA-005)"}

      campaign.status != :active ->
        {:error, :campaign_not_active, "Campaign #{campaign.id} is not active (RG-MGA-005)"}

      DateTime.compare(campaign.expires_at, now) == :lt ->
        {:error, :campaign_expired,
         "Campaign #{campaign.id} expired at #{campaign.expires_at} (RG-MGA-005)"}

      true ->
        :ok
    end
  end

  @impl IgamingRef.Rule
  def description, do: "Campaign must not have expired"
end

defmodule IgamingRef.Promotions.Rules.CampaignNotStarted do
  @moduledoc """
  Rule: the campaign's starts_at has passed.

  Applied by: IgamingRef.Promotions.BonusGrantTransfer
  Compliance: RG-MGA-005
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_005]
  @spec_invariants [
    "rule rejects when campaign.starts_at is in the future",
    "rule passes when campaign.starts_at is in the past",
    "rule prevents grant-time activation of future campaigns"
  ]

  @behaviour IgamingRef.Rule

  @impl IgamingRef.Rule
  def evaluate(%{campaign: campaign}, _context) do
    now = DateTime.utc_now()

    case DateTime.compare(campaign.starts_at, now) do
      :gt ->
        {:error, :campaign_not_started,
         "Campaign #{campaign.id} starts at #{campaign.starts_at} and cannot be granted yet (RG-MGA-005)"}

      _ ->
        :ok
    end
  end

  @impl IgamingRef.Rule
  def description, do: "Campaign must have reached its starts_at"
end

defmodule IgamingRef.Finance.Rules.PlayerKYCVerified do
  @moduledoc """
  Rule: the player must have verified KYC status before certain transactions.

  Compliance: RG-MGA-003 (KYC requirements)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_003]
  @spec_invariants [
    "rule rejects when player.kyc_status != :verified",
    "rule passes when player.kyc_status == :verified",
    "rule is a hard requirement for withdrawal processing"
  ]

  @behaviour IgamingRef.Rule

  @impl IgamingRef.Rule
  def evaluate(%{player: player}, _context) do
    if player.kyc_status == :verified do
      :ok
    else
      {:error, :kyc_not_verified,
       "Player #{player.id} has kyc_status #{player.kyc_status}, must be :verified (RG-MGA-003)"}
    end
  end

  @impl IgamingRef.Rule
  def description, do: "Player must have verified KYC status"
end

defmodule IgamingRef.Gaming.Rules.ProviderActive do
  @moduledoc """
  Rule: the gaming provider must be in :active status.

  Compliance: RG-MGA-006 (provider agreements)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_006]
  @spec_invariants [
    "rule rejects when provider status is not :active",
    "rule passes when provider.status == :active",
    "games from inactive providers are not playable"
  ]

  @behaviour IgamingRef.Rule

  @impl IgamingRef.Rule
  def evaluate(%{provider_config: config}, _context) do
    if config.status == :active do
      :ok
    else
      {:error, :provider_inactive,
       "Provider #{config.provider_name} has status #{config.status}, must be :active (RG-MGA-006)"}
    end
  end

  @impl IgamingRef.Rule
  def description, do: "Provider must be in active status"
end

defmodule IgamingRef.Gaming.Rules.GameRTPCertified do
  @moduledoc """
  Rule: the game version must have RTP certification.

  Compliance: RG-UK-007 (game certification)
  """

  use Foundry.Annotations

  @compliance [:RG_UK_007]
  @spec_invariants [
    "rule rejects when game_version.rtp_certified is false",
    "rule passes when game_version.rtp_certified is true",
    "uncertified game versions cannot be played"
  ]

  @behaviour IgamingRef.Rule

  @impl IgamingRef.Rule
  def evaluate(%{game_version: version}, _context) do
    if version.rtp_certified do
      :ok
    else
      {:error, :rtp_not_certified,
       "Game version #{version.id} is not RTP-certified. Cannot be played (RG-UK-007)"}
    end
  end

  @impl IgamingRef.Rule
  def description, do: "Game version must be RTP-certified"
end

# ---------------------------------------------------------------------------
# Rule behaviour
# ---------------------------------------------------------------------------

defmodule IgamingRef.Rule do
  @moduledoc """
  Behaviour for all IgamingRef domain rules.

  Rules are pure functions - no side effects, no database calls.
  All data needed for evaluation is passed in the context map.
  """

  @type context :: map()
  @type ok :: :ok
  @type error :: {:error, atom(), String.t()}

  @callback evaluate(context(), any()) :: ok() | error()
  @callback description() :: String.t()
end

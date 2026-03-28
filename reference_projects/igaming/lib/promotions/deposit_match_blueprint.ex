defmodule IgamingRef.Promotions.DepositMatchBlueprint do
  @moduledoc """
  Blueprint for deposit match bonus campaigns.

  Defines the standard parameters and calculation rules for deposit matching
  promotions (e.g., "100% match up to £500"). Used as a template when creating
  new BonusCampaign instances with consistent parameters.

  Used by: IgamingRef.Promotions.BonusGrantTransfer
  Compliance: RG-MGA-005 (bonus terms transparency)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_005]
  @telemetry_prefix [:igaming_ref, :promotions, :deposit_match_blueprint]

  # Mark this as a blueprint module for Foundry introspection
  def __blueprint__(), do: true

  defstruct [
    :name,
    :match_percentage,
    :max_bonus_amount,
    :min_deposit_amount,
    :wagering_multiplier,
    :eligible_countries,
    :expires_at
  ]

  @type t :: %__MODULE__{
    name: String.t(),
    match_percentage: Decimal.t(),
    max_bonus_amount: Money.t(),
    min_deposit_amount: Money.t(),
    wagering_multiplier: Decimal.t(),
    eligible_countries: [String.t()],
    expires_at: DateTime.t()
  }

  @doc """
  Create a new deposit match blueprint with standard parameters.

  Args:
    - name: Campaign name
    - match_percentage: Percentage match (e.g., Decimal.new("100") for 100%)
    - max_bonus_amount: Maximum bonus allowed (e.g., Money.new(50_000, :GBP))
    - min_deposit_amount: Minimum deposit required
    - wagering_multiplier: Wagering requirement multiplier (e.g., 3x bonus amount)
    - eligible_countries: List of ISO 3166-1 alpha-2 country codes
    - expires_at: Campaign expiration datetime

  Returns: {:ok, %DepositMatchBlueprint{}} | {:error, reason}
  """
  def new(name, match_percentage, max_bonus, min_deposit, wager_mult, countries, expires) do
    blueprint = %__MODULE__{
      name: name,
      match_percentage: match_percentage,
      max_bonus_amount: max_bonus,
      min_deposit_amount: min_deposit,
      wagering_multiplier: wager_mult,
      eligible_countries: countries,
      expires_at: expires
    }

    case validate(blueprint) do
      :ok -> {:ok, blueprint}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Calculate the bonus amount for a given deposit.

  Applies the match percentage and enforces the maximum bonus cap.
  """
  def calculate_bonus(blueprint, deposit_amount) when is_struct(blueprint) do
    case Money.compare!(deposit_amount, blueprint.min_deposit_amount) do
      :lt ->
        {:error, "Deposit below minimum of #{blueprint.min_deposit_amount}"}

      _ ->
        with {:ok, matched} <- Money.mult(
               deposit_amount,
               Decimal.to_string(Decimal.div(blueprint.match_percentage, 100))
             ) do
          bonus = case Money.compare!(matched, blueprint.max_bonus_amount) do
            :gt -> blueprint.max_bonus_amount
            _ -> matched
          end

          {:ok, bonus}
        end
    end
  end

  @doc """
  Check if a player from the given country is eligible.
  """
  def player_eligible?(blueprint, country_code) when is_binary(country_code) do
    Enum.member?(blueprint.eligible_countries, country_code)
  end

  @doc """
  Validate the blueprint structure.
  """
  def validate(blueprint) when is_struct(blueprint) do
    cond do
      is_nil(blueprint.name) -> {:error, "name is required"}
      is_nil(blueprint.match_percentage) -> {:error, "match_percentage is required"}
      is_nil(blueprint.max_bonus_amount) -> {:error, "max_bonus_amount is required"}
      is_nil(blueprint.min_deposit_amount) -> {:error, "min_deposit_amount is required"}
      is_nil(blueprint.wagering_multiplier) -> {:error, "wagering_multiplier is required"}
      is_nil(blueprint.eligible_countries) -> {:error, "eligible_countries is required"}
      is_nil(blueprint.expires_at) -> {:error, "expires_at is required"}
      true -> :ok
    end
  end
end

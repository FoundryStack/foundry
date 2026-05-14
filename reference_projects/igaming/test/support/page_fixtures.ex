defmodule IgamingRef.PageFixtures do
  @moduledoc false
  require Ash.Query

  alias IgamingRef.Accounts.User
  alias IgamingRef.Finance.{Transfer, Wallet, WithdrawalRequest}
  alias IgamingRef.Gaming.{Game, GameSession}
  alias IgamingRef.Players.Player
  alias IgamingRef.Promotions.BonusCampaign

  def player_fixture(attrs \\ %{}) do
    defaults = %{
      email: unique_email("player"),
      username: unique_username("player"),
      date_of_birth: ~D[1990-01-01],
      country_code: "GB"
    }

    Ash.create!(Player, Map.merge(defaults, attrs), action: :register, authorize?: false)
  end

  def wallet_fixture(player, attrs \\ %{}) do
    currency = Map.get(attrs, :currency, "GBP")
    balance = Map.get(attrs, :balance, Money.new(:GBP, "0.00"))

    wallet =
      Ash.create!(
        Wallet,
        %{player_id: player.id, currency: currency},
        action: :create,
        actor: %{is_system: true}
      )

    if Money.zero?(balance) do
      wallet
    else
      wallet
      |> Ash.Changeset.for_update(:credit, %{amount: balance})
      |> Ash.update!(actor: %{is_system: true})
    end
  end

  def game_fixture(attrs \\ %{}) do
    defaults = %{
      provider_id: Ash.UUID.generate(),
      provider_game_code: "game-#{System.unique_integer([:positive])}",
      title: "Lucky Spires #{System.unique_integer([:positive])}",
      category: "slot",
      rtp: Decimal.new("96.50"),
      volatility: :medium
    }

    Ash.create!(Game, Map.merge(defaults, attrs), action: :sync, authorize?: false)
  end

  def bonus_campaign_fixture(attrs \\ %{}) do
    defaults = %{
      name: "Welcome Bonus #{System.unique_integer([:positive])}",
      kind: :deposit_match,
      eligibility_rule: "IgamingRef.Promotions.Rules.PlayerEligibleForCampaign",
      bonus_amount: Money.new(:GBP, "10.00"),
      wagering_multiplier: Decimal.new("10"),
      max_redemptions: 100,
      starts_at: DateTime.add(DateTime.utc_now(), -3600, :second),
      expires_at: DateTime.add(DateTime.utc_now(), 86_400, :second)
    }

    Ash.create!(
      BonusCampaign,
      Map.merge(defaults, attrs),
      action: :create,
      authorize?: false
    )
  end

  def user_fixture(attrs \\ %{}) do
    defaults = %{email: unique_email("user"), password: "password123"}
    Ash.create!(User, Map.merge(defaults, attrs), action: :register_with_password, authorize?: false)
  end

  def view_assigns(view) do
    :sys.get_state(view.pid).socket.assigns
  end

  def flash(view, kind) do
    view
    |> view_assigns()
    |> Map.get(:flash, %{})
    |> then(fn flash -> Map.get(flash, kind) || Map.get(flash, to_string(kind)) end)
  end

  def normalize_text(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def transfer_for_wallet(wallet_id) do
    Transfer
    |> Ash.Query.filter(to_wallet_id: wallet_id)
    |> Ash.Query.filter(reason: "deposit")
    |> Ash.read_one!(authorize?: false)
  end

  def withdrawal_for_wallet(wallet_id) do
    WithdrawalRequest
    |> Ash.Query.filter(wallet_id: wallet_id)
    |> Ash.read_one!(authorize?: false)
  end

  def session_for(player_id, game_id) do
    GameSession
    |> Ash.Query.filter(player_id: player_id)
    |> Ash.Query.filter(game_id: game_id)
    |> Ash.read_one!(authorize?: false)
  end

  def unique_email(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}@example.test"
  def unique_username(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"
end

defmodule IgamingRef.Promotions.BonusCampaign do
  @moduledoc """
  A configured bonus campaign. Declares eligibility rules, award amounts,
  and wagering requirements.

  Non-sensitive resource. Changes require :behavioral approval only.
  Terms must be transparent and enforced at grant time (RG-MGA-005, RG-UK-011).

  Compliance: RG-MGA-005 (bonus terms transparency), RG-UK-011 (bonus wagering disclosure).
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_005, :RG_UK_011]
  @telemetry_prefix [:igaming_ref, :promotions, :bonus_campaign]

  use Ash.Resource,
    domain: IgamingRef.Promotions,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  postgres do
    table("bonus_campaigns")
    repo(IgamingRef.Repo)
  end

  state_machine do
    state_attribute(:status)
    initial_states([:draft])
    default_initial_state(:draft)

    transitions do
      transition(:activate, from: :draft, to: :active)
      transition(:pause, from: :active, to: :paused)
      transition(:resume, from: :paused, to: :active)
      transition(:expire, from: [:active, :paused], to: :expired)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      description("Human-readable campaign name. Shown to players in the promotions UI.")
      allow_nil?(false)
      constraints(max_length: 255)
    end

    attribute :kind, :atom do
      description("Campaign type. Determines the award calculation logic.")
      constraints(one_of: [:deposit_match, :free_spins, :cashback])
      allow_nil?(false)
    end

    attribute :status, :atom do
      description("Lifecycle state. Managed by AshStateMachine.")
      constraints(one_of: [:draft, :active, :paused, :expired])
      default(:draft)
      allow_nil?(false)
    end

    attribute :eligibility_rule, :string do
      description(
        "Module name of the Rule that determines player eligibility. E.g. 'IgamingRef.Promotions.Rules.PlayerEligibleForCampaign'."
      )

      allow_nil?(false)
    end

    attribute :bonus_amount, :money do
      description(
        "Base bonus award amount. For :deposit_match campaigns, this is multiplied by the deposit (RG-UK-011 requires this to be disclosed at grant time)."
      )

      allow_nil?(false)
    end

    attribute :wagering_multiplier, :decimal do
      description(
        "Wagering requirement multiplier. A player must wager bonus_amount * wagering_multiplier before withdrawal (RG-UK-011)."
      )

      allow_nil?(false)
      constraints(min: 0)
    end

    attribute :max_redemptions, :integer do
      description(
        "Maximum number of times this campaign can be redeemed across all players. Nil means unlimited."
      )

      allow_nil?(true)
      constraints(min: 1)
    end

    attribute :starts_at, :utc_datetime do
      description("When the campaign becomes eligible for redemption.")
      allow_nil?(false)
    end

    attribute :expires_at, :utc_datetime do
      description(
        "When the campaign stops being eligible for redemption. Checked by CampaignNotExpired rule."
      )

      allow_nil?(false)
    end

    timestamps()
  end

  relationships do
    has_many :grants, IgamingRef.Promotions.BonusGrant do
      description("All bonus grants issued from this campaign.")
      destination_attribute(:campaign_id)
    end

    has_many :triggers, IgamingRef.Promotions.BonusTrigger do
      description("Manager-defined trigger declarations for this campaign.")
      destination_attribute(:campaign_id)
    end

    has_many :condition_groups, IgamingRef.Promotions.BonusConditionGroup do
      description("Logical condition tree groups for this campaign.")
      destination_attribute(:campaign_id)
    end

    has_many :executions, IgamingRef.Promotions.BonusExecution do
      description("Execution steps that run when campaign conditions pass.")
      destination_attribute(:campaign_id)
    end
  end

  actions do
    defaults([:read])

    create :create do
      description("Create a new campaign in :draft state.")

      accept([
        :name,
        :kind,
        :eligibility_rule,
        :bonus_amount,
        :wagering_multiplier,
        :max_redemptions,
        :starts_at,
        :expires_at
      ])
    end

    update :update do
      description("Update campaign configuration. Only permitted while in :draft state.")
      require_atomic?(false)

      accept([
        :name,
        :bonus_amount,
        :wagering_multiplier,
        :max_redemptions,
        :starts_at,
        :expires_at
      ])

      validate(fn changeset, _ ->
        status = Ash.Changeset.get_attribute(changeset, :status)
        if status == :draft, do: :ok, else: {:error, "only draft campaigns can be updated"}
      end)
    end

    update :activate do
      description("Activate the campaign. Validates starts_at is not in the future.")
      require_atomic?(false)

      validate(fn changeset, _ ->
        starts_at = Ash.Changeset.get_attribute(changeset, :starts_at)

        if DateTime.compare(starts_at, DateTime.utc_now()) in [:lt, :eq] do
          :ok
        else
          {:error, "campaign cannot be activated before starts_at"}
        end
      end)

      change(transition_state(:active))
    end

    update :pause do
      description("Pause an active campaign temporarily.")
      change(transition_state(:paused))
    end

    update :resume do
      description("Resume a paused campaign.")
      change(transition_state(:active))
    end

    update :expire do
      description("Expire the campaign. Called by a scheduled job when expires_at passes.")
      change(transition_state(:expired))
    end
  end

  policies do
    policy action_type(:read) do
      description(
        "All authenticated users may read campaign details (terms must be transparent - RG-MGA-005)."
      )

      authorize_if(IgamingRef.Policies.AuthenticatedSubject)
    end

    policy action(:create) do
      authorize_if(IgamingRef.Policies.OperatorOnly)
    end

    policy action(:update) do
      authorize_if(IgamingRef.Policies.OperatorOnly)
    end

    policy action(:activate) do
      authorize_if(IgamingRef.Policies.OperatorOnly)
    end
  end
end

defmodule IgamingRef.Promotions.BonusGrant do
  @moduledoc """
  A specific bonus awarded to a player from a campaign.

  Tracks wagering progress. State advances to :wagered when wagering_remaining
  reaches zero, enabling the bonus funds to be withdrawn.

  Compliance: RG-MGA-005, RG-UK-011.
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_005, :RG_UK_011]
  @telemetry_prefix [:igaming_ref, :promotions, :bonus_grant]

  use Ash.Resource,
    domain: IgamingRef.Promotions,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  postgres do
    table("bonus_grants")
    repo(IgamingRef.Repo)
  end

  state_machine do
    state_attribute(:status)
    initial_states([:active])
    default_initial_state(:active)

    transitions do
      transition(:complete, from: :active, to: :wagered)
      transition(:forfeit, from: :active, to: :forfeited)
      transition(:expire, from: :active, to: :expired)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :player_id, :uuid do
      description("The player who received this bonus.")
      allow_nil?(false)
    end

    attribute :campaign_id, :uuid do
      description("The campaign this grant was issued from.")
      allow_nil?(false)
    end

    attribute :amount, :money do
      description("Total bonus amount awarded. Fixed at grant time (RG-UK-011).")
      allow_nil?(false)
    end

    attribute :wagering_remaining, :decimal do
      description(
        "Amount still to be wagered before the bonus can be withdrawn. Decremented by apply_wager."
      )

      allow_nil?(false)
      constraints(min: 0)
    end

    attribute :status, :atom do
      description("Lifecycle state. Managed by AshStateMachine.")
      constraints(one_of: [:active, :wagered, :forfeited, :expired])
      default(:active)
      allow_nil?(false)
    end

    attribute :granted_at, :utc_datetime do
      description("When the bonus was awarded.")
      allow_nil?(false)
    end

    attribute :expires_at, :utc_datetime do
      description("When the bonus expires if wagering requirements are not met.")
      allow_nil?(false)
    end

    timestamps()
  end

  relationships do
    belongs_to :player, IgamingRef.Players.Player do
      description("The player who received this bonus.")
      source_attribute(:player_id)
      allow_nil?(false)
    end

    belongs_to :campaign, IgamingRef.Promotions.BonusCampaign do
      description("The campaign this bonus was issued from.")
      source_attribute(:campaign_id)
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :grant do
      description(
        "Issue a bonus grant. Called by BonusGrantTransfer after eligibility is confirmed."
      )

      accept([:player_id, :campaign_id, :amount, :wagering_remaining, :granted_at, :expires_at])
    end

    update :apply_wager do
      description("Decrement wagering_remaining. When it reaches zero, transitions to :wagered.")
      require_atomic?(false)

      argument :wager_amount, :decimal do
        description("The wagered amount to apply toward the requirement.")
        allow_nil?(false)
      end

      change(fn changeset, _ ->
        wager = Ash.Changeset.get_argument(changeset, :wager_amount)
        current = Ash.Changeset.get_attribute(changeset, :wagering_remaining)
        new_remaining = Decimal.max(Decimal.sub(current, wager), Decimal.new(0))
        Ash.Changeset.change_attribute(changeset, :wagering_remaining, new_remaining)
      end)

      change(fn changeset, _ ->
        remaining = Ash.Changeset.get_attribute(changeset, :wagering_remaining)

        if Decimal.eq?(remaining, Decimal.new(0)) do
          Ash.Changeset.change_attribute(changeset, :status, :wagered)
        else
          changeset
        end
      end)
    end

    update :forfeit do
      description("Forfeit the bonus. Called when a player violates bonus terms.")
      change(transition_state(:forfeited))
    end

    update :expire do
      description("Expire the bonus. Called by a scheduled job when expires_at passes.")
      change(transition_state(:expired))
    end

    update :complete do
      description("Mark the bonus as fully wagered. Called when wagering_remaining hits zero.")
      change(transition_state(:wagered))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(IgamingRef.Policies.OwnerOrOperator)
    end

    policy action(:grant) do
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end

    policy action(:apply_wager) do
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end
  end
end

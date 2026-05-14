defmodule IgamingRef.Promotions.BonusCondition do
  @moduledoc """
  Atomic condition used by bonus rule trees.
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_005, :RG_UK_011]
  @telemetry_prefix [:igaming_ref, :promotions, :bonus_condition]

  use Ash.Resource,
    domain: IgamingRef.Promotions,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("bonus_conditions")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :group_id, :uuid do
      description("Condition group that owns this condition.")
      allow_nil?(false)
    end

    attribute :kind, :atom do
      description("Condition handler identifier.")
      allow_nil?(false)

      constraints(
        one_of: [
          :campaign_active,
          :campaign_not_expired,
          :player_not_self_excluded,
          :player_country_in,
          :min_deposit_amount,
          :no_active_bonus
        ]
      )
    end

    attribute :params, :map do
      description("Condition parameters consumed by handler-specific logic.")
      allow_nil?(false)
      default(%{})
    end

    attribute :negated, :boolean do
      description("Invert condition result when true.")
      allow_nil?(false)
      default(false)
    end

    attribute :position, :integer do
      description("Ordering position within the group.")
      allow_nil?(false)
      default(0)
      constraints(min: 0)
    end

    timestamps()
  end

  relationships do
    belongs_to :group, IgamingRef.Promotions.BonusConditionGroup do
      description("Condition group containing this condition.")
      source_attribute(:group_id)
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :create do
      description("Create an atomic condition.")
      accept([:group_id, :kind, :params, :negated, :position])
    end

    update :update do
      description("Update condition configuration.")
      accept([:kind, :params, :negated, :position])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(IgamingRef.Policies.AuthenticatedSubject)
    end

    policy action(:create) do
      authorize_if(IgamingRef.Policies.OperatorOnly)
    end

    policy action(:update) do
      authorize_if(IgamingRef.Policies.OperatorOnly)
    end
  end
end

defmodule IgamingRef.Promotions.BonusConditionGroup do
  @moduledoc """
  Logical grouping node for campaign conditions.

  Groups use `:all` / `:any` combinators and may be nested via parent_group_id.
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_005, :RG_UK_011]
  @telemetry_prefix [:igaming_ref, :promotions, :bonus_condition_group]

  use Ash.Resource,
    domain: IgamingRef.Promotions,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("bonus_condition_groups")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :campaign_id, :uuid do
      description("Campaign that owns this condition group.")
      allow_nil?(false)
    end

    attribute :parent_group_id, :uuid do
      description("Optional parent group for nested trees.")
      allow_nil?(true)
    end

    attribute :combinator, :atom do
      description("How child conditions are combined.")
      allow_nil?(false)
      default(:all)
      constraints(one_of: [:all, :any])
    end

    attribute :position, :integer do
      description("Ordering position for stable UI and evaluation sequence.")
      allow_nil?(false)
      default(0)
      constraints(min: 0)
    end

    timestamps()
  end

  relationships do
    belongs_to :campaign, IgamingRef.Promotions.BonusCampaign do
      description("Campaign this group belongs to.")
      source_attribute(:campaign_id)
      allow_nil?(false)
    end

    belongs_to :parent_group, __MODULE__ do
      description("Optional parent condition group.")
      source_attribute(:parent_group_id)
      allow_nil?(true)
    end

    has_many :conditions, IgamingRef.Promotions.BonusCondition do
      description("Conditions directly contained by this group.")
      destination_attribute(:group_id)
    end
  end

  actions do
    defaults([:read])

    create :create do
      description("Create a condition group for a campaign.")
      accept([:campaign_id, :parent_group_id, :combinator, :position])
    end

    update :update do
      description("Update group combinator or ordering.")
      accept([:combinator, :position, :parent_group_id])
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

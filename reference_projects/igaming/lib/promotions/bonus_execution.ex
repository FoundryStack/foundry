defmodule IgamingRef.Promotions.BonusExecution do
  @moduledoc """
  Declarative execution step for a campaign.
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_005, :RG_UK_011]
  @telemetry_prefix [:igaming_ref, :promotions, :bonus_execution]

  use Ash.Resource,
    domain: IgamingRef.Promotions,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("bonus_executions")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :campaign_id, :uuid do
      description("Campaign that owns this execution.")
      allow_nil?(false)
    end

    attribute :kind, :atom do
      description("Execution handler identifier.")
      allow_nil?(false)
      constraints(one_of: [:grant_deposit_match, :grant_fixed_amount, :set_wagering_requirement])
    end

    attribute :params, :map do
      description("Execution parameters used by the handler.")
      allow_nil?(false)
      default(%{})
    end

    attribute :position, :integer do
      description("Execution order index.")
      allow_nil?(false)
      default(0)
      constraints(min: 0)
    end

    attribute :enabled, :boolean do
      description("Whether this execution is currently active.")
      allow_nil?(false)
      default(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :campaign, IgamingRef.Promotions.BonusCampaign do
      description("Campaign configured by this execution.")
      source_attribute(:campaign_id)
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :create do
      description("Create an execution step for a campaign.")
      accept([:campaign_id, :kind, :params, :position, :enabled])
    end

    update :update do
      description("Update execution configuration.")
      accept([:kind, :params, :position, :enabled])
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

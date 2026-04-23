defmodule IgamingRef.Promotions.BonusTrigger do
  @moduledoc """
  Configurable trigger declaration for a bonus campaign.

  Managers can enable and order triggers per campaign from back-office.
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_005, :RG_UK_011]
  @telemetry_prefix [:igaming_ref, :promotions, :bonus_trigger]

  use Ash.Resource,
    domain: IgamingRef.Promotions,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("bonus_triggers")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :campaign_id, :uuid do
      description("Campaign that owns this trigger.")
      allow_nil?(false)
    end

    attribute :kind, :atom do
      description("Trigger event kind that can activate this campaign.")
      allow_nil?(false)
      constraints(one_of: [:deposit_completed, :manual_grant])
    end

    attribute :enabled, :boolean do
      description("Whether this trigger is active.")
      allow_nil?(false)
      default(true)
    end

    attribute :params, :map do
      description("Optional trigger parameters used by handler-specific logic.")
      allow_nil?(false)
      default(%{})
    end

    attribute :position, :integer do
      description("Ordering position for deterministic trigger evaluation.")
      allow_nil?(false)
      default(0)
      constraints(min: 0)
    end

    timestamps()
  end

  relationships do
    belongs_to :campaign, IgamingRef.Promotions.BonusCampaign do
      description("Campaign configured by this trigger.")
      source_attribute(:campaign_id)
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :create do
      description("Create a trigger for a campaign.")
      accept([:campaign_id, :kind, :enabled, :params, :position])
    end

    update :update do
      description("Update trigger configuration.")
      accept([:enabled, :params, :position])
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

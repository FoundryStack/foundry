defmodule IgamingRef.Finance.WithdrawalWebhookEvent do
  @moduledoc """
  Inbound provider webhook event captured inside the Ash domain boundary.

  This resource models the external trigger as explicit Ash data so downstream
  processing is always linked to a concrete action invocation.

  Compliance: RG-UK-014 (withdrawal processing integrity), RG-MGA-007.
  """

  use Foundry.Annotations

  @compliance [:RG_UK_014, :RG_MGA_007]
  @telemetry_prefix [:igaming_ref, :finance, :withdrawal_webhook_event]

  use Ash.Resource,
    domain: IgamingRef.Finance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("withdrawal_webhook_events")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :provider, :string do
      description("Webhook provider identifier, e.g. stripe or paypal.")
      allow_nil?(false)
      constraints(max_length: 64)
    end

    attribute :provider_reference, :string do
      description("Provider-assigned transaction identifier from the webhook payload.")
      allow_nil?(false)
      constraints(max_length: 255)
    end

    attribute :event_type, :string do
      description("Provider-native webhook event type.")
      allow_nil?(false)
      constraints(max_length: 255)
    end

    attribute :status, :atom do
      description("Normalized withdrawal status derived from provider event type.")
      allow_nil?(false)
      constraints(one_of: [:completed, :failed, :reversed, :unknown])
    end

    attribute :payload, :map do
      description("Raw webhook payload for debugging and operational replay.")
      allow_nil?(false)
      default(%{})
    end

    create_timestamp(:received_at)
  end

  identities do
    identity :unique_provider_reference_event, [:provider, :provider_reference, :event_type] do
      description("Prevents duplicate inserts for repeated provider webhook delivery.")
    end
  end

  actions do
    defaults([:read])

    create :receive do
      description("Persist a normalized withdrawal webhook event.")
      accept([:provider, :provider_reference, :event_type, :status, :payload])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(IgamingRef.Policies.OperatorOnly)
    end

    policy action(:receive) do
      authorize_if(IgamingRef.Policies.InternalSystemActor)
    end
  end
end

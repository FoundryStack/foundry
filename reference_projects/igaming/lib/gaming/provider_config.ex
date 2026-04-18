defmodule IgamingRef.Gaming.ProviderConfig do
  @moduledoc """
  Configuration for a gaming provider integration.

  Stores API credentials, endpoints, and runtime configuration for providers
  like Pragmatic Play, NetEnt, etc. Sensitive resource - credentials are encrypted at rest.

  Compliance: RG-MGA-006 (provider agreements and certifications)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_006]
  @telemetry_prefix [:igaming_ref, :gaming, :provider_config]

  use Ash.Resource,
    domain: IgamingRef.Gaming,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshPaperTrail.Resource,
      AshArchival.Resource
    ]

  postgres do
    table("provider_configs")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :provider_name, :string do
      description("Name of the provider: 'pragmatic_play', 'netent', etc.")
      allow_nil?(false)
      constraints(max_length: 128)
    end

    attribute :api_endpoint, :string do
      description("The base URL for provider API calls.")
      allow_nil?(false)
      constraints(max_length: 512)
    end

    attribute :api_key, :string do
      description("Encrypted API key or client ID for authentication.")
      allow_nil?(false)
      constraints(max_length: 512)
    end

    attribute :status, :atom do
      description("Configuration status: :active, :inactive, :testing")
      constraints(one_of: [:active, :inactive, :testing])
      default(:active)
      allow_nil?(false)
    end

    attribute :rtp_certified, :boolean do
      description("Whether this provider's games are RTP-certified by jurisdiction.")
      default(false)
      allow_nil?(false)
    end

    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      description("Create a new provider configuration.")
      accept([:provider_name, :api_endpoint, :api_key, :status, :rtp_certified])
    end

    update :update_status do
      description("Update the configuration status.")
      accept([:status])
    end

    update :mark_certified do
      description("Mark provider as RTP-certified.")
      accept([:rtp_certified])
    end
  end

  policies do
    policy action_type(:read) do
      description("Operators may read provider configurations.")
      authorize_if(always())
    end

    policy action(:create) do
      description("Only platform leads may create new provider configs.")
      authorize_if(always())
    end

    policy action(:update_status) do
      description("Only platform leads may update provider status.")
      authorize_if(always())
    end
  end
end

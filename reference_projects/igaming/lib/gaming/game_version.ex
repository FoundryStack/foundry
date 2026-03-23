defmodule IgamingRef.Gaming.GameVersion do
  @moduledoc """
  A specific version of a game.

  Read-only resource. Games may receive updates; versions track distinct
  code and RTP versions. Only one version per game may be :active at a time.

  Compliance: RG-UK-007 (game certification), RG-MGA-006 (provider agreements)
  """

  use Foundry.Annotations

  @compliance [:RG_UK_007, :RG_MGA_006]
  @telemetry_prefix [:igaming_ref, :gaming, :game_version]

  use Ash.Resource,
    domain: IgamingRef.Gaming,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource]

  postgres do
    table("game_versions")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :game_id, :uuid do
      description("The game this version belongs to.")
      allow_nil?(false)
    end

    attribute :version_code, :string do
      description("Provider's version identifier (e.g. '1.2.3' or 'v5').")
      allow_nil?(false)
      constraints(max_length: 64)
    end

    attribute :status, :atom do
      description("Version status: :active, :deprecated, :testing")
      constraints(one_of: [:active, :deprecated, :testing])
      default(:active)
      allow_nil?(false)
    end

    attribute :release_date, :date do
      description("When this version was released by the provider.")
      allow_nil?(false)
    end

    attribute :rtp_certified, :boolean do
      description("Whether this specific version is RTP-certified.")
      default(false)
      allow_nil?(false)
    end

    create_timestamp(:synced_at)
  end

  actions do
    defaults([:read])

    create :sync do
      description("Sync a game version from provider. Internal use only.")
      accept([
        :game_id,
        :version_code,
        :status,
        :release_date,
        :rtp_certified
      ])
    end

    update :mark_active do
      description("Mark this version as the active version.")
      accept([])
    end

    update :mark_deprecated do
      description("Mark this version as deprecated.")
      accept([])
    end
  end

  policies do
    policy action_type(:read) do
      description("All authenticated users may read game versions.")
      authorize_if(always())
    end

    policy action(:sync) do
      description("Only system sync processes may sync versions.")
      authorize_if(always())
    end
  end
end

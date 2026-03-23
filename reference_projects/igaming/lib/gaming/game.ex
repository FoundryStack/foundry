defmodule IgamingRef.Gaming.Game do
  @moduledoc """
  A game title offered by a provider.

  Read-only resource. Games are synced from provider catalogs and cannot be
  manually created. Each game belongs to a provider and has one or more versions.

  Compliance: RG-MGA-006 (provider agreements), RG-UK-007 (game certification)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_006, :RG_UK_007]
  @telemetry_prefix [:igaming_ref, :gaming, :game]

  use Ash.Resource,
    domain: IgamingRef.Gaming,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource]

  postgres do
    table("games")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :provider_id, :uuid do
      description("The provider who owns this game.")
      allow_nil?(false)
    end

    attribute :provider_game_code, :string do
      description("The unique game code as provided by the vendor.")
      allow_nil?(false)
      constraints(max_length: 128)
    end

    attribute :title, :string do
      description("Display name of the game.")
      allow_nil?(false)
      constraints(max_length: 256)
    end

    attribute :category, :string do
      description("Game category: 'slot', 'table', 'live', 'bingo', etc.")
      allow_nil?(false)
      constraints(max_length: 64)
    end

    attribute :rtp, :decimal do
      description("Return to Player percentage (e.g. 96.5 for 96.5%). Certified value.")
      allow_nil?(false)
    end

    attribute :volatility, :atom do
      description("Volatility rating: :low, :medium, :high")
      constraints(one_of: [:low, :medium, :high])
      allow_nil?(false)
    end

    create_timestamp(:synced_at)
  end

  actions do
    defaults([:read])

    create :sync do
      description("Sync a game from provider catalog. Internal use only.")
      accept([
        :provider_id,
        :provider_game_code,
        :title,
        :category,
        :rtp,
        :volatility
      ])
    end
  end

  policies do
    policy action_type(:read) do
      description("All authenticated users may read game catalog.")
      authorize_if(always())
    end

    policy action(:sync) do
      description("Only system sync processes may create games.")
      authorize_if(always())
    end
  end
end

defmodule IgamingRef.Gaming.GameCatalog do
  @moduledoc """
  Read-only view of available games.

  Aggregates active games and their current versions. Metadata for user-facing
  game selection screens. Updates are driven by provider sync processes.

  Compliance: RG-UK-007 (game certification), RG-MGA-006 (provider agreements)
  """

  use Foundry.Annotations

  @compliance [:RG_UK_007, :RG_MGA_006]
  @telemetry_prefix [:igaming_ref, :gaming, :game_catalog]

  use Ash.Resource,
    domain: IgamingRef.Gaming,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource]

  postgres do
    table("game_catalogs")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :game_id, :uuid do
      description("The game in the catalog.")
      allow_nil?(false)
    end

    attribute :current_version_id, :uuid do
      description("The currently active version of this game.")
      allow_nil?(false)
    end

    attribute :available_regions, :string do
      description("Comma-separated list of region codes where this game is available.")
      allow_nil?(true)
      constraints(max_length: 512)
    end

    attribute :published_at, :utc_datetime do
      description("When this game was added to the catalog.")
      allow_nil?(false)
    end

    attribute :hidden, :boolean do
      description("Whether the game is hidden from player-facing catalog.")
      default(false)
      allow_nil?(false)
    end

    create_timestamp(:inserted_at)
  end

  actions do
    defaults([:read])

    create :add_to_catalog do
      description("Add a game to the catalog. Internal use only.")
      accept([
        :game_id,
        :current_version_id,
        :available_regions,
        :published_at,
        :hidden
      ])
    end

    update :hide do
      description("Hide a game from the player-facing catalog.")
      accept([:hidden])
    end

    update :show do
      description("Show a previously hidden game in the catalog.")
      accept([:hidden])
    end
  end

  policies do
    policy action_type(:read) do
      description("All authenticated users may read the game catalog.")
      authorize_if(always())
    end

    policy action(:add_to_catalog) do
      description("Only system processes may add games to the catalog.")
      authorize_if(always())
    end

    policy action(:hide) do
      description("Only operators may hide games.")
      authorize_if(always())
    end
  end
end

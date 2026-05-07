defmodule IgamingRef.Gaming.GameSession do
  @moduledoc """
  Represents an active player gaming round/session.

  Tracks the lifecycle of a player's gameplay: from session start through
  bets placed to session end or interruption. Used for responsible gambling
  monitoring and audit trail.

  Compliance: RG-MGA-002 (session time tracking), RG-UK-003 (activity logging)
  """

  use Foundry.Annotations
  @compliance [:RG_MGA_002, :RG_UK_003]
  @telemetry_prefix [:igaming_ref, :gaming, :game_session]

  use Ash.Resource,
    domain: IgamingRef.Gaming,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("game_sessions")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :player_id, :uuid do
      description("Player who started this session.")
      allow_nil?(false)
    end

    attribute :game_id, :uuid do
      description("Game being played in this session.")
      allow_nil?(false)
    end

    attribute :status, :atom do
      description("Session lifecycle: :active, :ended, :interrupted")
      constraints(one_of: [:active, :ended, :interrupted])
      default(:active)
      allow_nil?(false)
    end

    attribute :started_at, :utc_datetime do
      description("When the session started.")
      allow_nil?(false)
    end

    attribute :ended_at, :utc_datetime do
      description("When the session ended or was interrupted.")
      allow_nil?(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :player, IgamingRef.Players.Player do
      description("Player who owns this session.")
      attribute_writable?(true)
    end

    belongs_to :game, IgamingRef.Gaming.Game do
      description("Game being played.")
      attribute_writable?(true)
    end
  end

  actions do
    defaults([:read])

    create :start do
      description("Start a new gaming session for a player.")
      accept([:player_id, :game_id])

      change(set_attribute(:started_at, &DateTime.utc_now/0))
    end

    update :end do
      description("End a gaming session normally.")
      accept([])
      change(set_attribute(:status, :ended))
      change(set_attribute(:ended_at, &DateTime.utc_now/0))
    end

    update :interrupt do
      description("Mark session as interrupted (connection loss, timeout).")
      accept([])
      change(set_attribute(:status, :interrupted))
      change(set_attribute(:ended_at, &DateTime.utc_now/0))
    end
  end

  policies do
    policy action_type(:read) do
      description("Players may read their own sessions; operators may read all.")
      authorize_if(always())
    end

    policy action(:start) do
      description("Authenticated players may start sessions.")
      authorize_if(always())
    end

    policy action([:end, :interrupt]) do
      description("System or the owning player may close sessions.")
      authorize_if(always())
    end
  end
end

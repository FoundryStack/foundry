defmodule IgamingRef.Repo.Migrations.AddGameSessions do
  use Ecto.Migration

  def change do
    create table(:game_sessions, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)

      add(
        :player_id,
        references(:players,
          column: :id,
          name: "game_sessions_player_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(
        :game_id,
        references(:games,
          column: :id,
          name: "game_sessions_game_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(:status, :text, null: false, default: "active")
      add(:started_at, :utc_datetime, null: false)
      add(:ended_at, :utc_datetime)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end
  end
end

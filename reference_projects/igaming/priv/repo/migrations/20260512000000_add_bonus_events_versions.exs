defmodule IgamingRef.Repo.Migrations.AddBonusEventsVersions do
  use Ecto.Migration

  def change do
    create table(:bonus_events_versions, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:version_action_type, :text, null: false)

      add(
        :version_source_id,
        references(:bonus_events,
          column: :id,
          name: "bonus_events_versions_version_source_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(:changes, :map)
      add(:version_inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
      add(:version_updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
    end
  end
end

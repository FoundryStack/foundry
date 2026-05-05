defmodule IgamingRef.Repo.Migrations.AddPaperTrailVersionTables do
  use Ecto.Migration

  def change do
    create table(:players_versions, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:version_action_type, :text, null: false)

      add(
        :version_source_id,
        references(:players,
          column: :id,
          name: "players_versions_version_source_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(:changes, :map)
      add(:version_inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
      add(:version_updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
    end

    create table(:wallets_versions, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:version_action_type, :text, null: false)

      add(
        :version_source_id,
        references(:wallets,
          column: :id,
          name: "wallets_versions_version_source_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(:changes, :map)
      add(:version_inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
      add(:version_updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
    end

    create table(:withdrawal_requests_versions, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:version_action_type, :text, null: false)

      add(
        :version_source_id,
        references(:withdrawal_requests,
          column: :id,
          name: "withdrawal_requests_versions_version_source_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(:changes, :map)
      add(:version_inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
      add(:version_updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
    end

    create table(:ledger_entries_versions, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:version_action_type, :text, null: false)

      add(
        :version_source_id,
        references(:ledger_entries,
          column: :id,
          name: "ledger_entries_versions_version_source_id_fkey",
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

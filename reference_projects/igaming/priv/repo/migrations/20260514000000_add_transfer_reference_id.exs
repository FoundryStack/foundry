defmodule IgamingRef.Repo.Migrations.AddTransferReferenceId do
  use Ecto.Migration

  def change do
    alter table(:transfers) do
      add(:reference_id, :text)
    end

    create(unique_index(:transfers, [:reference_id], name: "transfers_unique_reference_id_index"))
  end
end

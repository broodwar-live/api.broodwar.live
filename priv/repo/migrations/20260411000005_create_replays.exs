defmodule Broodwar.Repo.Migrations.CreateReplays do
  use Ecto.Migration

  def change do
    create table(:replays) do
      add :file_hash, :string, null: false
      add :file_path, :string
      add :map_id, references(:maps, on_delete: :nilify_all)
      add :match_id, references(:matches, on_delete: :nilify_all)
      add :player_a_id, references(:players, on_delete: :nilify_all)
      add :player_b_id, references(:players, on_delete: :nilify_all)
      add :race_a, :string
      add :race_b, :string
      add :duration, :integer
      add :game_version, :string
      add :played_at, :utc_datetime
      add :parsed_data, :string

      timestamps()
    end

    create unique_index(:replays, [:file_hash])
    create index(:replays, [:map_id])
    create index(:replays, [:match_id])
    create index(:replays, [:player_a_id])
    create index(:replays, [:player_b_id])
  end
end

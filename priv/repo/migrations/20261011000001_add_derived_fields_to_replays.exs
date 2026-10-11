defmodule Broodwar.Repo.Migrations.AddDerivedFieldsToReplays do
  use Ecto.Migration

  # Denormalized columns derived from parsed_data so list/stats/openings
  # queries can filter in SQL without loading the (large) parsed_data JSON.
  def change do
    alter table(:replays) do
      add :matchup, :string
      add :map_name_normalized, :string
      add :player_a_name, :string
      add :player_b_name, :string
      add :winner_name, :string
      add :classification_a, :string
      add :classification_b, :string
      # "upload" (anonymous API), "import" (operator batch), "admin"
      add :source, :string, null: false, default: "upload"
      # Set once a trusted path has linked players and applied Elo, so a
      # replay is never rated twice.
      add :rated_at, :utc_datetime
    end

    create index(:replays, [:matchup])
    create index(:replays, [:player_a_name])
    create index(:replays, [:player_b_name])
    create index(:replays, [:inserted_at])
  end
end

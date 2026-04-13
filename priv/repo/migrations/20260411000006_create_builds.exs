defmodule Broodwar.Repo.Migrations.CreateBuilds do
  use Ecto.Migration

  def change do
    create table(:builds) do
      add :name, :string, null: false
      add :race, :string, null: false
      add :matchup, :string, null: false
      add :description, :text
      add :tags, :string, default: "[]"
      add :games, :integer, default: 0
      add :winrate, :integer
      add :upvotes, :integer, default: 0

      timestamps()
    end

    create index(:builds, [:race])
    create index(:builds, [:matchup])

    create table(:build_replays) do
      add :build_id, references(:builds, on_delete: :delete_all), null: false
      add :replay_id, references(:replays, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:build_replays, [:build_id, :replay_id])
  end
end

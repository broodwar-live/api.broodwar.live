defmodule Broodwar.Repo.Migrations.CreateMatches do
  use Ecto.Migration

  def change do
    create table(:matches) do
      add :tournament_id, references(:tournaments, on_delete: :nilify_all)
      add :round, :string
      add :map_id, references(:maps, on_delete: :nilify_all)
      add :player_a_id, references(:players, on_delete: :restrict), null: false
      add :player_b_id, references(:players, on_delete: :restrict), null: false
      add :race_a, :string, null: false
      add :race_b, :string, null: false
      add :score_a, :integer, default: 0
      add :score_b, :integer, default: 0
      add :played_at, :utc_datetime
      add :source, :string

      timestamps()
    end

    create index(:matches, [:tournament_id])
    create index(:matches, [:player_a_id])
    create index(:matches, [:player_b_id])
    create index(:matches, [:map_id])
    create index(:matches, [:played_at])
  end
end

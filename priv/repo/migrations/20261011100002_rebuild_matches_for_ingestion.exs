defmodule Broodwar.Repo.Migrations.RebuildMatchesForIngestion do
  use Ecto.Migration

  # SQLite cannot drop NOT NULL, so the table is rebuilt: races become
  # nullable (not every source records them) and series gain provenance
  # (Liquipedia page + match id + revision) for idempotent upserts and
  # CC-BY-SA attribution. Seeded (fabricated) matches are not carried over.
  def up do
    create table(:matches_new) do
      add :tournament_id, references(:tournaments, on_delete: :nilify_all)
      add :stage, :string
      add :round, :string
      add :map_id, references(:maps, on_delete: :nilify_all)
      add :player_a_id, references(:players, on_delete: :restrict), null: false
      add :player_b_id, references(:players, on_delete: :restrict), null: false
      add :winner_id, references(:players, on_delete: :restrict)
      add :race_a, :string
      add :race_b, :string
      add :score_a, :integer, default: 0
      add :score_b, :integer, default: 0
      add :best_of, :integer
      add :walkover, :boolean, null: false, default: false
      add :played_at, :utc_datetime
      add :date_precision, :string
      add :source, :string
      add :source_page, :string
      add :source_match_id, :string
      add :source_revision_id, :integer
      add :page_order, :integer

      timestamps()
    end

    execute """
    INSERT INTO matches_new (id, tournament_id, round, map_id, player_a_id, player_b_id,
      race_a, race_b, score_a, score_b, played_at, source, inserted_at, updated_at)
    SELECT id, tournament_id, round, map_id, player_a_id, player_b_id,
      race_a, race_b, score_a, score_b, played_at, source, inserted_at, updated_at
    FROM matches WHERE source IS NULL OR source != 'seed'
    """

    drop table(:matches)
    rename table(:matches_new), to: table(:matches)

    create index(:matches, [:tournament_id])
    create index(:matches, [:player_a_id])
    create index(:matches, [:player_b_id])
    create index(:matches, [:map_id])
    create index(:matches, [:played_at])
    create unique_index(:matches, [:source_page, :source_match_id])
  end

  def down do
    create table(:matches_old) do
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

    execute """
    INSERT INTO matches_old (id, tournament_id, round, map_id, player_a_id, player_b_id,
      race_a, race_b, score_a, score_b, played_at, source, inserted_at, updated_at)
    SELECT id, tournament_id, round, map_id, player_a_id, player_b_id,
      race_a, race_b, score_a, score_b, played_at, source, inserted_at, updated_at
    FROM matches WHERE race_a IS NOT NULL AND race_b IS NOT NULL
    """

    drop table(:matches)
    rename table(:matches_old), to: table(:matches)

    create index(:matches, [:tournament_id])
    create index(:matches, [:player_a_id])
    create index(:matches, [:player_b_id])
    create index(:matches, [:map_id])
    create index(:matches, [:played_at])
  end
end

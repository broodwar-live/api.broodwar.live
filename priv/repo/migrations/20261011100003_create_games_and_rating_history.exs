defmodule Broodwar.Repo.Migrations.CreateGamesAndRatingHistory do
  use Ecto.Migration

  def change do
    # One row per map played. Ratings and map/balance stats are computed
    # from games, never from series scores.
    create table(:games) do
      add :match_id, references(:matches, on_delete: :delete_all)
      add :replay_id, references(:replays, on_delete: :delete_all)
      add :game_number, :integer, null: false, default: 1
      add :map_id, references(:maps, on_delete: :nilify_all)
      add :map_name, :string
      add :player_a_id, references(:players, on_delete: :restrict), null: false
      add :player_b_id, references(:players, on_delete: :restrict), null: false
      add :winner_id, references(:players, on_delete: :restrict), null: false
      add :race_a, :string
      add :race_b, :string
      add :played_at, :utc_datetime
      # Score-only series: game exists, map and order are unknown.
      add :inferred, :boolean, null: false, default: false
      # "liquipedia" | "replay"
      add :source, :string, null: false
      add :source_page, :string
      add :page_order, :integer

      timestamps()
    end

    create unique_index(:games, [:match_id, :game_number])
    create unique_index(:games, [:replay_id])
    create index(:games, [:player_a_id])
    create index(:games, [:player_b_id])
    create index(:games, [:map_id])
    create index(:games, [:played_at])

    # Rebuilt from scratch by Broodwar.Ratings.recompute/0.
    create table(:rating_history) do
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :opponent_id, references(:players, on_delete: :delete_all), null: false
      add :won, :boolean, null: false
      add :rating_before, :float, null: false
      add :rating_after, :float, null: false
      add :games_played, :integer, null: false
      add :played_at, :utc_datetime
      add :sequence, :integer, null: false
    end

    create index(:rating_history, [:player_id, :sequence])
    create index(:rating_history, [:game_id])

    alter table(:players) do
      add :rated_games, :integer, null: false, default: 0
      add :last_played_at, :utc_datetime
    end

    # Ratings so far were seeded by hand, not computed. Clear them; the
    # next recompute fills in real values from games.
    execute "UPDATE players SET rating = NULL", "SELECT 1"
  end
end

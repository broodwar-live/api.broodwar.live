defmodule Mix.Tasks.Broodwar.Seed do
  @moduledoc """
  Seed the database with player profiles and tournament data from Liquipedia.

  ## Usage

      mix broodwar.seed              # Sync players + all tournament series
      mix broodwar.seed --players    # Sync players only
      mix broodwar.seed --tournaments # Sync tournaments only

  This is safe to run multiple times — it upserts existing records.
  Rate limited to ~1 request per 2 seconds per Liquipedia's terms.
  """
  use Mix.Task

  @shortdoc "Seed players and tournaments from Liquipedia"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    cond do
      "--players" in args ->
        seed_players()

      "--tournaments" in args ->
        seed_tournaments()

      true ->
        seed_players()
        seed_tournaments()
    end

    Mix.shell().info("Seed complete.")
  end

  defp seed_players do
    Mix.shell().info("Syncing player profiles from Liquipedia...")
    Broodwar.Ingestion.PlayerSync.sync_all()
  end

  defp seed_tournaments do
    Mix.shell().info("Syncing tournament data from Liquipedia...")
    Broodwar.Ingestion.TournamentSync.sync_all_series()
    Mix.shell().info("Tournament sync jobs enqueued. They will run in the :ingestion queue.")
  end
end

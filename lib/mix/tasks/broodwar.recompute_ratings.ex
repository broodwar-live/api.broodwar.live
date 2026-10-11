defmodule Mix.Tasks.Broodwar.RecomputeRatings do
  @moduledoc """
  Rebuild all Elo ratings and rating history from games, in one
  transaction. Deterministic: running it twice gives identical results.

      mix broodwar.recompute_ratings
  """
  use Mix.Task

  @shortdoc "Recompute Elo ratings from all games"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case Broodwar.Ratings.recompute() do
      {:ok, stats} ->
        Mix.shell().info(
          "Rated #{stats.games} games for #{stats.players} players " <>
            "(#{stats.undated} undated games skipped)."
        )

      {:error, reason} ->
        Mix.raise("Recompute failed: #{inspect(reason)}")
    end
  end
end

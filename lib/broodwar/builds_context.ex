defmodule Broodwar.BuildsContext do
  import Ecto.Query
  alias Broodwar.Repo
  alias Broodwar.Builds.Build

  def list_builds(opts \\ []) do
    Build
    |> order_by(desc: :games)
    |> maybe_filter_race(opts[:race])
    |> maybe_filter_matchup(opts[:matchup])
    |> Repo.all()
  end

  def get_build!(id), do: Repo.get!(Build, id)

  defp maybe_filter_race(query, nil), do: query
  defp maybe_filter_race(query, race), do: where(query, [b], b.race == ^race)

  defp maybe_filter_matchup(query, nil), do: query
  defp maybe_filter_matchup(query, matchup), do: where(query, [b], b.matchup == ^matchup)
end

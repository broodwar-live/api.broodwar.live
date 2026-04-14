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

  @doc """
  Aggregate opening classifications from replay data.

  Uses DB columns (classification_a/b, matchup) when available.
  Filterable by race and matchup.
  """
  def list_openings(opts \\ []) do
    alias Broodwar.Replays.Replay

    matchup_filter = opts[:matchup]

    query =
      from(r in Replay,
        where: not is_nil(r.classification_a) or not is_nil(r.classification_b),
        select: %{
          classification_a: r.classification_a,
          classification_b: r.classification_b,
          race_a: r.race_a,
          race_b: r.race_b,
          matchup: r.matchup,
          winner_id: r.winner_id,
          parsed_data: r.parsed_data
        }
      )

    query =
      if matchup_filter,
        do: where(query, [r], r.matchup == ^matchup_filter),
        else: query

    replays = Repo.all(query)
    race_filter = opts[:race]

    # Build entries from DB columns + parsed_data classifications.
    entries =
      replays
      |> Enum.flat_map(fn r ->
        classifications = (r.parsed_data || %{})["classifications"] || []
        winner_name = get_in(r.parsed_data || %{}, ["metadata", "result", "player_name"])
        players = get_in(r.parsed_data || %{}, ["header", "players"]) || []

        [
          build_entry(r.classification_a, Enum.at(classifications, 0), r.race_a, r.matchup, Enum.at(players, 0), winner_name),
          build_entry(r.classification_b, Enum.at(classifications, 1), r.race_b, r.matchup, Enum.at(players, 1), winner_name)
        ]
        |> Enum.reject(&is_nil/1)
      end)

    entries =
      if race_filter, do: Enum.filter(entries, &(&1.race == race_filter)), else: entries

    entries
    |> Enum.group_by(&{&1.tag, &1.name, &1.race})
    |> Enum.map(fn {{tag, name, race}, group} ->
      total = length(group)
      wins = Enum.count(group, & &1.won)
      winrate = if total > 0, do: Float.round(wins / total * 100, 1), else: 0.0
      matchups = group |> Enum.map(& &1.matchup) |> Enum.reject(&is_nil/1) |> Enum.frequencies()
      %{tag: tag, name: name, race: race, games: total, wins: wins, winrate: winrate, matchups: matchups}
    end)
    |> Enum.sort_by(& &1.games, :desc)
  end

  defp build_entry(tag, classification, race, matchup, player, winner_name) do
    tag = tag || (classification && classification["tag"])
    return_nil_if_empty(tag, fn ->
      name = (classification && classification["name"]) || tag
      player_name = player && player["name"]
      %{
        tag: tag,
        name: name,
        race: race || (classification && classification["race"]),
        matchup: matchup,
        won: player_name != nil and player_name == winner_name
      }
    end)
  end

  defp return_nil_if_empty(nil, _fun), do: nil
  defp return_nil_if_empty("unknown", _fun), do: nil
  defp return_nil_if_empty(_tag, fun), do: fun.()
end

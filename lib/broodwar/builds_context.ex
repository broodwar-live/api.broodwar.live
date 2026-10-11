defmodule Broodwar.BuildsContext do
  @moduledoc """
  Context for curated build orders and replay-derived opening statistics.
  """
  import Ecto.Query
  alias Broodwar.Builds.Build
  alias Broodwar.Pagination
  alias Broodwar.Repo

  def list_builds(opts \\ []) do
    Build
    |> order_by(desc: :games)
    |> maybe_filter_race(opts[:race])
    |> maybe_filter_matchup(opts[:matchup])
    |> Pagination.paginate(opts)
    |> Repo.all()
  end

  def get_build!(id), do: Repo.get!(Build, id)

  defp maybe_filter_race(query, nil), do: query
  defp maybe_filter_race(query, race), do: where(query, [b], b.race == ^race)

  defp maybe_filter_matchup(query, nil), do: query
  defp maybe_filter_matchup(query, matchup), do: where(query, [b], b.matchup == ^matchup)

  @doc """
  Aggregate opening classifications from replay data.

  Reads only denormalized columns plus two small JSON paths, never the full
  `parsed_data`. Filterable by race (`"T"`, `"P"`, `"Z"`) and matchup.
  """
  def list_openings(opts \\ []) do
    alias Broodwar.Replays.Replay

    query =
      from(r in Replay,
        where: not is_nil(r.classification_a) or not is_nil(r.classification_b),
        select: %{
          classification_a: r.classification_a,
          classification_b: r.classification_b,
          name_a: fragment("json_extract(?, '$.classifications[0].name')", r.parsed_data),
          name_b: fragment("json_extract(?, '$.classifications[1].name')", r.parsed_data),
          race_a: r.race_a,
          race_b: r.race_b,
          player_a_name: r.player_a_name,
          player_b_name: r.player_b_name,
          winner_name: r.winner_name,
          matchup: r.matchup
        }
      )

    query
    |> maybe_filter_matchup(opts[:matchup])
    |> Repo.all()
    |> Enum.flat_map(&opening_entries/1)
    |> maybe_filter_entry_race(opts[:race])
    |> Enum.group_by(&{&1.tag, &1.name, &1.race})
    |> Enum.map(&summarize_opening/1)
    |> Enum.sort_by(& &1.games, :desc)
  end

  defp opening_entries(r) do
    [
      opening_entry(r.classification_a, r.name_a, r.race_a, r.player_a_name, r),
      opening_entry(r.classification_b, r.name_b, r.race_b, r.player_b_name, r)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp opening_entry(tag, _name, _race, _player, _r) when tag in [nil, "unknown"], do: nil

  defp opening_entry(tag, name, race, player_name, r) do
    %{
      tag: tag,
      name: name || tag,
      race: race,
      matchup: r.matchup,
      won: player_name != nil and player_name == r.winner_name
    }
  end

  defp maybe_filter_entry_race(entries, nil), do: entries
  defp maybe_filter_entry_race(entries, race), do: Enum.filter(entries, &(&1.race == race))

  defp summarize_opening({{tag, name, race}, group}) do
    total = length(group)
    wins = Enum.count(group, & &1.won)
    winrate = if total > 0, do: Float.round(wins / total * 100, 1), else: 0.0
    matchups = group |> Enum.map(& &1.matchup) |> Enum.reject(&is_nil/1) |> Enum.frequencies()

    %{
      tag: tag,
      name: name,
      race: race,
      games: total,
      wins: wins,
      winrate: winrate,
      matchups: matchups
    }
  end
end

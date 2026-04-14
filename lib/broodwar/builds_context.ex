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
  Aggregate opening classifications from parsed replay data.

  Returns a list of openings with name, tag, race, game count, and winrate,
  derived from the `classifications` field in replay parsed_data.
  Filterable by race and matchup.
  """
  def list_openings(opts \\ []) do
    alias Broodwar.Replays.Replay

    replays =
      Repo.all(
        from(r in Replay,
          where: not is_nil(r.parsed_data),
          select: r.parsed_data,
          limit: 500
        )
      )

    race_filter = opts[:race]
    matchup_filter = opts[:matchup]

    # Extract classification + matchup + winner for each player in each replay.
    entries =
      replays
      |> Enum.flat_map(fn pd ->
        classifications = pd["classifications"] || []
        players = get_in(pd, ["header", "players"]) || []
        matchup_code = get_in(pd, ["metadata", "matchup", "code"])
        winner_name = get_in(pd, ["metadata", "result", "player_name"])

        classifications
        |> Enum.with_index()
        |> Enum.map(fn {cls, i} ->
          player = Enum.at(players, i)
          player_name = player && player["name"]

          %{
            tag: cls["tag"],
            name: cls["name"],
            race: cls["race"],
            matchup: matchup_code,
            won: player_name != nil and player_name == winner_name
          }
        end)
        |> Enum.reject(fn e -> is_nil(e.tag) or e.tag == "unknown" end)
      end)

    # Apply filters.
    entries =
      entries
      |> then(fn es ->
        if race_filter, do: Enum.filter(es, &(&1.race == race_filter)), else: es
      end)
      |> then(fn es ->
        if matchup_filter, do: Enum.filter(es, &(&1.matchup == matchup_filter)), else: es
      end)

    # Aggregate by tag.
    entries
    |> Enum.group_by(&{&1.tag, &1.name, &1.race})
    |> Enum.map(fn {{tag, name, race}, group} ->
      total = length(group)
      wins = Enum.count(group, & &1.won)
      winrate = if total > 0, do: Float.round(wins / total * 100, 1), else: 0.0

      matchups =
        group
        |> Enum.map(& &1.matchup)
        |> Enum.reject(&is_nil/1)
        |> Enum.frequencies()

      %{
        tag: tag,
        name: name,
        race: race,
        games: total,
        wins: wins,
        winrate: winrate,
        matchups: matchups
      }
    end)
    |> Enum.sort_by(& &1.games, :desc)
  end
end

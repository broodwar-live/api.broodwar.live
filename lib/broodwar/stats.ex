defmodule Broodwar.Stats do
  @moduledoc """
  Aggregate statistics computed from games (one row per map played):
  head-to-head records, matchup winrates per map and per period.

  Every aggregate carries its sample size `n`. Walkovers never produce
  games, so they are excluded everywhere except the series record, where
  they are counted separately. Map and race statistics skip `inferred`
  games (score-only series with unknown maps) and games where a race is
  unknown or random.
  """
  import Ecto.Query

  alias Broodwar.Ingestion.Liquipedia
  alias Broodwar.Matches.Game
  alias Broodwar.Matches.Match
  alias Broodwar.Repo

  # Non-mirror matchups in the canonical order from the API conventions;
  # winrates are for the first-named race.
  @matchups [{"TvZ", "T", "Z"}, {"PvT", "P", "T"}, {"ZvP", "Z", "P"}]
  @mirrors [{"TvT", "T"}, {"PvP", "P"}, {"ZvZ", "Z"}]

  @doc """
  Attribution for responses built from Liquipedia data (CC-BY-SA 3.0).
  """
  def attribution do
    %{
      name: "Liquipedia",
      url: "https://liquipedia.net/starcraft",
      license: "CC-BY-SA 3.0",
      license_url: "https://creativecommons.org/licenses/by-sa/3.0/",
      note:
        "Match results from Liquipedia contributors; per-match source pages and " <>
          "revisions are linked on each match. Replay-derived games come from " <>
          "admin-verified replays."
    }
  end

  @doc "Source block for a single series."
  def match_source(%Match{source: "liquipedia", source_page: page} = m) when is_binary(page) do
    %{
      type: "liquipedia",
      page: page,
      url: Liquipedia.page_url(page),
      revision_id: m.source_revision_id,
      revision_url: m.source_revision_id && Liquipedia.revision_url(m.source_revision_id),
      license: "CC-BY-SA 3.0"
    }
  end

  def match_source(%Match{source: source}), do: %{type: source}

  # -- Head to head --

  @doc """
  Head-to-head between two players: series record, game record, games by
  map and by matchup (all from `player_a`'s perspective), and the series.
  """
  def head_to_head(a_id, b_id) do
    matches =
      Repo.all(
        from m in Match,
          where:
            (m.player_a_id == ^a_id and m.player_b_id == ^b_id) or
              (m.player_a_id == ^b_id and m.player_b_id == ^a_id),
          order_by: [desc: m.played_at, desc: m.id],
          preload: [:tournament, :player_a, :player_b, :winner, games: :map]
      )

    games =
      Repo.all(
        from g in Game,
          where:
            (g.player_a_id == ^a_id and g.player_b_id == ^b_id) or
              (g.player_a_id == ^b_id and g.player_b_id == ^a_id),
          left_join: map in assoc(g, :map),
          select: %{
            a_won: g.winner_id == ^a_id,
            a_race:
              fragment(
                "CASE WHEN ? = ? THEN ? ELSE ? END",
                g.player_a_id,
                ^a_id,
                g.race_a,
                g.race_b
              ),
            b_race:
              fragment(
                "CASE WHEN ? = ? THEN ? ELSE ? END",
                g.player_a_id,
                ^a_id,
                g.race_b,
                g.race_a
              ),
            map_id: map.id,
            map_name: map.name,
            inferred: g.inferred
          }
      )

    decided = Enum.reject(matches, &is_nil(&1.winner_id))

    %{
      series: %{
        a_wins: Enum.count(decided, &(&1.winner_id == a_id)),
        b_wins: Enum.count(decided, &(&1.winner_id == b_id)),
        n: length(decided),
        walkovers: Enum.count(decided, & &1.walkover)
      },
      games: record(games),
      by_map:
        games
        |> Enum.reject(&(&1.inferred or is_nil(&1.map_id)))
        |> Enum.group_by(&{&1.map_id, &1.map_name})
        |> Enum.map(fn {{id, name}, gs} ->
          Map.merge(%{map: %{id: id, name: name}}, record(gs))
        end)
        |> Enum.sort_by(&{-&1.n, &1.map.name}),
      by_matchup:
        games
        |> Enum.reject(&(is_nil(&1.a_race) or is_nil(&1.b_race)))
        |> Enum.group_by(&"#{&1.a_race}v#{&1.b_race}")
        |> Enum.map(fn {mu, gs} -> Map.put(record(gs), :matchup, mu) end)
        |> Enum.sort_by(&{-&1.n, &1.matchup}),
      matches: matches
    }
  end

  defp record(games) do
    a = Enum.count(games, & &1.a_won)
    %{a_wins: a, b_wins: length(games) - a, n: length(games)}
  end

  # -- Matchup winrates --

  @doc """
  Matchup winrates on one map, from non-inferred games with known races.
  """
  def map_stats(map_id), do: matchup_table(race_rows(map_id: map_id))

  @doc """
  Matchup winrates overall and per year. Options: `:map_id`.
  """
  def balance(opts \\ []) do
    rows = race_rows(opts)

    by_year =
      rows
      |> Enum.reject(&is_nil(&1.year))
      |> Enum.group_by(& &1.year)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {year, rs} -> %{year: year, n: length(rs), matchups: matchup_table(rs)} end)

    %{n: length(rows), overall: matchup_table(rows), by_year: by_year}
  end

  defp race_rows(opts) do
    Game
    |> where([g], not g.inferred and g.race_a in ["T", "P", "Z"] and g.race_b in ["T", "P", "Z"])
    |> then(fn q -> if opts[:map_id], do: where(q, [g], g.map_id == ^opts[:map_id]), else: q end)
    |> select([g], %{
      race_a: g.race_a,
      race_b: g.race_b,
      a_won: g.winner_id == g.player_a_id,
      year: fragment("CAST(strftime('%Y', ?) AS INTEGER)", g.played_at)
    })
    |> Repo.all()
  end

  defp matchup_table(rows) do
    non_mirror =
      Enum.map(@matchups, fn {name, first, second} ->
        relevant =
          Enum.filter(rows, fn r ->
            {r.race_a, r.race_b} in [{first, second}, {second, first}]
          end)

        first_wins =
          Enum.count(relevant, fn r ->
            (r.race_a == first and r.a_won) or (r.race_b == first and not r.a_won)
          end)

        n = length(relevant)

        %{
          matchup: name,
          n: n,
          wins: first_wins,
          losses: n - first_wins,
          winrate: if(n > 0, do: Float.round(first_wins / n * 100, 1))
        }
      end)

    mirrors =
      Enum.map(@mirrors, fn {name, race} ->
        n = Enum.count(rows, &(&1.race_a == race and &1.race_b == race))
        %{matchup: name, n: n, wins: nil, losses: nil, winrate: nil}
      end)

    non_mirror ++ mirrors
  end
end

defmodule Broodwar.Players do
  @moduledoc """
  Context for player profiles, tournament records and replay-derived stats.
  """
  import Ecto.Query
  alias Broodwar.Pagination
  alias Broodwar.Players.Player
  alias Broodwar.Repo

  def list_players(opts \\ []) do
    Player
    |> order_by(desc: :rating)
    |> maybe_filter_race(opts[:race])
    |> maybe_filter_status(opts[:status])
    |> maybe_search(opts[:search])
    |> Pagination.paginate(opts)
    |> Repo.all()
  end

  def get_player!(id), do: Repo.get!(Player, id)

  def get_player_matches(player_id) do
    alias Broodwar.Matches.Match

    Match
    |> where([m], m.player_a_id == ^player_id or m.player_b_id == ^player_id)
    |> order_by(desc: :played_at)
    |> preload([:tournament, :player_a, :player_b, :map])
    |> Repo.all()
  end

  defp maybe_filter_race(query, nil), do: query
  defp maybe_filter_race(query, race), do: where(query, [p], p.race == ^race)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [p], p.status == ^status)

  @doc """
  Returns all tournament matches involving this player, sourced from
  the Liquipedia match data stored in tournaments.
  """
  def get_tournament_matches(player_name) do
    alias Broodwar.Tournaments.Tournament

    Repo.all(from t in Tournament, where: not is_nil(t.liquipedia_data))
    |> Enum.flat_map(fn t ->
      (t.liquipedia_data["matches"] || [])
      |> Enum.filter(&(&1["opponent1"] == player_name or &1["opponent2"] == player_name))
      |> Enum.map(&player_match_view(t, &1, player_name))
    end)
    |> Enum.sort_by(fn m -> m.date || "" end, :desc)
  end

  defp player_match_view(tournament, match, player_name) do
    is_p1 = match["opponent1"] == player_name
    opponent = if is_p1, do: match["opponent2"], else: match["opponent1"]
    {s1, s2} = split_score(match["score"])
    {my_score, opp_score} = if is_p1, do: {s1, s2}, else: {s2, s1}

    %{
      tournament: "#{tournament.short_name} S#{tournament.season}",
      tournament_slug: String.downcase(tournament.short_name),
      season: tournament.season,
      context: match["context"],
      date: match["date"],
      opponent: opponent,
      my_score: my_score,
      opp_score: opp_score,
      score: match["score"],
      result: match_result(match["winner"], player_name),
      maps: match["maps"] || []
    }
  end

  defp split_score(score) when is_binary(score) do
    case String.split(score, "-", parts: 2) do
      [s1, s2] -> {s1, s2}
      _ -> {"0", "0"}
    end
  end

  defp split_score(_), do: {"0", "0"}

  defp match_result(nil, _player_name), do: :unknown
  defp match_result(player_name, player_name), do: :win
  defp match_result(_winner, _player_name), do: :loss

  @doc """
  Computes win/loss stats for a player from tournament match data.
  """
  def compute_stats(tournament_matches) do
    wins = Enum.count(tournament_matches, &(&1.result == :win))
    losses = Enum.count(tournament_matches, &(&1.result == :loss))
    total = wins + losses
    winrate = if total > 0, do: Float.round(wins / total * 100, 1), else: 0.0

    # By opponent
    vs_stats =
      tournament_matches
      |> Enum.filter(&(&1.result in [:win, :loss]))
      |> Enum.group_by(& &1.opponent)
      |> Enum.map(fn {opp, matches} ->
        w = Enum.count(matches, &(&1.result == :win))
        l = Enum.count(matches, &(&1.result == :loss))
        %{opponent: opp, wins: w, losses: l, total: w + l}
      end)
      |> Enum.sort_by(& &1.total, :desc)

    # Titles (matches in Finals context where player won)
    titles =
      tournament_matches
      |> Enum.filter(fn m ->
        ctx = m.context || ""

        m.result == :win and
          (String.contains?(ctx, "Finals") or String.contains?(ctx, "Grand Final"))
      end)
      |> Enum.map(& &1.tournament)
      |> Enum.uniq()

    %{
      wins: wins,
      losses: losses,
      total: total,
      winrate: winrate,
      vs_stats: vs_stats,
      titles: titles
    }
  end

  @doc """
  Compute replay-based stats for a player: opening frequencies, matchup
  winrates from replay data, and skill profile from the most recent replay.

  Replays are matched by in-game name via indexed columns (most recent
  200), and only the small JSON paths needed are extracted in SQL.
  """
  def compute_replay_stats(player_name) do
    alias Broodwar.Replays.Replay

    rows =
      Repo.all(
        from(r in Replay,
          where: r.player_a_name == ^player_name or r.player_b_name == ^player_name,
          order_by: [desc: r.inserted_at, desc: r.id],
          limit: 200,
          select: %{
            slot: fragment("CASE WHEN ? = ? THEN 0 ELSE 1 END", r.player_a_name, ^player_name),
            tag_a: r.classification_a,
            tag_b: r.classification_b,
            name_a: fragment("json_extract(?, '$.classifications[0].name')", r.parsed_data),
            name_b: fragment("json_extract(?, '$.classifications[1].name')", r.parsed_data),
            skill_a: fragment("json_extract(?, '$.skill_profiles[0]')", r.parsed_data),
            skill_b: fragment("json_extract(?, '$.skill_profiles[1]')", r.parsed_data),
            matchup: r.matchup,
            winner_name: r.winner_name
          }
        )
      )

    %{
      replay_count: length(rows),
      openings: opening_frequencies(rows),
      matchup_winrates: matchup_winrates(rows, player_name),
      skill_profile: latest_skill_profile(rows)
    }
  end

  defp opening_frequencies(rows) do
    rows
    |> Enum.map(fn
      %{slot: 0} = r -> {r.tag_a, r.name_a}
      r -> {r.tag_b, r.name_b}
    end)
    |> Enum.reject(fn {tag, _name} -> is_nil(tag) end)
    |> Enum.group_by(fn {tag, _name} -> tag end)
    |> Enum.map(fn {tag, [{_tag, name} | _] = list} ->
      %{tag: tag, name: name, count: length(list)}
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp matchup_winrates(rows, player_name) do
    rows
    |> Enum.reject(&is_nil(&1.matchup))
    |> Enum.group_by(& &1.matchup)
    |> Enum.map(fn {matchup, in_mu} ->
      wins = Enum.count(in_mu, &(&1.winner_name == player_name))
      total = length(in_mu)

      %{
        matchup: matchup,
        wins: wins,
        losses: total - wins,
        total: total,
        winrate: Float.round(wins / total * 100, 1)
      }
    end)
    |> Enum.sort_by(& &1.total, :desc)
  end

  defp latest_skill_profile([]), do: nil

  defp latest_skill_profile([latest | _]) do
    json = if latest.slot == 0, do: latest.skill_a, else: latest.skill_b
    decode_json(json)
  end

  defp decode_json(nil), do: nil
  defp decode_json(map) when is_map(map), do: map

  defp decode_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, value} -> value
      {:error, _} -> nil
    end
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    term = "%#{search}%"

    where(
      query,
      [p],
      like(p.name, ^term) or like(p.real_name, ^term) or like(p.real_name_ko, ^term)
    )
  end
end

defmodule Broodwar.Players do
  import Ecto.Query
  alias Broodwar.Repo
  alias Broodwar.Players.Player

  def list_players(opts \\ []) do
    Player
    |> order_by(desc: :rating)
    |> maybe_filter_race(opts[:race])
    |> maybe_filter_status(opts[:status])
    |> maybe_search(opts[:search])
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
      |> Enum.filter(fn m ->
        m["opponent1"] == player_name or m["opponent2"] == player_name
      end)
      |> Enum.map(fn m ->
        is_p1 = m["opponent1"] == player_name
        opponent = if is_p1, do: m["opponent2"], else: m["opponent1"]
        [s1, s2] = String.split(m["score"] || "0-0", "-")
        {my_score, opp_score} = if is_p1, do: {s1, s2}, else: {s2, s1}

        result =
          cond do
            m["winner"] == player_name -> :win
            m["winner"] != nil -> :loss
            true -> :unknown
          end

        %{
          tournament: "#{t.short_name} S#{t.season}",
          tournament_slug: String.downcase(t.short_name),
          season: t.season,
          context: m["context"],
          date: m["date"],
          opponent: opponent,
          my_score: my_score,
          opp_score: opp_score,
          score: m["score"],
          result: result,
          maps: m["maps"] || []
        }
      end)
    end)
    |> Enum.sort_by(fn m -> m.date || "" end, :desc)
  end

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
        m.result == :win and (String.contains?(ctx, "Finals") or String.contains?(ctx, "Grand Final"))
      end)
      |> Enum.map(& &1.tournament)
      |> Enum.uniq()

    %{wins: wins, losses: losses, total: total, winrate: winrate, vs_stats: vs_stats, titles: titles}
  end

  @doc """
  Compute replay-based stats for a player: opening frequencies, matchup
  winrates from replay data, and skill profile from the most recent replay.
  """
  def compute_replay_stats(player_name) do
    alias Broodwar.Replays.Replay

    replays =
      Repo.all(
        from(r in Replay,
          where: not is_nil(r.parsed_data),
          order_by: [desc: :inserted_at],
          limit: 200
        )
      )

    # Filter to replays involving this player.
    player_replays =
      Enum.filter(replays, fn r ->
        players = get_in(r.parsed_data, ["header", "players"]) || []
        Enum.any?(players, fn p -> p["name"] == player_name end)
      end)

    if player_replays == [] do
      %{replay_count: 0, openings: [], matchup_winrates: [], skill_profile: nil}
    else
      # Opening frequencies.
      openings =
        player_replays
        |> Enum.flat_map(fn r ->
          players = get_in(r.parsed_data, ["header", "players"]) || []
          classifications = r.parsed_data["classifications"] || []

          players
          |> Enum.with_index()
          |> Enum.filter(fn {p, _i} -> p["name"] == player_name end)
          |> Enum.map(fn {_p, i} -> Enum.at(classifications, i) end)
          |> Enum.reject(&is_nil/1)
        end)
        |> Enum.group_by(fn c -> c["tag"] end)
        |> Enum.map(fn {tag, list} ->
          sample = List.first(list)
          %{tag: tag, name: sample["name"], count: length(list)}
        end)
        |> Enum.sort_by(& &1.count, :desc)

      # Matchup winrates from replay metadata.
      matchup_stats =
        player_replays
        |> Enum.filter(fn r -> r.parsed_data["metadata"] != nil end)
        |> Enum.group_by(fn r ->
          get_in(r.parsed_data, ["metadata", "matchup", "code"])
        end)
        |> Enum.reject(fn {k, _} -> is_nil(k) end)
        |> Enum.map(fn {matchup, replays_in_mu} ->
          wins =
            Enum.count(replays_in_mu, fn r ->
              get_in(r.parsed_data, ["metadata", "result", "player_name"]) == player_name
            end)

          total = length(replays_in_mu)

          %{
            matchup: matchup,
            wins: wins,
            losses: total - wins,
            total: total,
            winrate: if(total > 0, do: Float.round(wins / total * 100, 1), else: 0.0)
          }
        end)
        |> Enum.sort_by(& &1.total, :desc)

      # Skill profile from most recent replay.
      skill_profile =
        player_replays
        |> List.first()
        |> then(fn r ->
          profiles = r.parsed_data["skill_profiles"] || []
          players = get_in(r.parsed_data, ["header", "players"]) || []

          idx =
            Enum.find_index(players, fn p -> p["name"] == player_name end)

          if idx, do: Enum.at(profiles, idx), else: nil
        end)

      %{
        replay_count: length(player_replays),
        openings: openings,
        matchup_winrates: matchup_stats,
        skill_profile: skill_profile
      }
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

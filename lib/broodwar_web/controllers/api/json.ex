defmodule BroodwarWeb.Api.JSON do
  @moduledoc """
  Serialization helpers for converting Ecto schemas to JSON-friendly maps.
  """

  alias Broodwar.Builds.Build
  alias Broodwar.Maps.Map, as: GameMap
  alias Broodwar.Matches.Game
  alias Broodwar.Matches.Match
  alias Broodwar.Players.Player
  alias Broodwar.Replays.Replay
  alias Broodwar.Streams.Stream
  alias Broodwar.Tournaments.Tournament

  @race_names %{"T" => "terran", "P" => "protoss", "Z" => "zerg", "R" => "random"}

  defp race(code), do: @race_names[code]

  def player(%Player{} = p) do
    %{
      id: p.id,
      name: p.name,
      real_name: p.real_name,
      real_name_ko: p.real_name_ko,
      aliases: p.aliases,
      race: race(p.race),
      country: p.country,
      rating: p.rating,
      rated_games: p.rated_games,
      last_played_at: p.last_played_at,
      birth_date: p.birth_date,
      age: Player.age(p),
      team: p.team,
      status: p.status,
      image_url: image_url(p.image_url)
    }
  end

  def player_summary(%Player{} = p) do
    %{
      id: p.id,
      name: p.name,
      race: race(p.race),
      country: p.country,
      rating: p.rating,
      liquipedia_page: p.liquipedia_page
    }
  end

  def match(%Match{} = m) do
    %{
      id: m.id,
      stage: m.stage,
      round: m.round,
      race_a: race(m.race_a),
      race_b: race(m.race_b),
      matchup: matchup_string(m.race_a, m.race_b),
      score_a: m.score_a,
      score_b: m.score_b,
      best_of: m.best_of,
      walkover: m.walkover,
      winner_id: m.winner_id,
      played_at: m.played_at,
      date_precision: m.date_precision,
      source: Broodwar.Stats.match_source(m),
      player_a: maybe_assoc(m.player_a, &player_summary/1),
      player_b: maybe_assoc(m.player_b, &player_summary/1),
      tournament: maybe_assoc(m.tournament, &tournament_summary/1),
      games: maybe_list(m.games, &game/1)
    }
  end

  def game(%Game{} = g) do
    %{
      id: g.id,
      game_number: g.game_number,
      map:
        maybe_assoc(g.map, &game_map_summary/1) || (g.map_name && %{id: nil, name: g.map_name}),
      race_a: race(g.race_a),
      race_b: race(g.race_b),
      winner_id: g.winner_id,
      inferred: g.inferred,
      played_at: g.played_at
    }
  end

  def rating_point(h) do
    %{
      game_id: h.game_id,
      match_id: h.match_id,
      replay_id: h.replay_id,
      played_at: h.played_at,
      result: if(h.won, do: "win", else: "loss"),
      rating_before: Float.round(h.rating_before, 1),
      rating_after: Float.round(h.rating_after, 1),
      games_played: h.games_played,
      opponent: %{id: h.opponent_id, name: h.opponent_name}
    }
  end

  def replay_summary(%Replay{} = r) do
    %{
      id: r.id,
      file_hash: r.file_hash,
      race_a: race(r.race_a),
      race_b: race(r.race_b),
      matchup: matchup_string(r.race_a, r.race_b),
      duration: r.duration,
      game_version: r.game_version,
      played_at: r.played_at,
      player_a: maybe_assoc(r.player_a, &player_summary/1),
      player_b: maybe_assoc(r.player_b, &player_summary/1),
      map: maybe_assoc(r.map, &game_map_summary/1)
    }
  end

  def replay(%Replay{} = r) do
    r
    |> replay_summary()
    |> Elixir.Map.put(:parsed_data, r.parsed_data)
  end

  def build(%Build{} = b) do
    %{
      id: b.id,
      name: b.name,
      race: race(b.race),
      matchup: b.matchup,
      description: b.description,
      tags: b.tags,
      games: b.games,
      winrate: b.winrate,
      upvotes: b.upvotes
    }
  end

  def tournament(%Tournament{} = t) do
    %{
      id: t.id,
      name: t.name,
      short_name: t.short_name,
      type: t.type,
      year: t.year,
      season: t.season
    }
  end

  def tournament_summary(%Tournament{} = t) do
    %{id: t.id, name: t.name, short_name: t.short_name, season: t.season}
  end

  def tournament_detail(%Tournament{} = t) do
    t
    |> tournament()
    |> Elixir.Map.put(:liquipedia_data, t.liquipedia_data)
  end

  def game_map(%GameMap{} = m) do
    %{
      id: m.id,
      name: m.name,
      width: m.width,
      height: m.height,
      tileset: m.tileset,
      spawn_positions: m.spawn_positions
    }
  end

  def game_map_summary(%GameMap{} = m) do
    %{id: m.id, name: m.name}
  end

  def stream(%Stream{} = s) do
    %{
      id: s.id,
      channel_id: s.channel_id,
      platform: s.platform,
      title: s.title,
      is_live: s.is_live,
      viewer_count: s.viewer_count,
      last_seen_at: s.last_seen_at,
      player: maybe_assoc(s.player, &player_summary/1)
    }
  end

  # Player images are hosted by the static site; stored values are paths
  # like "/images/players/flash.png" relative to it.
  defp image_url(nil), do: nil
  defp image_url("/" <> _ = path), do: static_site_url() <> path
  defp image_url(url), do: url

  defp static_site_url do
    Application.get_env(:broodwar, :static_site_url, "https://broodwar.live")
  end

  defp matchup_string(nil, _), do: nil
  defp matchup_string(_, nil), do: nil
  defp matchup_string(a, b), do: "#{a}v#{b}"

  defp maybe_list(%Ecto.Association.NotLoaded{}, _fun), do: nil
  defp maybe_list(list, fun) when is_list(list), do: Enum.map(list, fun)

  defp maybe_assoc(%Ecto.Association.NotLoaded{}, _fun), do: nil
  defp maybe_assoc(nil, _fun), do: nil
  defp maybe_assoc(assoc, fun), do: fun.(assoc)
end

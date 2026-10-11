defmodule Broodwar.ReplayStatsTest do
  use Broodwar.DataCase

  alias Broodwar.BuildsContext
  alias Broodwar.Players
  alias Broodwar.Replays

  @fixture Path.expand("../fixtures/larva_vs_mini.rep", __DIR__)

  setup do
    Broodwar.Cache.invalidate_all()
    {:ok, replay, :created} = Replays.parse_and_save(File.read!(@fixture))
    %{replay: replay}
  end

  test "validate_format/1 with real replay returns :ok" do
    assert Replays.validate_format(File.read!(@fixture)) == :ok
  end

  test "validate_format/1 with arbitrary bytes returns invalid_format" do
    assert Replays.validate_format("hello") == {:error, :invalid_format}
  end

  test "list_openings/1 with race filter aggregates from columns" do
    assert [%{tag: "4pool", race: "Z", games: 1, wins: 1, matchups: %{"PvZ" => 1}} = opening] =
             BuildsContext.list_openings(race: "Z")

    assert opening.name == "4/5 Pool"
    assert BuildsContext.list_openings(race: "T") == []
    assert BuildsContext.list_openings(matchup: "TvT") == []
  end

  test "compute_replay_stats/1 with winning player reports openings and winrate" do
    stats = Players.compute_replay_stats("adultrabbit")

    assert stats.replay_count == 1
    assert [%{tag: "4pool", count: 1}] = stats.openings
    assert [%{matchup: "PvZ", wins: 1, losses: 0}] = stats.matchup_winrates
    assert is_map(stats.skill_profile)
  end

  test "compute_replay_stats/1 with unknown player returns empty stats" do
    assert %{replay_count: 0, openings: [], skill_profile: nil} =
             Players.compute_replay_stats("nobody")
  end
end

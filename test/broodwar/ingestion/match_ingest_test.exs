defmodule Broodwar.Ingestion.MatchIngestTest do
  use Broodwar.DataCase

  alias Broodwar.Ingestion.MatchIngest
  alias Broodwar.Matches.Game
  alias Broodwar.Matches.Match
  alias Broodwar.Players.Identity
  alias Broodwar.Players.Player
  alias Broodwar.Tournaments.Tournament

  @dir Path.expand("../../fixtures/liquipedia", __DIR__)
  @asl17 "AfreecaTV/StarCraft League Remastered/17"
  @asl6 "AfreecaTV/StarCraft League Remastered/6"

  defp ingest(file, title, rev) do
    {:ok, summary} = MatchIngest.ingest_wikitext(title, rev, File.read!(Path.join(@dir, file)))
    summary
  end

  test "ingest_wikitext/3 stores series, games, players and provenance" do
    summary = ingest("asl_s17_rev542482.wiki", @asl17, 542_482)

    assert summary.upserted == 57
    assert summary.games == 100
    assert summary.failed == []
    assert Repo.aggregate(Match, :count) == 57
    assert Repo.aggregate(Game, :count) == 100

    final = Repo.get_by!(Match, source_page: @asl17, source_match_id: "ASL17R08PO_R3M1")
    assert final.source == "liquipedia"
    assert final.source_revision_id == 542_482
    assert final.best_of == 7

    assert %Tournament{name: "ASL Season 17", season: 17} =
             Repo.get!(Tournament, final.tournament_id)

    hero = Repo.get!(Player, final.player_a_id)
    assert hero.name == "hero"
    assert hero.liquipedia_page == "hero"
  end

  test "ingest_wikitext/3 is idempotent" do
    ingest("asl_s17_rev542482.wiki", @asl17, 542_482)

    counts =
      {Repo.aggregate(Match, :count), Repo.aggregate(Game, :count),
       Repo.aggregate(Player, :count)}

    summary = ingest("asl_s17_rev542482.wiki", @asl17, 542_483)

    assert summary.upserted == 57

    assert counts ==
             {Repo.aggregate(Match, :count), Repo.aggregate(Game, :count),
              Repo.aggregate(Player, :count)}

    assert Repo.all(from m in Match, select: m.source_revision_id, distinct: true) == [542_483]
  end

  test "ingest_wikitext/3 deletes series removed from the page" do
    ingest("asl_s17_rev542482.wiki", @asl17, 1)

    text = """
    {{Matchlist|id=ASL17R24GA
    |M1={{Match|date=2024-02-26|opponent1={{1Opponent|Light}}|opponent2={{1Opponent|ZeLoT}}|map1={{Map|map=Radeon|winner=1}}}}
    }}
    """

    {:ok, summary} = MatchIngest.ingest_wikitext(@asl17, 2, text)
    assert summary.deleted == 56
    assert Repo.aggregate(Match, :count) == 1
  end

  test "ingest_wikitext/3 stores walkovers without games" do
    ingest("asl_s6_rev538330.wiki", @asl6, 538_330)

    wo = Repo.get_by!(Match, source_page: @asl6, source_match_id: "fndC08cTEd_M1")
    assert wo.walkover
    assert Repo.all(from g in Game, where: g.match_id == ^wo.id) == []
    assert Repo.get!(Player, wo.winner_id).name == "Sharp"
  end

  test "ingest_wikitext/3 links to an existing player by case-insensitive page alias" do
    {:ok, snow} =
      Repo.insert(
        Player.changeset(%Player{}, %{name: "Snow", race: "P", liquipedia_page: "Snow"})
      )

    Identity.add_alias(snow, "Snow", "liquipedia")

    ingest("asl_s17_rev542482.wiki", @asl17, 1)

    # The page links "SnOw"; no duplicate player is created.
    assert Repo.all(from p in Player, where: fragment("lower(?)", p.name) == "snow") == [
             Repo.get!(Player, snow.id)
           ]

    assert Repo.exists?(
             from m in Match, where: m.player_a_id == ^snow.id or m.player_b_id == ^snow.id
           )
  end

  test "ingest_wikitext/3 reports an ambiguous player and keeps the rest of the page" do
    # Two unlinked players share the alias "Light".
    for name <- ["Light", "Light (2)"] do
      {:ok, p} = Repo.insert(Player.changeset(%Player{}, %{name: name}))
      Identity.add_alias(p, "Light", "profile")
    end

    summary = ingest("asl_s17_rev542482.wiki", @asl17, 1)

    light_series = summary.failed |> Enum.map(& &1.key)
    assert "ASL17R24GA_M1" in light_series
    assert Enum.all?(summary.failed, &(&1.reason =~ "ambiguous player Light"))
    assert summary.upserted == 57 - length(summary.failed)
    assert summary.upserted > 40
  end

  test "fill_missing_races/1 sets races from player pages and backfills games" do
    ingest("asl_s17_rev542482.wiki", @asl17, 1)

    fetch = fn titles ->
      send(self(), {:fetched, length(titles)})

      {:ok,
       titles
       |> Enum.filter(&(&1 in ["hero", "Soulkey"]))
       |> Map.new(&{&1, "{{Infobox player\n|id=#{&1}\n|race=z\n}}\nBio"})}
    end

    assert {:ok, 2} = MatchIngest.fill_missing_races(fetch: fetch)
    # 28 players without a race fit in one batched request.
    assert_received {:fetched, n} when n <= 50
    refute_received {:fetched, _}

    final = Repo.get_by!(Match, source_match_id: "ASL17R08PO_R3M1")
    assert {final.race_a, final.race_b} == {"Z", "Z"}

    assert Repo.all(from g in Game, where: g.match_id == ^final.id, select: g.race_a)
           |> Enum.uniq() == ["Z"]
  end
end

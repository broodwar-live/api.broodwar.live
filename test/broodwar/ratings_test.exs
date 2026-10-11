defmodule Broodwar.RatingsTest do
  use Broodwar.DataCase

  alias Broodwar.Ingestion.MatchIngest
  alias Broodwar.Players.Player
  alias Broodwar.Ratings
  alias Broodwar.Ratings.RatingHistory

  @dir Path.expand("../fixtures/liquipedia", __DIR__)

  defp ingest_fixtures do
    for {file, title} <- [
          {"bacchus_osl_2008_rev541187.wiki", "2008 Bacchus OSL"},
          {"asl_s6_rev538330.wiki", "AfreecaTV/StarCraft League Remastered/6"},
          {"asl_s17_rev542482.wiki", "AfreecaTV/StarCraft League Remastered/17"}
        ] do
      {:ok, _} = MatchIngest.ingest_wikitext(title, 1, File.read!(Path.join(@dir, file)))
    end
  end

  defp snapshot do
    history =
      Repo.all(
        from h in RatingHistory,
          order_by: [h.sequence, h.player_id],
          select: {h.sequence, h.player_id, h.game_id, h.rating_before, h.rating_after}
      )

    players =
      Repo.all(
        from p in Player,
          order_by: p.id,
          select: {p.id, p.rating, p.rated_games, p.last_played_at}
      )

    {history, players}
  end

  test "k_factor/1 follows the documented schedule" do
    assert Ratings.k_factor(0) == 40
    assert Ratings.k_factor(29) == 40
    assert Ratings.k_factor(30) == 24
    assert Ratings.k_factor(99) == 24
    assert Ratings.k_factor(100) == 16
  end

  test "recompute/0 twice yields identical history and ratings" do
    ingest_fixtures()

    assert {:ok, %{games: games}} = Ratings.recompute()
    assert games > 200
    first = snapshot()

    assert {:ok, _} = Ratings.recompute()
    assert snapshot() == first
  end

  test "recompute/0 is zero-sum per game while K factors are equal" do
    ingest_fixtures()
    {:ok, _} = Ratings.recompute()

    [first_a, first_b] =
      Repo.all(from h in RatingHistory, where: h.sequence == 1, order_by: h.player_id)

    assert first_a.rating_before == 1500.0
    assert_in_delta first_a.rating_after - 1500.0, -(first_b.rating_after - 1500.0), 1.0e-9
    assert abs(first_a.rating_after - 1500.0) == 20.0
  end

  test "recompute/0 excludes walkovers" do
    ingest_fixtures()
    {:ok, _} = Ratings.recompute()

    # Yerim2 lost both of his ASL6 series by walkover, so he has no rated games.
    yerim = Repo.get_by!(Player, name: "Yerim2")
    assert yerim.rated_games == 0
    assert yerim.rating == nil
  end

  test "recompute/0 orders games chronologically across pages" do
    ingest_fixtures()
    {:ok, _} = Ratings.recompute()

    dates =
      Repo.all(from h in RatingHistory, order_by: h.sequence, select: h.played_at)

    assert dates == Enum.sort(dates, DateTime)
    assert hd(dates).year == 2008
  end
end

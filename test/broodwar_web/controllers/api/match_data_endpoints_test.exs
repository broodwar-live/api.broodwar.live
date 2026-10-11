defmodule BroodwarWeb.Api.MatchDataEndpointsTest do
  @moduledoc """
  Endpoint tests for ingested match data: ratings, player matches,
  head-to-head, map stats, balance and rankings. Data comes from the saved
  Liquipedia fixtures (ASL Season 17 and 2008 Bacchus OSL).
  """
  use BroodwarWeb.ConnCase

  alias Broodwar.Ingestion.MatchIngest
  alias Broodwar.Maps.Map, as: GameMap
  alias Broodwar.Players.Identity
  alias Broodwar.Players.Player
  alias Broodwar.Ratings
  alias Broodwar.Repo

  @dir Path.expand("../../../fixtures/liquipedia", __DIR__)

  setup %{conn: conn} do
    Broodwar.Cache.invalidate_all()

    # ASL17 pages carry no inline races (Liquipedia takes them from player
    # pages); create these players first, as the profile sync would.
    for {name, race} <- [{"hero", "Z"}, {"Soulkey", "Z"}, {"Sharp", "T"}, {"SnOw", "P"}] do
      {:ok, _} = Identity.resolve_liquipedia(%{page: name, name: name}, race: race)
    end

    for {file, title} <- [
          {"asl_s17_rev542482.wiki", "AfreecaTV/StarCraft League Remastered/17"},
          {"bacchus_osl_2008_rev541187.wiki", "2008 Bacchus OSL"}
        ] do
      {:ok, _} = MatchIngest.ingest_wikitext(title, 42, File.read!(Path.join(@dir, file)))
    end

    {:ok, _} = Ratings.recompute()
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp player(name), do: Repo.get_by!(Player, name: name)

  test "GET /api/players/:id/ratings returns the history with sample size", %{conn: conn} do
    flash = player("Flash")
    body = conn |> get(~p"/api/players/#{flash.id}/ratings?per_page=200") |> json_response(200)

    assert %{"rating" => rating, "n" => n, "history" => history} = body["data"]
    assert n == length(history) and n > 0
    assert body["pagination"]["total"] == n
    assert List.last(history)["rating_after"] |> round() == rating
    assert hd(history)["rating_before"] == 1500.0
    assert body["meta"]["source"]["name"] == "Liquipedia"
  end

  test "GET /api/players/:id/ratings for a missing player returns 404", %{conn: conn} do
    assert conn |> get(~p"/api/players/999999/ratings") |> json_response(404)
  end

  test "GET /api/players/:id/matches returns series with games and source", %{conn: conn} do
    hero = player("hero")
    body = conn |> get(~p"/api/players/#{hero.id}/matches") |> json_response(200)

    assert [final | _] = body["data"]
    assert final["round"] == "Finals (Bo7)"
    assert final["source"]["type"] == "liquipedia"
    assert final["source"]["revision_id"] == 42

    assert final["source"]["url"] =~
             "liquipedia.net/starcraft/AfreecaTV/StarCraft_League_Remastered/17"

    assert length(final["games"]) == final["score_a"] + final["score_b"]
    assert body["pagination"]["total"] >= 5
  end

  test "GET /api/head_to_head returns series, games, by-map and by-matchup", %{conn: conn} do
    hero = player("hero")
    soulkey = player("Soulkey")

    body =
      conn
      |> get(~p"/api/head_to_head?player_a=#{hero.id}&player_b=#{soulkey.id}")
      |> json_response(200)

    data = body["data"]
    assert data["series"]["n"] >= 1
    assert data["games"]["n"] == data["games"]["a_wins"] + data["games"]["b_wins"]
    assert Enum.sum(Enum.map(data["by_map"], & &1["n"])) == data["games"]["n"]
    assert [%{"matchup" => "ZvZ", "n" => n}] = data["by_matchup"]
    assert n == data["games"]["n"]
    assert body["meta"]["source"]["license"] == "CC-BY-SA 3.0"
  end

  test "GET /api/head_to_head without two ids returns 400", %{conn: conn} do
    assert conn |> get(~p"/api/head_to_head?player_a=1") |> json_response(400)
  end

  test "GET /api/maps/:id/stats returns matchup winrates with n", %{conn: conn} do
    katrina = Repo.get_by!(GameMap, name: "Katrina")
    body = conn |> get(~p"/api/maps/#{katrina.id}/stats") |> json_response(200)

    assert body["data"]["map"]["name"] == "Katrina"
    assert body["data"]["n"] > 0
    assert Enum.all?(body["data"]["matchups"], &is_integer(&1["n"]))
    assert body["meta"]["source"]["name"] == "Liquipedia"
  end

  test "GET /api/balance aggregates games by year with sample sizes", %{conn: conn} do
    body = conn |> get(~p"/api/balance") |> json_response(200)

    assert body["data"]["n"] > 0
    years = Enum.map(body["data"]["by_year"], & &1["year"])
    assert 2008 in years

    for %{"matchup" => mu, "n" => n, "wins" => w, "losses" => l} <- body["data"]["overall"],
        mu in ~w(TvZ PvT ZvP) do
      assert w + l == n
    end
  end

  test "GET /api/rankings applies the games and activity filters", %{conn: conn} do
    # All fixture games are from 2008-2024: nobody is active in the default
    # 365-day window.
    assert %{"data" => []} = conn |> get(~p"/api/rankings") |> json_response(200)

    body = conn |> get(~p"/api/rankings?min_games=5&active_days=20000") |> json_response(200)
    assert [%{"rank" => 1, "n" => n} | _] = body["data"]
    assert n >= 5
    assert body["meta"]["criteria"] == %{"min_games" => 5, "active_days" => 20_000}

    ratings = Enum.map(body["data"], & &1["rating"])
    assert ratings == Enum.sort(ratings, :desc)
  end
end

defmodule BroodwarWeb.Api.MatchControllerTest do
  use BroodwarWeb.ConnCase

  alias Broodwar.Repo
  alias Broodwar.Players.Player
  alias Broodwar.Matches.Match

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp create_players do
    {:ok, p1} = Repo.insert(Player.changeset(%Player{}, %{name: "Flash", race: "T"}))
    {:ok, p2} = Repo.insert(Player.changeset(%Player{}, %{name: "Jaedong", race: "Z"}))
    {p1, p2}
  end

  defp create_match(p1, p2, attrs \\ %{}) do
    default = %{
      player_a_id: p1.id,
      player_b_id: p2.id,
      race_a: "T",
      race_b: "Z",
      score_a: 3,
      score_b: 1,
      played_at: ~U[2025-01-15 12:00:00Z]
    }

    {:ok, match} = Repo.insert(Match.changeset(%Match{}, Map.merge(default, attrs)))
    match
  end

  describe "GET /api/matches" do
    test "returns empty list when no matches", %{conn: conn} do
      conn = get(conn, ~p"/api/matches")
      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns matches with player data", %{conn: conn} do
      {p1, p2} = create_players()
      create_match(p1, p2)

      conn = get(conn, ~p"/api/matches")
      assert %{"data" => [match]} = json_response(conn, 200)
      assert match["matchup"] == "TvZ"
      assert match["player_a"]["name"] == "Flash"
      assert match["player_b"]["name"] == "Jaedong"
    end

    test "filters by matchup", %{conn: conn} do
      {p1, p2} = create_players()
      create_match(p1, p2, %{race_a: "T", race_b: "Z"})

      conn = get(conn, ~p"/api/matches?matchup=PvP")
      assert %{"data" => []} = json_response(conn, 200)

      conn = get(conn, ~p"/api/matches?matchup=TvZ")
      assert %{"data" => [_]} = json_response(conn, 200)
    end
  end

  describe "GET /api/matches/:id" do
    test "returns match by id", %{conn: conn} do
      {p1, p2} = create_players()
      match = create_match(p1, p2)

      conn = get(conn, ~p"/api/matches/#{match.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == match.id
      assert data["score_a"] == 3
    end

    test "returns 404 for missing match", %{conn: conn} do
      conn = get(conn, ~p"/api/matches/999999")
      assert json_response(conn, 404)["error"]["code"] == "NOT_FOUND"
    end
  end
end

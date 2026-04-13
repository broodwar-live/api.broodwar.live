defmodule BroodwarWeb.Api.TournamentControllerTest do
  use BroodwarWeb.ConnCase

  alias Broodwar.Repo
  alias Broodwar.Tournaments.Tournament

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp create_tournament(attrs \\ %{}) do
    default = %{
      name: "Afreeca StarCraft League Season 19",
      short_name: "ASL",
      type: "individual",
      year: 2025,
      season: 19,
      liquipedia_data: %{"first_place" => "Flash"}
    }

    {:ok, tournament} = Repo.insert(Tournament.changeset(%Tournament{}, Map.merge(default, attrs)))
    tournament
  end

  describe "GET /api/tournaments" do
    test "returns tournament series", %{conn: conn} do
      create_tournament()

      conn = get(conn, ~p"/api/tournaments")
      assert %{"data" => series} = json_response(conn, 200)
      assert is_list(series)
    end
  end

  describe "GET /api/tournaments/:slug" do
    test "returns seasons for a series", %{conn: conn} do
      create_tournament(%{season: 18})
      create_tournament(%{name: "ASL S19", season: 19})

      conn = get(conn, ~p"/api/tournaments/asl")
      assert %{"data" => seasons} = json_response(conn, 200)
      assert length(seasons) == 2
    end
  end

  describe "GET /api/tournaments/:slug/:season" do
    test "returns specific season", %{conn: conn} do
      create_tournament()

      conn = get(conn, ~p"/api/tournaments/asl/19")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["short_name"] == "ASL"
      assert data["season"] == 19
    end

    test "returns 404 for missing season", %{conn: conn} do
      conn = get(conn, ~p"/api/tournaments/asl/99")
      assert json_response(conn, 404)["error"]["code"] == "NOT_FOUND"
    end
  end
end

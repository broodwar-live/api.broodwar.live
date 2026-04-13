defmodule BroodwarWeb.Api.PlayerControllerTest do
  use BroodwarWeb.ConnCase

  alias Broodwar.Repo
  alias Broodwar.Players.Player

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp create_player(attrs \\ %{}) do
    default = %{name: "Flash", race: "T", country: "KR", rating: 2500, status: "active"}
    {:ok, player} = Repo.insert(Player.changeset(%Player{}, Map.merge(default, attrs)))
    player
  end

  describe "GET /api/players" do
    test "returns empty list when no players", %{conn: conn} do
      conn = get(conn, ~p"/api/players")
      assert %{"data" => [], "pagination" => _} = json_response(conn, 200)
    end

    test "returns players list", %{conn: conn} do
      create_player()
      conn = get(conn, ~p"/api/players")
      assert %{"data" => [player]} = json_response(conn, 200)
      assert player["name"] == "Flash"
      assert player["race"] == "terran"
    end

    test "filters by race", %{conn: conn} do
      create_player(%{name: "Flash", race: "T"})
      create_player(%{name: "Bisu", race: "P"})

      conn = get(conn, ~p"/api/players?race=T")
      assert %{"data" => players} = json_response(conn, 200)
      assert length(players) == 1
      assert hd(players)["name"] == "Flash"
    end

    test "filters by status", %{conn: conn} do
      create_player(%{name: "Flash", status: "active"})
      create_player(%{name: "NaDa", status: "inactive"})

      conn = get(conn, ~p"/api/players?status=active")
      assert %{"data" => players} = json_response(conn, 200)
      assert length(players) == 1
    end

    test "searches by name", %{conn: conn} do
      create_player(%{name: "Flash"})
      create_player(%{name: "Bisu"})

      conn = get(conn, ~p"/api/players?search=Fla")
      assert %{"data" => [player]} = json_response(conn, 200)
      assert player["name"] == "Flash"
    end

    test "paginates results", %{conn: conn} do
      for i <- 1..3, do: create_player(%{name: "Player#{i}", rating: i})

      conn = get(conn, ~p"/api/players?page=1&per_page=2")
      assert %{"data" => players, "pagination" => pagination} = json_response(conn, 200)
      assert length(players) == 2
      assert pagination["page"] == 1
      assert pagination["per_page"] == 2
    end
  end

  describe "GET /api/players/:id" do
    test "returns player by id", %{conn: conn} do
      player = create_player()
      conn = get(conn, ~p"/api/players/#{player.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == player.id
      assert data["name"] == "Flash"
    end

    test "returns 404 for missing player", %{conn: conn} do
      conn = get(conn, ~p"/api/players/999999")
      assert json_response(conn, 404)["error"]["code"] == "NOT_FOUND"
    end
  end
end

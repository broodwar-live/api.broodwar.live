defmodule BroodwarWeb.Api.MapControllerTest do
  use BroodwarWeb.ConnCase

  alias Broodwar.Repo
  alias Broodwar.Maps.Map, as: GameMap

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp create_map(attrs \\ %{}) do
    default = %{
      name: "Fighting Spirit",
      width: 128,
      height: 128,
      tileset: "jungle",
      spawn_positions: [%{"x" => 10, "y" => 20}, %{"x" => 100, "y" => 110}]
    }

    {:ok, map} = Repo.insert(GameMap.changeset(%GameMap{}, Map.merge(default, attrs)))
    map
  end

  describe "GET /api/maps" do
    test "returns maps list", %{conn: conn} do
      create_map()

      conn = get(conn, ~p"/api/maps")
      assert %{"data" => [map]} = json_response(conn, 200)
      assert map["name"] == "Fighting Spirit"
      assert map["tileset"] == "jungle"
    end
  end

  describe "GET /api/maps/:id" do
    test "returns map by id", %{conn: conn} do
      map = create_map()

      conn = get(conn, ~p"/api/maps/#{map.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == map.id
      assert data["spawn_positions"] |> length() == 2
    end

    test "returns 404 for missing map", %{conn: conn} do
      conn = get(conn, ~p"/api/maps/999999")
      assert json_response(conn, 404)["error"]["code"] == "NOT_FOUND"
    end
  end
end

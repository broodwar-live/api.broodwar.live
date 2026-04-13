defmodule BroodwarWeb.Api.BuildControllerTest do
  use BroodwarWeb.ConnCase

  alias Broodwar.Repo
  alias Broodwar.Builds.Build

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp create_build(attrs \\ %{}) do
    default = %{
      name: "2 Hatch Muta",
      race: "Z",
      matchup: "ZvT",
      description: "Fast mutalisk opening",
      tags: ["aggressive", "air"],
      games: 150,
      winrate: 54
    }

    {:ok, build} = Repo.insert(Build.changeset(%Build{}, Map.merge(default, attrs)))
    build
  end

  describe "GET /api/builds" do
    test "returns builds list", %{conn: conn} do
      create_build()

      conn = get(conn, ~p"/api/builds")
      assert %{"data" => [build]} = json_response(conn, 200)
      assert build["name"] == "2 Hatch Muta"
      assert build["race"] == "zerg"
      assert build["matchup"] == "ZvT"
    end

    test "filters by race", %{conn: conn} do
      create_build(%{name: "2 Hatch Muta", race: "Z", matchup: "ZvT"})
      create_build(%{name: "1 Gate Core", race: "P", matchup: "PvT"})

      conn = get(conn, ~p"/api/builds?race=Z")
      assert %{"data" => builds} = json_response(conn, 200)
      assert length(builds) == 1
    end

    test "filters by matchup", %{conn: conn} do
      create_build(%{name: "2 Hatch Muta", race: "Z", matchup: "ZvT"})
      create_build(%{name: "3 Hatch Hydra", race: "Z", matchup: "ZvP"})

      conn = get(conn, ~p"/api/builds?matchup=ZvT")
      assert %{"data" => [build]} = json_response(conn, 200)
      assert build["name"] == "2 Hatch Muta"
    end
  end

  describe "GET /api/builds/:id" do
    test "returns build by id", %{conn: conn} do
      build = create_build()

      conn = get(conn, ~p"/api/builds/#{build.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == build.id
      assert data["tags"] == ["aggressive", "air"]
    end

    test "returns 404 for missing build", %{conn: conn} do
      conn = get(conn, ~p"/api/builds/999999")
      assert json_response(conn, 404)["error"]["code"] == "NOT_FOUND"
    end
  end
end

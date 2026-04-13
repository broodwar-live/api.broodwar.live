defmodule BroodwarWeb.Api.ReplayControllerTest do
  use BroodwarWeb.ConnCase

  alias Broodwar.Repo
  alias Broodwar.Replays.Replay

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp create_replay(attrs \\ %{}) do
    default = %{
      file_hash: "abc123def456",
      race_a: "T",
      race_b: "Z",
      duration: 900,
      parsed_data: %{"header" => %{"map_name" => "Fighting Spirit"}}
    }

    {:ok, replay} = Repo.insert(Replay.changeset(%Replay{}, Map.merge(default, attrs)))
    replay
  end

  describe "GET /api/replays" do
    test "returns empty list when no replays", %{conn: conn} do
      conn = get(conn, ~p"/api/replays")
      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns replays without parsed_data", %{conn: conn} do
      create_replay()

      conn = get(conn, ~p"/api/replays")
      assert %{"data" => [replay]} = json_response(conn, 200)
      assert replay["file_hash"] == "abc123def456"
      refute Map.has_key?(replay, "parsed_data")
    end
  end

  describe "GET /api/replays/:id" do
    test "returns replay with parsed_data", %{conn: conn} do
      replay = create_replay()

      conn = get(conn, ~p"/api/replays/#{replay.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == replay.id
      assert data["parsed_data"] != nil
    end

    test "returns 404 for missing replay", %{conn: conn} do
      conn = get(conn, ~p"/api/replays/999999")
      assert json_response(conn, 404)["error"]["code"] == "NOT_FOUND"
    end
  end
end

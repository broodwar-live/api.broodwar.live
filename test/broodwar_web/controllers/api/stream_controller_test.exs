defmodule BroodwarWeb.Api.StreamControllerTest do
  use BroodwarWeb.ConnCase

  alias Broodwar.Repo
  alias Broodwar.Streams.Stream

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp create_stream(attrs \\ %{}) do
    default = %{
      channel_id: "flash_bw",
      platform: "afreeca",
      title: "Flash streaming BW",
      is_live: true,
      viewer_count: 3500
    }

    {:ok, stream} = Repo.insert(Stream.changeset(%Stream{}, Map.merge(default, attrs)))
    stream
  end

  describe "GET /api/streams" do
    test "returns streams list", %{conn: conn} do
      create_stream()

      conn = get(conn, ~p"/api/streams")
      assert %{"data" => [stream]} = json_response(conn, 200)
      assert stream["platform"] == "afreeca"
      assert stream["is_live"] == true
    end

    test "filters by platform", %{conn: conn} do
      create_stream(%{channel_id: "flash_af", platform: "afreeca"})
      create_stream(%{channel_id: "flash_tw", platform: "twitch"})

      conn = get(conn, ~p"/api/streams?platform=twitch")
      assert %{"data" => streams} = json_response(conn, 200)
      assert length(streams) == 1
      assert hd(streams)["platform"] == "twitch"
    end

    test "filters by live status", %{conn: conn} do
      create_stream(%{channel_id: "live_ch", is_live: true})
      create_stream(%{channel_id: "offline_ch", is_live: false})

      conn = get(conn, ~p"/api/streams?live=true")
      assert %{"data" => streams} = json_response(conn, 200)
      assert length(streams) == 1
      assert hd(streams)["is_live"] == true
    end
  end

  describe "GET /api/streams/:id" do
    test "returns stream by id", %{conn: conn} do
      stream = create_stream()

      conn = get(conn, ~p"/api/streams/#{stream.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == stream.id
    end

    test "returns 404 for missing stream", %{conn: conn} do
      conn = get(conn, ~p"/api/streams/999999")
      assert json_response(conn, 404)["error"]["code"] == "NOT_FOUND"
    end
  end
end

defmodule BroodwarWeb.Api.ReplayControllerTest do
  use BroodwarWeb.ConnCase

  alias Broodwar.Players.Player
  alias Broodwar.Replays.Replay
  alias Broodwar.Repo

  # Real 1v1 Remastered replay with a decided result, copied from
  # bw-engine/tests/fixtures (Moo.Sapa vs adultrabbit; adultrabbit wins).
  @fixture Path.expand("../../../fixtures/larva_vs_mini.rep", __DIR__)

  setup %{conn: conn} do
    # Give every test its own client IP so rate-limit buckets don't leak
    # between tests.
    n = System.unique_integer([:positive])
    ip = {10, rem(div(n, 65_536), 256), rem(div(n, 256), 256), rem(n, 256)}

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> Map.put(:remote_ip, ip)

    {:ok, conn: conn}
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

  defp upload(path \\ @fixture) do
    %Plug.Upload{
      path: path,
      filename: Path.basename(path),
      content_type: "application/octet-stream"
    }
  end

  defp tmp_file(contents) do
    path = Path.join(System.tmp_dir!(), "bw-test-#{System.unique_integer([:positive])}.rep")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "GET /api/replays" do
    test "index with no replays returns empty list", %{conn: conn} do
      conn = get(conn, ~p"/api/replays")
      assert %{"data" => []} = json_response(conn, 200)
    end

    test "index omits parsed_data", %{conn: conn} do
      create_replay()

      conn = get(conn, ~p"/api/replays")
      assert %{"data" => [replay]} = json_response(conn, 200)
      assert replay["file_hash"] == "abc123def456"
      refute Map.has_key?(replay, "parsed_data")
    end

    test "index paginates in the database", %{conn: conn} do
      for i <- 1..3, do: create_replay(%{file_hash: "hash#{i}"})

      body = conn |> get(~p"/api/replays?per_page=2&page=2") |> json_response(200)
      assert length(body["data"]) == 1
      assert body["pagination"] == %{"page" => 2, "per_page" => 2}
    end
  end

  describe "GET /api/replays/:id" do
    test "show returns replay with parsed_data", %{conn: conn} do
      replay = create_replay()

      conn = get(conn, ~p"/api/replays/#{replay.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == replay.id
      assert data["parsed_data"] != nil
    end

    test "show with missing id returns 404", %{conn: conn} do
      conn = get(conn, ~p"/api/replays/999999")
      assert json_response(conn, 404)["error"]["code"] == "NOT_FOUND"
    end
  end

  describe "POST /api/replays" do
    test "create with real .rep stores parsed replay without touching players", %{conn: conn} do
      conn = post(conn, ~p"/api/replays", %{"file" => upload()})

      assert %{"data" => data} = json_response(conn, 201)
      assert data["parsed_data"]["header"]["players"] != []
      assert data["player_a"] == nil
      assert data["player_b"] == nil

      replay = Repo.get!(Replay, data["id"])
      assert replay.source == "upload"
      assert replay.rated_at == nil
      assert replay.player_a_name == "Moo.Sapa"
      assert replay.winner_name == "adultrabbit"
      assert replay.matchup != nil
      assert Repo.aggregate(Player, :count) == 0
    end

    test "create with duplicate file returns existing replay with 200", %{conn: conn} do
      first = conn |> post(~p"/api/replays", %{"file" => upload()}) |> json_response(201)
      second = conn |> post(~p"/api/replays", %{"file" => upload()}) |> json_response(200)

      assert first["data"]["id"] == second["data"]["id"]
      assert Repo.aggregate(Replay, :count) == 1
    end

    test "create with non-replay bytes returns 422 before parsing", %{conn: conn} do
      path = tmp_file("definitely not a replay file, just some text bytes")
      conn = post(conn, ~p"/api/replays", %{"file" => upload(path)})

      assert json_response(conn, 422)["error"]["code"] == "INVALID_REPLAY"
    end

    test "create with valid magic but corrupt body returns 422", %{conn: conn} do
      path = tmp_file(<<0::32, 1::little-32, 4::little-32, "seRS", 0::size(800)>>)
      conn = post(conn, ~p"/api/replays", %{"file" => upload(path)})

      assert json_response(conn, 422)["error"]["code"] == "INVALID_REPLAY"
    end

    test "create with file over 5 MiB returns 413", %{conn: conn} do
      header = <<0::32, 1::little-32, 4::little-32, "seRS">>
      path = tmp_file([header, :binary.copy(<<0>>, Broodwar.Replays.max_size())])
      conn = post(conn, ~p"/api/replays", %{"file" => upload(path)})

      assert json_response(conn, 413)["error"]["code"] == "TOO_LARGE"
    end

    test "create without file returns 400", %{conn: conn} do
      conn = post(conn, ~p"/api/replays", %{})
      assert json_response(conn, 400)["error"]["code"] == "BAD_REQUEST"
    end

    test "create beyond the per-IP upload limit returns 429", %{conn: conn} do
      # config/test.exs allows 3 uploads per hour.
      path = tmp_file("not a replay")

      for _ <- 1..3 do
        assert conn |> post(~p"/api/replays", %{"file" => upload(path)}) |> json_response(422)
      end

      conn = post(conn, ~p"/api/replays", %{"file" => upload(path)})
      assert json_response(conn, 429)["error"]["code"] == "RATE_LIMITED"
      assert [_] = get_resp_header(conn, "retry-after")
    end
  end

  describe "admin replay routes" do
    test "admin_create without token returns 401", %{conn: conn} do
      conn = post(conn, ~p"/api/admin/replays", %{"file" => upload()})
      assert json_response(conn, 401)["error"]["code"] == "UNAUTHORIZED"
      assert Repo.aggregate(Replay, :count) == 0
    end

    test "admin_create with wrong token returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer nope")
        |> post(~p"/api/admin/replays", %{"file" => upload()})

      assert json_response(conn, 401)
    end

    test "admin_create with valid token links players and rates", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer test-admin-key")
        |> post(~p"/api/admin/replays", %{"file" => upload()})

      assert %{"data" => data} = json_response(conn, 201)
      replay = Repo.get!(Replay, data["id"])
      assert replay.source == "admin"
      assert %DateTime{} = replay.rated_at

      winner = Repo.get_by!(Player, name: "adultrabbit")
      loser = Repo.get_by!(Player, name: "Moo.Sapa")
      assert winner.rating > 1500
      assert loser.rating < 1500
      assert data["player_a"]["name"] == "Moo.Sapa"
    end

    test "rate on anonymous upload is idempotent", %{conn: conn} do
      %{"data" => %{"id" => id}} =
        conn |> post(~p"/api/replays", %{"file" => upload()}) |> json_response(201)

      authed = put_req_header(conn, "authorization", "Bearer test-admin-key")
      assert authed |> post(~p"/api/admin/replays/#{id}/rate") |> json_response(200)
      ratings = Repo.all(Player) |> Enum.map(&{&1.name, &1.rating}) |> Enum.sort()

      assert authed |> post(~p"/api/admin/replays/#{id}/rate") |> json_response(200)
      assert ratings == Repo.all(Player) |> Enum.map(&{&1.name, &1.rating}) |> Enum.sort()
    end
  end
end

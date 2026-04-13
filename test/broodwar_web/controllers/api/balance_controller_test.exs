defmodule BroodwarWeb.Api.BalanceControllerTest do
  use BroodwarWeb.ConnCase

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "GET /api/balance" do
    test "returns matchup balance stats", %{conn: conn} do
      conn = get(conn, ~p"/api/balance")
      assert %{"data" => stats} = json_response(conn, 200)
      assert is_list(stats)

      matchups = Enum.map(stats, & &1["matchup"])
      assert "TvZ" in matchups
      assert "PvT" in matchups
      assert "ZvP" in matchups
    end
  end
end

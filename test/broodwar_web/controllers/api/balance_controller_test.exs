defmodule BroodwarWeb.Api.BalanceControllerTest do
  use BroodwarWeb.ConnCase

  setup %{conn: conn} do
    Broodwar.Cache.invalidate_all()
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "GET /api/balance" do
    test "with no games returns all matchups with n = 0 and attribution", %{conn: conn} do
      body = conn |> get(~p"/api/balance") |> json_response(200)

      assert %{"n" => 0, "overall" => overall, "by_year" => []} = body["data"]
      assert Enum.map(overall, & &1["matchup"]) == ~w(TvZ PvT ZvP TvT PvP ZvZ)
      assert Enum.all?(overall, &(&1["n"] == 0))
      assert body["meta"]["source"]["license"] == "CC-BY-SA 3.0"
    end
  end
end

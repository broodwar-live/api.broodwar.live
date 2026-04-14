defmodule BroodwarWeb.Api.BalanceController do
  use BroodwarWeb, :controller

  alias Broodwar.Matches

  def index(conn, _params) do
    stats = Broodwar.Cache.fetch("balance_stats", 300, fn ->
      Matches.balance_stats()
    end)
    json(conn, %{data: stats})
  end
end

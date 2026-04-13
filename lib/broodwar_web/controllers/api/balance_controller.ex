defmodule BroodwarWeb.Api.BalanceController do
  use BroodwarWeb, :controller

  alias Broodwar.Matches

  def index(conn, _params) do
    stats = Matches.balance_stats()
    json(conn, %{data: stats})
  end
end

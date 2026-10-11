defmodule BroodwarWeb.Api.BalanceController do
  use BroodwarWeb, :controller

  alias Broodwar.Stats
  alias BroodwarWeb.Api.Params

  @doc """
  GET /api/balance — matchup winrates from games, overall and per year.
  `?map_id=` restricts to one map. Every row carries its sample size `n`.
  """
  def index(conn, params) do
    map_id = Params.int(params["map_id"])

    stats =
      Broodwar.Cache.fetch("balance_stats:#{map_id}", 300, fn ->
        Stats.balance(map_id: map_id)
      end)

    json(conn, %{data: stats, meta: %{source: Stats.attribution()}})
  end
end

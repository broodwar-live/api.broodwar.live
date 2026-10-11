defmodule BroodwarWeb.Api.HeadToHeadController do
  use BroodwarWeb, :controller

  alias Broodwar.Players
  alias Broodwar.Stats
  alias BroodwarWeb.Api.JSON
  alias BroodwarWeb.Api.Params

  action_fallback BroodwarWeb.Api.FallbackController

  @doc """
  GET /api/head_to_head?player_a=ID&player_b=ID — series and game record
  between two players, games by map and by matchup (from player_a's view).
  """
  def show(conn, params) do
    with {:ok, a_id, b_id} <- ids(params),
         {:ok, a} <- fetch(a_id),
         {:ok, b} <- fetch(b_id) do
      h2h = Stats.head_to_head(a.id, b.id)

      json(conn, %{
        data: %{
          player_a: JSON.player_summary(a),
          player_b: JSON.player_summary(b),
          series: h2h.series,
          games: h2h.games,
          by_map: h2h.by_map,
          by_matchup: h2h.by_matchup,
          matches: Enum.map(h2h.matches, &JSON.match/1)
        },
        meta: %{source: Stats.attribution()}
      })
    end
  end

  defp ids(params) do
    case {Params.int(params["player_a"]), Params.int(params["player_b"])} do
      {a, b} when is_integer(a) and is_integer(b) and a != b -> {:ok, a, b}
      _ -> {:error, "player_a and player_b must be two different player ids"}
    end
  end

  defp fetch(id) do
    {:ok, Players.get_player!(id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end

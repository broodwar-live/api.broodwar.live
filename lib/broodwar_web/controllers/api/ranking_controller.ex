defmodule BroodwarWeb.Api.RankingController do
  use BroodwarWeb, :controller

  alias Broodwar.Ratings
  alias Broodwar.Stats
  alias BroodwarWeb.Api.JSON
  alias BroodwarWeb.Api.Params

  @doc """
  GET /api/rankings — current Elo of players with at least `min_games`
  rated games who played within `active_days` (defaults from
  `config :broodwar, :rankings`, overridable per request).
  """
  def index(conn, params) do
    pagination = Params.pagination(params)

    {min_games, active_days} =
      Ratings.ranking_criteria(
        min_games: Params.int(params["min_games"]),
        active_days: Params.int(params["active_days"])
      )

    players = Ratings.rankings([min_games: min_games, active_days: active_days] ++ pagination)
    meta = Broodwar.Pagination.pagination_meta(pagination)
    offset = (meta.page - 1) * meta.per_page

    data =
      players
      |> Enum.with_index(offset + 1)
      |> Enum.map(fn {p, rank} ->
        %{
          rank: rank,
          player: JSON.player_summary(p),
          rating: p.rating,
          n: p.rated_games,
          last_played_at: p.last_played_at
        }
      end)

    json(conn, %{
      data: data,
      pagination: meta,
      meta: %{
        criteria: %{min_games: min_games, active_days: active_days},
        rating_system: "Elo per game; K=40 (<30 games), 24 (<100), 16; start 1500",
        source: Stats.attribution()
      }
    })
  end
end

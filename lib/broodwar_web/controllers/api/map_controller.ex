defmodule BroodwarWeb.Api.MapController do
  use BroodwarWeb, :controller

  alias Broodwar.Maps.Map, as: GameMap
  alias Broodwar.Repo
  alias BroodwarWeb.Api.JSON

  import Ecto.Query

  action_fallback BroodwarWeb.Api.FallbackController

  def index(conn, _params) do
    maps =
      GameMap
      |> order_by(:name)
      |> Repo.all()

    json(conn, %{data: Enum.map(maps, &JSON.game_map/1)})
  end

  @doc """
  GET /api/maps/:id/stats — matchup winrates on this map from games with
  known races and maps (sample size `n` per matchup).
  """
  def stats(conn, %{"map_id" => id}) do
    map = Repo.get!(GameMap, id)
    stats = Broodwar.Stats.map_stats(map.id)

    json(conn, %{
      data: %{
        map: JSON.game_map_summary(map),
        n: Enum.sum(Enum.map(stats, & &1.n)),
        matchups: stats
      },
      meta: %{source: Broodwar.Stats.attribution()}
    })
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def show(conn, %{"id" => id}) do
    map = Repo.get!(GameMap, id)
    json(conn, %{data: JSON.game_map(map)})
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end
end

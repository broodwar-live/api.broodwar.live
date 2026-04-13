defmodule BroodwarWeb.Api.MapController do
  use BroodwarWeb, :controller

  alias Broodwar.Repo
  alias Broodwar.Maps.Map, as: GameMap
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

  def show(conn, %{"id" => id}) do
    map = Repo.get!(GameMap, id)
    json(conn, %{data: JSON.game_map(map)})
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end
end

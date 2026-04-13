defmodule BroodwarWeb.Api.TournamentController do
  use BroodwarWeb, :controller

  alias Broodwar.Tournaments
  alias BroodwarWeb.Api.JSON

  action_fallback BroodwarWeb.Api.FallbackController

  def index(conn, _params) do
    series = Tournaments.list_series()
    json(conn, %{data: series})
  end

  def show(conn, %{"slug" => slug}) do
    seasons = Tournaments.list_by_series(String.upcase(slug))
    json(conn, %{data: Enum.map(seasons, &JSON.tournament/1)})
  end

  def season(conn, %{"slug" => slug, "season" => season}) do
    case Tournaments.get_season(String.upcase(slug), season) do
      nil -> {:error, :not_found}
      tournament -> json(conn, %{data: JSON.tournament_detail(tournament)})
    end
  end
end

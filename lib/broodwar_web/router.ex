defmodule BroodwarWeb.Router do
  use BroodwarWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug BroodwarWeb.Plugs.CORS
  end

  scope "/api", BroodwarWeb.Api do
    pipe_through :api

    resources "/players", PlayerController, only: [:index, :show] do
      get "/matches", PlayerController, :matches
      get "/stats", PlayerController, :stats
    end

    resources "/matches", MatchController, only: [:index, :show]
    resources "/replays", ReplayController, only: [:index, :show, :create]
    resources "/builds", BuildController, only: [:index, :show]
    resources "/maps", MapController, only: [:index, :show]
    resources "/streams", StreamController, only: [:index, :show]

    get "/tournaments", TournamentController, :index
    get "/tournaments/:slug", TournamentController, :show
    get "/tournaments/:slug/:season", TournamentController, :season

    get "/balance", BalanceController, :index
  end
end

defmodule BroodwarWeb.Router do
  use BroodwarWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug BroodwarWeb.Plugs.CORS
    plug BroodwarWeb.Plugs.ClientIP
    plug BroodwarWeb.Plugs.RateLimit, bucket: :api
  end

  pipeline :uploads do
    plug BroodwarWeb.Plugs.RateLimit, bucket: :uploads
  end

  pipeline :admin do
    plug BroodwarWeb.Plugs.AdminAuth
  end

  # Health check sits outside the rate-limited pipeline.
  scope "/api", BroodwarWeb.Api do
    get "/health", HealthController, :show
  end

  scope "/api", BroodwarWeb.Api do
    pipe_through [:api, :uploads]

    post "/replays", ReplayController, :create
  end

  scope "/api/admin", BroodwarWeb.Api do
    pipe_through [:api, :admin]

    post "/replays", ReplayController, :admin_create
    post "/replays/:id/rate", ReplayController, :rate
  end

  scope "/api", BroodwarWeb.Api do
    pipe_through :api

    resources "/players", PlayerController, only: [:index, :show] do
      get "/matches", PlayerController, :matches
      get "/stats", PlayerController, :stats
    end

    resources "/matches", MatchController, only: [:index, :show]
    resources "/replays", ReplayController, only: [:index, :show]
    resources "/builds", BuildController, only: [:index, :show]
    get "/openings", BuildController, :openings
    resources "/maps", MapController, only: [:index, :show]
    resources "/streams", StreamController, only: [:index, :show]

    get "/tournaments", TournamentController, :index
    get "/tournaments/:slug", TournamentController, :show
    get "/tournaments/:slug/:season", TournamentController, :season

    get "/balance", BalanceController, :index
  end
end

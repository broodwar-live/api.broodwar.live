import Config

config :broodwar,
  ecto_repos: [Broodwar.Repo],
  generators: [timestamp_type: :utc_datetime]

config :broodwar, BroodwarWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: BroodwarWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Broodwar.PubSub

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :broodwar, Oban,
  repo: Broodwar.Repo,
  prefix: false,
  notifier: Oban.Notifiers.PG,
  peer: false,
  queues: [default: 10, ingestion: 2],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron, crontab: [{"*/3 * * * *", Broodwar.Ingestion.StreamPoll}]}
  ]

# Base URL of the static site, which hosts player images.
config :broodwar, :static_site_url, "https://broodwar.live"

# Per-client-IP rate limits: bucket => {limit, window_ms}.
config :broodwar, :rate_limits,
  api: {600, :timer.minutes(1)},
  uploads: {10, :timer.hours(1)}

# Header carrying the real client IP behind a proxy (set in prod for Fly).
config :broodwar, :client_ip_header, nil

# Bearer token for /api/admin/* (set ADMIN_API_KEY in runtime.exs/env).
config :broodwar, :admin_api_key, nil

# Twitch Helix API credentials (read from env in config/runtime.exs).
config :broodwar, :twitch,
  client_id: "",
  client_secret: "",
  bw_game_id: "1466"

# SOOP (AfreecaTV) Open API. Requires a registered client_id from
# developers.sooplive.co.kr; polling is skipped until both are set
# (read from env in config/runtime.exs).
config :broodwar, :soop, client_id: "", category: ""

import_config "#{config_env()}.exs"

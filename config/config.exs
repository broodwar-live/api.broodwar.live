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
  queues: [default: 10, ingestion: 2]

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

# Twitch Helix API credentials (override in runtime.exs or env vars).
config :broodwar, :twitch,
  client_id: System.get_env("TWITCH_CLIENT_ID", ""),
  client_secret: System.get_env("TWITCH_CLIENT_SECRET", ""),
  bw_game_id: "1466"

import_config "#{config_env()}.exs"

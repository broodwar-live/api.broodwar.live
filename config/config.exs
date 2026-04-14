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

# Twitch Helix API credentials (override in runtime.exs or env vars).
config :broodwar, :twitch,
  client_id: System.get_env("TWITCH_CLIENT_ID", ""),
  client_secret: System.get_env("TWITCH_CLIENT_SECRET", ""),
  bw_game_id: "1466"

import_config "#{config_env()}.exs"

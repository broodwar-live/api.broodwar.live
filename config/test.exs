import Config

config :broodwar, Broodwar.Repo,
  database: Path.expand("../broodwar_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

config :broodwar, BroodwarWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "y78gijB+PYU9b7GmqEoOSLM1yuqCBcs2kRmLdcu6YLN42+qEM7Hpi6DRy7VOshoM",
  server: false

config :broodwar, Oban, testing: :inline

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :broodwar, :admin_api_key, "test-admin-key"

# Tight upload limit so the rate-limit test is quick; generous API limit.
config :broodwar, :rate_limits,
  api: {10_000, :timer.minutes(1)},
  uploads: {3, :timer.hours(1)}

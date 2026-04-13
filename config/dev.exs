import Config

config :broodwar, Broodwar.Repo,
  database: Path.expand("../broodwar_dev.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :broodwar, BroodwarWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "OYZFmyqKACFe2H9mr7JVHAppmp/bwQac1VsRN54Vnvse68hdgfoQgTzSNiuebobC"

config :broodwar, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

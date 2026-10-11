import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/broodwar start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :broodwar, BroodwarWeb.Endpoint, server: true
end

config :broodwar, BroodwarWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Stream polling credentials. Each platform is skipped while unset.
config :broodwar, :twitch,
  client_id: System.get_env("TWITCH_CLIENT_ID", ""),
  client_secret: System.get_env("TWITCH_CLIENT_SECRET", ""),
  bw_game_id: System.get_env("TWITCH_BW_GAME_ID", "1466")

config :broodwar, :soop,
  client_id: System.get_env("SOOP_CLIENT_ID", ""),
  category: System.get_env("SOOP_CATEGORY", "")

# Bearer token for /api/admin/*. Admin routes reject everything when unset.
if admin_api_key = System.get_env("ADMIN_API_KEY") do
  config :broodwar, :admin_api_key, admin_api_key
end

if config_env() == :prod do
  # On Fly the SQLite file lives on the volume mounted at /data.
  database_path = System.get_env("DATABASE_PATH", "/data/broodwar.db")

  config :broodwar, Broodwar.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    journal_mode: :wal

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST", "api.broodwar.live")

  # Behind Fly's proxy the real client IP arrives in Fly-Client-IP.
  config :broodwar, :client_ip_header, System.get_env("CLIENT_IP_HEADER", "fly-client-ip")

  config :broodwar, :static_site_url, System.get_env("STATIC_SITE_URL", "https://broodwar.live")

  config :broodwar, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :broodwar, BroodwarWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Bind on all IPv4 and IPv6 interfaces (Fly's proxy uses IPv6).
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base
end

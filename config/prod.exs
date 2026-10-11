import Config

# Fly terminates TLS at its edge and forwards plain HTTP with
# x-forwarded-proto, so rewrite on that header before redirecting. The
# health check is excluded so Fly's internal plain-HTTP probe isn't
# redirected. `:force_ssl` must be set at compile time.
config :broodwar, BroodwarWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      paths: ["/api/health"],
      hosts: ["localhost", "127.0.0.1"]
    ]
  ]

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.

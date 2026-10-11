defmodule BroodwarWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :broodwar

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :broodwar
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # Replay uploads are capped at 5 MiB in Broodwar.Replays; the multipart
  # limit leaves headroom for form overhead. Other bodies stay small.
  plug Plug.Parsers,
    parsers: [:urlencoded, {:multipart, length: 6_000_000}, :json],
    length: 1_000_000,
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug BroodwarWeb.Router
end

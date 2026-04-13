defmodule Broodwar.Repo do
  use Ecto.Repo,
    otp_app: :broodwar,
    adapter: Ecto.Adapters.SQLite3
end

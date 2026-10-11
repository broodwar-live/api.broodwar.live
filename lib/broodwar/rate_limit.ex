defmodule Broodwar.RateLimit do
  @moduledoc """
  In-memory (ETS) rate limiter. State is per-node, which is fine for a
  single Fly machine; switch to a shared backend if the API is scaled out.
  """
  use Hammer, backend: :ets
end

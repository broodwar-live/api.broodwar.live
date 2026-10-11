defmodule BroodwarWeb.Api.HealthController do
  use BroodwarWeb, :controller

  alias Ecto.Adapters.SQL

  @doc """
  GET /api/health — liveness/readiness probe for Fly. Checks the database
  is reachable. Excluded from `force_ssl` so the internal plain-HTTP health
  check is not redirected.
  """
  def show(conn, _params) do
    case SQL.query(Broodwar.Repo, "SELECT 1", []) do
      {:ok, _} ->
        json(conn, %{status: "ok"})

      {:error, _} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          error: %{code: "DB_UNAVAILABLE", message: "Database unavailable"}
        })
    end
  end
end

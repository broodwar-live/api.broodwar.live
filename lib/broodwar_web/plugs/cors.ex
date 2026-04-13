defmodule BroodwarWeb.Plugs.CORS do
  @moduledoc """
  Simple CORS plug for the broodwar.live static site.
  """
  import Plug.Conn

  @allowed_origins ["https://broodwar.live", "http://localhost:1111"]

  def init(opts), do: opts

  def call(%{method: "OPTIONS"} = conn, _opts) do
    conn
    |> set_cors_headers()
    |> send_resp(204, "")
    |> halt()
  end

  def call(conn, _opts) do
    set_cors_headers(conn)
  end

  defp set_cors_headers(conn) do
    origin = get_req_header(conn, "origin") |> List.first()

    if origin in @allowed_origins do
      conn
      |> put_resp_header("access-control-allow-origin", origin)
      |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
      |> put_resp_header("access-control-allow-headers", "content-type, accept")
      |> put_resp_header("access-control-max-age", "86400")
    else
      conn
    end
  end
end

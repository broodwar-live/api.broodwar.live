defmodule BroodwarWeb.Plugs.AdminAuth do
  @moduledoc """
  Bearer-token auth for admin routes.

  The expected token comes from `config :broodwar, :admin_api_key` (set from
  the `ADMIN_API_KEY` env var). When it is unset every admin request is
  rejected. Tokens are compared in constant time.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    expected = Application.get_env(:broodwar, :admin_api_key)

    with key when is_binary(key) and key != "" <- expected,
         ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <-
           Plug.Crypto.secure_compare(:crypto.hash(:sha256, token), :crypto.hash(:sha256, key)) do
      conn
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> put_resp_content_type("application/json")
    |> send_resp(
      401,
      Jason.encode!(%{error: %{code: "UNAUTHORIZED", message: "Missing or invalid API key"}})
    )
    |> halt()
  end
end

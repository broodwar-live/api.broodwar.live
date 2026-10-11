defmodule BroodwarWeb.Plugs.RateLimit do
  @moduledoc """
  Per-client-IP rate limiting backed by `Broodwar.RateLimit`.

      plug BroodwarWeb.Plugs.RateLimit, bucket: :uploads

  Limits are read at runtime from `config :broodwar, :rate_limits`, a keyword
  list of `bucket: {limit, scale_ms}`. Requires `BroodwarWeb.Plugs.ClientIP`
  to have run first. Responds `429` with a `retry-after` header when denied.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :bucket)

  @impl Plug
  def call(conn, bucket) do
    case Keyword.get(Application.get_env(:broodwar, :rate_limits, []), bucket) do
      {limit, scale_ms} -> check(conn, bucket, limit, scale_ms)
      nil -> conn
    end
  end

  defp check(conn, bucket, limit, scale_ms) do
    key = "#{bucket}:#{conn.assigns[:client_ip] || "unknown"}"

    case Broodwar.RateLimit.hit(key, scale_ms, limit) do
      {:allow, _count} ->
        conn

      {:deny, retry_after_ms} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(div(retry_after_ms, 1000) + 1))
        |> put_resp_content_type("application/json")
        |> send_resp(
          429,
          Jason.encode!(%{
            error: %{code: "RATE_LIMITED", message: "Too many requests, slow down."}
          })
        )
        |> halt()
    end
  end
end

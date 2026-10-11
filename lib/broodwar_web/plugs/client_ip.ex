defmodule BroodwarWeb.Plugs.ClientIP do
  @moduledoc """
  Resolves the real client IP into `conn.assigns.client_ip`.

  Behind Fly's proxy `conn.remote_ip` is the proxy address, so the header
  named by `config :broodwar, :client_ip_header` (e.g. `"fly-client-ip"`) is
  used when configured. It is ignored otherwise, since clients can forge it.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    assign(conn, :client_ip, client_ip(conn))
  end

  defp client_ip(conn) do
    with header when is_binary(header) <- Application.get_env(:broodwar, :client_ip_header),
         [value | _] <- get_req_header(conn, header),
         {:ok, ip} <- value |> String.trim() |> String.to_charlist() |> :inet.parse_address() do
      :inet.ntoa(ip) |> to_string()
    else
      _ -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end

defmodule BroodwarWeb.Api.StreamController do
  use BroodwarWeb, :controller

  alias Broodwar.Streams
  alias BroodwarWeb.Api.JSON

  action_fallback BroodwarWeb.Api.FallbackController

  def index(conn, params) do
    opts =
      []
      |> maybe_put(:platform, params["platform"])
      |> maybe_put(:live, parse_bool(params["live"]))

    streams = Streams.list_streams(opts)
    json(conn, %{data: Enum.map(streams, &JSON.stream/1)})
  end

  def show(conn, %{"id" => id}) do
    stream = Streams.get_stream!(id)
    json(conn, %{data: JSON.stream(stream)})
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_bool("true"), do: true
  defp parse_bool("1"), do: true
  defp parse_bool(_), do: nil
end

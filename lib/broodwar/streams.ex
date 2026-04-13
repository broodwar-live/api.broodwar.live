defmodule Broodwar.Streams do
  @moduledoc """
  Context for live stream tracking.
  """
  import Ecto.Query
  alias Broodwar.Repo
  alias Broodwar.Streams.Stream

  def list_streams(opts \\ []) do
    Stream
    |> order_by(desc: :is_live, desc: :viewer_count)
    |> maybe_filter_platform(opts[:platform])
    |> maybe_filter_live(opts[:live])
    |> preload(:player)
    |> Repo.all()
  end

  def get_stream!(id) do
    Stream
    |> preload(:player)
    |> Repo.get!(id)
  end

  defp maybe_filter_platform(query, nil), do: query
  defp maybe_filter_platform(query, platform), do: where(query, [s], s.platform == ^platform)

  defp maybe_filter_live(query, nil), do: query
  defp maybe_filter_live(query, true), do: where(query, [s], s.is_live == true)
  defp maybe_filter_live(query, _), do: query
end

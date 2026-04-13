defmodule BroodwarWeb.Api.PlayerController do
  use BroodwarWeb, :controller

  alias Broodwar.Players
  alias Broodwar.Pagination
  alias BroodwarWeb.Api.JSON

  action_fallback BroodwarWeb.Api.FallbackController

  def index(conn, params) do
    opts =
      []
      |> maybe_put(:race, params["race"])
      |> maybe_put(:status, params["status"])
      |> maybe_put(:search, params["search"])

    pagination_opts = parse_pagination(params)

    players =
      Players.list_players(opts)
      |> paginate(pagination_opts)

    json(conn, %{
      data: Enum.map(players, &JSON.player/1),
      pagination: Pagination.pagination_meta(pagination_opts)
    })
  end

  def show(conn, %{"id" => id}) do
    player = Players.get_player!(id)
    json(conn, %{data: JSON.player(player)})
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  def matches(conn, %{"player_id" => id}) do
    _player = Players.get_player!(id)
    matches = Players.get_player_matches(id)
    json(conn, %{data: Enum.map(matches, &JSON.match/1)})
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  def stats(conn, %{"player_id" => id}) do
    player = Players.get_player!(id)
    tournament_matches = Players.get_tournament_matches(player.name)
    stats = Players.compute_stats(tournament_matches)
    json(conn, %{data: stats})
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_pagination(params) do
    [
      page: parse_int(params["page"], 1),
      per_page: parse_int(params["per_page"], 50)
    ]
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end
  defp parse_int(val, _default) when is_integer(val), do: val
  defp parse_int(_, default), do: default

  defp paginate(list, opts) when is_list(list) do
    meta = Pagination.pagination_meta(opts)
    offset = (meta.page - 1) * meta.per_page

    list
    |> Enum.drop(offset)
    |> Enum.take(meta.per_page)
  end
end

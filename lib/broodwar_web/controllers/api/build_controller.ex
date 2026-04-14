defmodule BroodwarWeb.Api.BuildController do
  use BroodwarWeb, :controller

  alias Broodwar.BuildsContext
  alias Broodwar.Pagination
  alias BroodwarWeb.Api.JSON

  action_fallback BroodwarWeb.Api.FallbackController

  def index(conn, params) do
    opts =
      []
      |> maybe_put(:race, params["race"])
      |> maybe_put(:matchup, params["matchup"])

    pagination_opts = parse_pagination(params)

    builds =
      BuildsContext.list_builds(opts)
      |> paginate(pagination_opts)

    json(conn, %{
      data: Enum.map(builds, &JSON.build/1),
      pagination: Pagination.pagination_meta(pagination_opts)
    })
  end

  def show(conn, %{"id" => id}) do
    build = BuildsContext.get_build!(id)
    json(conn, %{data: JSON.build(build)})
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  @doc """
  GET /api/openings — aggregated opening classifications from replay data.

  Query params: ?race=T&matchup=TvZ
  """
  def openings(conn, params) do
    opts =
      []
      |> maybe_put(:race, params["race"])
      |> maybe_put(:matchup, params["matchup"])

    cache_key = "openings:#{params["race"] || "all"}:#{params["matchup"] || "all"}"
    openings = Broodwar.Cache.fetch(cache_key, 300, fn ->
      BuildsContext.list_openings(opts)
    end)
    json(conn, %{data: openings})
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

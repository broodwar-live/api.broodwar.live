defmodule BroodwarWeb.Api.MatchController do
  use BroodwarWeb, :controller

  alias Broodwar.Matches
  alias Broodwar.Pagination
  alias BroodwarWeb.Api.JSON

  action_fallback BroodwarWeb.Api.FallbackController

  def index(conn, params) do
    opts =
      []
      |> maybe_put(:tournament_id, parse_int(params["tournament_id"]))
      |> maybe_put(:matchup, params["matchup"])

    pagination_opts = parse_pagination(params)

    matches =
      Matches.list_matches(opts)
      |> paginate(pagination_opts)

    json(conn, %{
      data: Enum.map(matches, &JSON.match/1),
      pagination: Pagination.pagination_meta(pagination_opts)
    })
  end

  def show(conn, %{"id" => id}) do
    match = Matches.get_match!(id)
    json(conn, %{data: JSON.match(match)})
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_int(nil), do: nil
  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> nil
    end
  end
  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(_), do: nil

  defp parse_pagination(params) do
    [
      page: parse_int(params["page"]) || 1,
      per_page: parse_int(params["per_page"]) || 50
    ]
  end

  defp paginate(list, opts) when is_list(list) do
    meta = Pagination.pagination_meta(opts)
    offset = (meta.page - 1) * meta.per_page

    list
    |> Enum.drop(offset)
    |> Enum.take(meta.per_page)
  end
end

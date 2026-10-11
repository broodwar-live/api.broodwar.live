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
      BuildsContext.list_builds(opts ++ pagination_opts)

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
    # Only whitelisted values reach the cache key, so the key space is
    # bounded (4 race options x 17 matchup options).
    with {:ok, race} <- normalize_race(params["race"]),
         {:ok, matchup} <- normalize_matchup(params["matchup"]) do
      cache_key = "openings:#{race || "all"}:#{matchup || "all"}"

      openings =
        Broodwar.Cache.fetch(cache_key, 300, fn ->
          BuildsContext.list_openings(race: race, matchup: matchup)
        end)

      json(conn, %{data: openings})
    end
  end

  defp normalize_race(nil), do: {:ok, nil}
  defp normalize_race(""), do: {:ok, nil}

  defp normalize_race(race) when is_binary(race) do
    case race |> String.trim() |> String.upcase() do
      r when r in ["T", "TERRAN"] -> {:ok, "T"}
      r when r in ["P", "PROTOSS"] -> {:ok, "P"}
      r when r in ["Z", "ZERG"] -> {:ok, "Z"}
      _ -> {:error, "Invalid race. Use T, P or Z."}
    end
  end

  defp normalize_race(_), do: {:error, "Invalid race. Use T, P or Z."}

  defp normalize_matchup(nil), do: {:ok, nil}
  defp normalize_matchup(""), do: {:ok, nil}

  defp normalize_matchup(matchup) when is_binary(matchup) do
    case matchup |> String.trim() |> String.upcase() do
      <<a, "V", b>> when a in ~c"TPZR" and b in ~c"TPZR" -> {:ok, <<a, "v", b>>}
      _ -> {:error, "Invalid matchup. Use e.g. TvZ."}
    end
  end

  defp normalize_matchup(_), do: {:error, "Invalid matchup. Use e.g. TvZ."}

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
end

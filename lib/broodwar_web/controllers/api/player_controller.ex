defmodule BroodwarWeb.Api.PlayerController do
  use BroodwarWeb, :controller

  alias Broodwar.Pagination
  alias Broodwar.Players
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
      Players.list_players(opts ++ pagination_opts)

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

  def matches(conn, %{"player_id" => id} = params) do
    player = Players.get_player!(id)
    pagination_opts = parse_pagination(params)
    matches = Players.get_player_matches(player.id, pagination_opts)

    json(conn, %{
      data: Enum.map(matches, &JSON.match/1),
      pagination:
        pagination_opts
        |> Pagination.pagination_meta()
        |> Map.put(:total, Players.count_player_matches(player.id)),
      meta: %{source: Broodwar.Stats.attribution()}
    })
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  @doc """
  GET /api/players/:id/ratings — Elo history, oldest first (one point per
  rated game). Paginated; `pagination.total` is the number of games.
  """
  def ratings(conn, %{"player_id" => id} = params) do
    player = Players.get_player!(id)
    pagination_opts = parse_pagination(params)
    history = Broodwar.Ratings.history(player.id, pagination_opts)

    json(conn, %{
      data: %{
        player: JSON.player_summary(player),
        rating: player.rating,
        n: player.rated_games,
        history: Enum.map(history, &JSON.rating_point/1)
      },
      pagination:
        pagination_opts
        |> Pagination.pagination_meta()
        |> Map.put(:total, Broodwar.Ratings.history_count(player.id)),
      meta: %{source: Broodwar.Stats.attribution()}
    })
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  def stats(conn, %{"player_id" => id}) do
    player = Players.get_player!(id)
    tournament_matches = Players.get_tournament_matches(player.id)
    tournament_stats = Players.compute_stats(tournament_matches)
    replay_stats = Players.compute_replay_stats(player.name)

    json(conn, %{
      data: %{
        tournament: tournament_stats,
        replays: replay_stats
      },
      meta: %{source: Broodwar.Stats.attribution()}
    })
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
end

defmodule Broodwar.Matches do
  @moduledoc """
  Context for series (matches) and their games. Aggregate statistics live
  in `Broodwar.Stats`; ratings in `Broodwar.Ratings`.
  """
  import Ecto.Query
  alias Broodwar.Matches.Match
  alias Broodwar.Pagination
  alias Broodwar.Repo

  def list_matches(opts \\ []) do
    Match
    |> order_by(desc: :played_at, desc: :id)
    |> maybe_filter_tournament(opts[:tournament_id])
    |> maybe_filter_matchup(opts[:matchup])
    |> preload([:tournament, :player_a, :player_b, :map])
    |> Pagination.paginate(opts)
    |> Repo.all()
  end

  def get_match!(id) do
    Match
    |> preload([:tournament, :player_a, :player_b, :map, :winner, games: :map])
    |> Repo.get!(id)
  end

  defp parse_matchup(<<a::binary-size(1), "v", b::binary-size(1)>>), do: {a, b}

  defp maybe_filter_tournament(query, nil), do: query

  defp maybe_filter_tournament(query, tid),
    do: where(query, [m], m.tournament_id == ^tid)

  defp maybe_filter_matchup(query, nil), do: query

  defp maybe_filter_matchup(query, matchup) do
    {ra, rb} = parse_matchup(matchup)

    where(
      query,
      [m],
      (m.race_a == ^ra and m.race_b == ^rb) or (m.race_a == ^rb and m.race_b == ^ra)
    )
  end
end

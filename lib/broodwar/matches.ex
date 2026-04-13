defmodule Broodwar.Matches do
  import Ecto.Query
  alias Broodwar.Repo
  alias Broodwar.Matches.Match

  def list_matches(opts \\ []) do
    Match
    |> order_by(desc: :played_at)
    |> maybe_filter_tournament(opts[:tournament_id])
    |> maybe_filter_matchup(opts[:matchup])
    |> preload([:tournament, :player_a, :player_b, :map])
    |> Repo.all()
  end

  def get_match!(id) do
    Match
    |> preload([:tournament, :player_a, :player_b, :map])
    |> Repo.get!(id)
  end

  def balance_stats do
    matches = Repo.all(from(m in Match, where: not is_nil(m.played_at)))

    matchups = ["TvZ", "PvT", "ZvP", "TvT", "PvP", "ZvZ"]

    Enum.map(matchups, fn matchup ->
      {race_a, race_b} = parse_matchup(matchup)

      relevant =
        Enum.filter(matches, fn m ->
          (m.race_a == race_a and m.race_b == race_b) or
            (m.race_a == race_b and m.race_b == race_a)
        end)

      total = length(relevant)

      wins_a =
        Enum.count(relevant, fn m ->
          (m.race_a == race_a and m.score_a > m.score_b) or
            (m.race_b == race_a and m.score_b > m.score_a)
        end)

      pct_a = if total > 0, do: round(wins_a / total * 100), else: 50

      %{matchup: matchup, total: total, pct_a: pct_a, pct_b: 100 - pct_a}
    end)
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

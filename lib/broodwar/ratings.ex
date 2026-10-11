defmodule Broodwar.Ratings do
  @moduledoc """
  Elo ratings computed from individual games.

  ## Model

  Plain Elo, updated after every game (one map), in chronological order:

    * everyone starts at #{1500}
    * expected score `E = 1 / (1 + 10^((R_opp - R) / 400))`
    * `R' = R + K * (S - E)` with each player's own K:
      * K = 40 for a player's first 30 rated games (find the level fast)
      * K = 24 up to 100 games
      * K = 16 afterwards (stable for established pros)

  ## Why Elo and not Glicko-2

  Glicko-2 models rating uncertainty and inflates it during inactivity,
  which suits sparse data in principle. It was not chosen because:

    * Glicko-2 updates per *rating period*; games inside a period are
      treated as simultaneous. Pro BW data has exact game order (dates plus
      the order on the Liquipedia page), and per-game Elo uses all of it.
    * Its output depends on the period length and the volatility constant
      (tau), two tuning knobs without a principled value for this data,
      whereas the K schedule above is easy to explain and audit.
    * The two things Glicko buys us are handled separately: provisional
      ratings get a high K, and inactivity is handled by the rankings
      filter (minimum games + activity window) instead of by the rating.

  ## Which games count

    * every Liquipedia game with a date (walkovers create no games)
    * games from replays only once an admin has linked the replay to
      players (anonymous uploads never create games)
    * score-only series contribute `inferred` games in a fixed order

  Undated games are skipped (they cannot be placed in time).

  ## Determinism

  `recompute/0` throws away all derived ratings and replays every game in a
  total order: `played_at`, source page, position on the page, game
  number, id. The same games always produce bit-identical history.
  """

  import Ecto.Query

  alias Broodwar.Matches.Game
  alias Broodwar.Players.Player
  alias Broodwar.Ratings.RatingHistory
  alias Broodwar.Repo

  @initial 1500.0

  @doc "Initial rating for a new player."
  def initial_rating, do: @initial

  @doc "K factor for a player who has played `games` rated games so far."
  @spec k_factor(non_neg_integer()) :: pos_integer()
  def k_factor(games) when games < 30, do: 40
  def k_factor(games) when games < 100, do: 24
  def k_factor(_games), do: 16

  @doc "Expected score of a player rated `r` against one rated `r_opp`."
  @spec expected_score(number(), number()) :: float()
  def expected_score(r, r_opp), do: 1.0 / (1.0 + :math.pow(10.0, (r_opp - r) / 400.0))

  @doc """
  Rebuilds `rating_history` and every player's `rating`, `rated_games` and
  `last_played_at` from games, in one transaction.

  Returns `{:ok, %{games: rated, players: n, undated: skipped}}`.
  """
  @spec recompute() :: {:ok, map()} | {:error, term()}
  def recompute do
    result =
      Repo.transaction(
        fn ->
          Repo.delete_all(RatingHistory)
          Repo.update_all(Player, set: [rating: nil, rated_games: 0, last_played_at: nil])

          {games, undated} = load_games()
          {history, players} = replay_games(games)

          history
          |> Enum.chunk_every(1_000)
          |> Enum.each(&Repo.insert_all(RatingHistory, &1))

          Enum.each(players, fn {id, p} ->
            Repo.update_all(where(Player, id: ^id),
              set: [rating: round(p.rating), rated_games: p.games, last_played_at: p.last]
            )
          end)

          %{games: length(games), players: map_size(players), undated: undated}
        end,
        timeout: :infinity
      )

    Broodwar.Cache.invalidate_all()
    result
  end

  defp load_games do
    undated = Repo.aggregate(where(Game, [g], is_nil(g.played_at)), :count)

    games =
      Repo.all(
        from g in Game,
          where: not is_nil(g.played_at),
          order_by: [
            asc: g.played_at,
            asc: coalesce(g.source_page, ""),
            asc: coalesce(g.page_order, 0),
            asc: g.game_number,
            asc: g.id
          ],
          select: %{
            id: g.id,
            a: g.player_a_id,
            b: g.player_b_id,
            winner: g.winner_id,
            played_at: g.played_at
          }
      )

    {games, undated}
  end

  # Pure fold over ordered games -> {history rows, final player states}.
  defp replay_games(games) do
    {rows, players, _seq} =
      Enum.reduce(games, {[], %{}, 0}, fn game, {rows, players, seq} ->
        pa = Map.get(players, game.a, new_state())
        pb = Map.get(players, game.b, new_state())
        a_won = game.winner == game.a

        ea = expected_score(pa.rating, pb.rating)
        sa = if a_won, do: 1.0, else: 0.0
        ra = pa.rating + k_factor(pa.games) * (sa - ea)
        rb = pb.rating + k_factor(pb.games) * (1.0 - sa - (1.0 - ea))

        new_a = %{rating: ra, games: pa.games + 1, last: game.played_at}
        new_b = %{rating: rb, games: pb.games + 1, last: game.played_at}

        row_a = row(game, game.a, game.b, a_won, pa, new_a, seq + 1)
        row_b = row(game, game.b, game.a, not a_won, pb, new_b, seq + 1)

        {[row_b, row_a | rows], players |> Map.put(game.a, new_a) |> Map.put(game.b, new_b),
         seq + 1}
      end)

    {Enum.reverse(rows), players}
  end

  defp new_state, do: %{rating: @initial, games: 0, last: nil}

  defp row(game, player, opponent, won, before, after_state, seq) do
    %{
      player_id: player,
      opponent_id: opponent,
      game_id: game.id,
      won: won,
      rating_before: before.rating,
      rating_after: after_state.rating,
      games_played: after_state.games,
      played_at: game.played_at,
      sequence: seq
    }
  end

  @doc """
  Rating history for a player, oldest first, with opponent names.
  """
  def history(player_id, opts \\ []) do
    from(h in RatingHistory,
      where: h.player_id == ^player_id,
      join: o in assoc(h, :opponent),
      join: g in assoc(h, :game),
      order_by: [asc: h.sequence],
      select: %{
        game_id: h.game_id,
        match_id: g.match_id,
        replay_id: g.replay_id,
        played_at: h.played_at,
        won: h.won,
        rating_before: h.rating_before,
        rating_after: h.rating_after,
        games_played: h.games_played,
        opponent_id: o.id,
        opponent_name: o.name
      }
    )
    |> Broodwar.Pagination.paginate(opts)
    |> Repo.all()
  end

  @doc "Number of rating history entries for a player."
  def history_count(player_id) do
    Repo.aggregate(where(RatingHistory, player_id: ^player_id), :count)
  end

  @doc """
  Current ratings of active, established players.

  Options: `:min_games` and `:active_days` (defaults from
  `config :broodwar, :rankings`), plus pagination.
  """
  def rankings(opts \\ []) do
    {min_games, active_days} = ranking_criteria(opts)
    cutoff = DateTime.utc_now() |> DateTime.add(-active_days * 86_400, :second)

    from(p in Player,
      where: not is_nil(p.rating) and p.rated_games >= ^min_games and p.last_played_at >= ^cutoff,
      order_by: [desc: p.rating, asc: p.id]
    )
    |> Broodwar.Pagination.paginate(opts)
    |> Repo.all()
  end

  @doc "Effective `{min_games, active_days}` for rankings."
  def ranking_criteria(opts \\ []) do
    config = Application.get_env(:broodwar, :rankings, [])
    min_games = opts[:min_games] || Keyword.get(config, :min_games, 20)
    active_days = opts[:active_days] || Keyword.get(config, :active_days, 365)
    {min_games, active_days}
  end
end

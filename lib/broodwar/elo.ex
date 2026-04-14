defmodule Broodwar.Elo do
  @moduledoc """
  Elo rating system for Brood War players.

  Updates player ratings based on game results from replay analysis.
  Uses standard Elo with configurable K-factor.

  ## K-Factor

  - New players (< 30 games): K=40 (ratings adjust quickly)
  - Established players: K=20
  - High-rated players (> 2400): K=10

  ## Usage

      Broodwar.Elo.update_ratings("Flash", "Jaedong", :player_a)
      # Updates both players' ratings based on the result
  """

  import Ecto.Query
  alias Broodwar.Repo
  alias Broodwar.Players.Player

  @default_rating 1500
  @k_new 40
  @k_normal 20
  @k_high 10
  @high_rating_threshold 2400

  @doc """
  Update ratings for two players based on a game result.

  `winner` is `:player_a` or `:player_b`.
  Returns `{:ok, {new_rating_a, new_rating_b}}` or `{:error, reason}`.
  """
  def update_ratings(name_a, name_b, winner) when winner in [:player_a, :player_b] do
    with {:ok, player_a} <- find_or_create_player(name_a),
         {:ok, player_b} <- find_or_create_player(name_b) do
      rating_a = player_a.rating || @default_rating
      rating_b = player_b.rating || @default_rating

      {score_a, score_b} =
        case winner do
          :player_a -> {1.0, 0.0}
          :player_b -> {0.0, 1.0}
        end

      expected_a = expected_score(rating_a, rating_b)
      expected_b = 1.0 - expected_a

      k_a = k_factor(player_a)
      k_b = k_factor(player_b)

      new_rating_a = round(rating_a + k_a * (score_a - expected_a))
      new_rating_b = round(rating_b + k_b * (score_b - expected_b))

      Repo.update!(Player.changeset(player_a, %{rating: new_rating_a}))
      Repo.update!(Player.changeset(player_b, %{rating: new_rating_b}))

      {:ok, {new_rating_a, new_rating_b}}
    end
  end

  @doc """
  Update ratings from a parsed replay's metadata.

  Looks at the winner from the replay metadata and updates both players.
  """
  def update_from_replay(parsed_data) do
    players = get_in(parsed_data, ["header", "players"]) || []
    metadata = parsed_data["metadata"] || %{}

    with [p_a, p_b] <- Enum.take(players, 2),
         %{"player_name" => winner_name} <- metadata["result"] do
      name_a = p_a["name"]
      name_b = p_b["name"]

      winner =
        cond do
          winner_name == name_a -> :player_a
          winner_name == name_b -> :player_b
          true -> nil
        end

      if winner do
        update_ratings(name_a, name_b, winner)
      else
        {:error, :no_winner}
      end
    else
      _ -> {:error, :insufficient_data}
    end
  end

  @doc """
  Calculate expected score for player A against player B.
  Returns a float between 0.0 and 1.0.
  """
  def expected_score(rating_a, rating_b) do
    1.0 / (1.0 + :math.pow(10.0, (rating_b - rating_a) / 400.0))
  end

  # -- Private --

  defp k_factor(%Player{rating: rating}) when is_integer(rating) and rating > @high_rating_threshold,
    do: @k_high

  defp k_factor(%Player{} = player) do
    # Count games played (approximate from replay count).
    game_count =
      Repo.one(
        from(r in Broodwar.Replays.Replay,
          where: r.player_a_id == ^player.id or r.player_b_id == ^player.id,
          select: count()
        )
      ) || 0

    if game_count < 30, do: @k_new, else: @k_normal
  end

  defp find_or_create_player(name) do
    case Repo.one(from(p in Player, where: p.name == ^name)) do
      nil ->
        %Player{}
        |> Player.changeset(%{name: name, rating: @default_rating})
        |> Repo.insert()

      player ->
        {:ok, player}
    end
  end
end

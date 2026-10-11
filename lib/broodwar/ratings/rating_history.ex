defmodule Broodwar.Ratings.RatingHistory do
  @moduledoc """
  One rating change for one player in one game. The whole table is rebuilt
  by `Broodwar.Ratings.recompute/0`; `sequence` is the global game order.
  """
  use Ecto.Schema

  schema "rating_history" do
    belongs_to :player, Broodwar.Players.Player
    belongs_to :game, Broodwar.Matches.Game
    belongs_to :opponent, Broodwar.Players.Player

    field :won, :boolean
    field :rating_before, :float
    field :rating_after, :float
    field :games_played, :integer
    field :played_at, :utc_datetime
    field :sequence, :integer
  end
end

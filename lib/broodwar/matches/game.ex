defmodule Broodwar.Matches.Game do
  @moduledoc """
  A single game (one map). Ratings and map/balance statistics are computed
  from games. A game belongs either to a Liquipedia series (`match_id`) or
  to an admin-linked replay (`replay_id`).

  `inferred` games come from series that only record a score: the result
  is known, the map and order are not.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "games" do
    belongs_to :match, Broodwar.Matches.Match
    belongs_to :replay, Broodwar.Replays.Replay
    belongs_to :map, Broodwar.Maps.Map
    belongs_to :player_a, Broodwar.Players.Player
    belongs_to :player_b, Broodwar.Players.Player
    belongs_to :winner, Broodwar.Players.Player

    field :game_number, :integer, default: 1
    field :map_name, :string
    field :race_a, :string
    field :race_b, :string
    field :played_at, :utc_datetime
    field :inferred, :boolean, default: false
    field :source, :string
    field :source_page, :string
    field :page_order, :integer

    timestamps()
  end

  @required_fields [:player_a_id, :player_b_id, :winner_id, :source]
  @optional_fields [
    :match_id,
    :replay_id,
    :map_id,
    :game_number,
    :map_name,
    :race_a,
    :race_b,
    :played_at,
    :inferred,
    :source_page,
    :page_order
  ]
  @valid_races ~w(T P Z R)

  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:race_a, @valid_races)
    |> validate_inclusion(:race_b, @valid_races)
    |> validate_inclusion(:source, ~w(liquipedia replay))
    |> unique_constraint([:match_id, :game_number])
    |> unique_constraint(:replay_id)
  end
end

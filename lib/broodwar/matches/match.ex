defmodule Broodwar.Matches.Match do
  use Ecto.Schema
  import Ecto.Changeset

  schema "matches" do
    belongs_to :tournament, Broodwar.Tournaments.Tournament
    belongs_to :map, Broodwar.Maps.Map
    belongs_to :player_a, Broodwar.Players.Player
    belongs_to :player_b, Broodwar.Players.Player

    field :round, :string
    field :race_a, :string
    field :race_b, :string
    field :score_a, :integer, default: 0
    field :score_b, :integer, default: 0
    field :played_at, :utc_datetime
    field :source, :string

    timestamps()
  end

  @required_fields [:player_a_id, :player_b_id, :race_a, :race_b]
  @optional_fields [:tournament_id, :map_id, :round, :score_a, :score_b, :played_at, :source]
  @valid_races ~w(T P Z R)

  @doc false
  def changeset(match, attrs) do
    match
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:race_a, @valid_races)
    |> validate_inclusion(:race_b, @valid_races)
    |> foreign_key_constraint(:player_a_id)
    |> foreign_key_constraint(:player_b_id)
    |> foreign_key_constraint(:tournament_id)
    |> foreign_key_constraint(:map_id)
  end
end

defmodule Broodwar.Builds.Build do
  use Ecto.Schema
  import Ecto.Changeset

  schema "builds" do
    field :name, :string
    field :race, :string
    field :matchup, :string
    field :description, :string
    field :tags, {:array, :string}, default: []
    field :games, :integer, default: 0
    field :winrate, :integer
    field :upvotes, :integer, default: 0

    many_to_many :replays, Broodwar.Replays.Replay, join_through: "build_replays"

    timestamps()
  end

  @required_fields [:name, :race, :matchup]
  @optional_fields [:description, :tags, :games, :winrate, :upvotes]
  @valid_races ~w(T P Z)
  @valid_matchups ~w(TvT TvZ TvP PvT PvZ PvP ZvT ZvP ZvZ)

  @doc false
  def changeset(build, attrs) do
    build
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:race, @valid_races)
    |> validate_inclusion(:matchup, @valid_matchups)
    |> validate_number(:winrate, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end

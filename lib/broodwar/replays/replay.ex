defmodule Broodwar.Replays.Replay do
  use Ecto.Schema
  import Ecto.Changeset

  schema "replays" do
    belongs_to :map, Broodwar.Maps.Map
    belongs_to :match, Broodwar.Matches.Match
    belongs_to :player_a, Broodwar.Players.Player
    belongs_to :player_b, Broodwar.Players.Player

    field :file_hash, :string
    field :file_path, :string
    field :race_a, :string
    field :race_b, :string
    field :duration, :integer
    field :game_version, :string
    field :played_at, :utc_datetime
    field :parsed_data, :map

    timestamps()
  end

  @required_fields [:file_hash]
  @optional_fields [
    :file_path,
    :map_id,
    :match_id,
    :player_a_id,
    :player_b_id,
    :race_a,
    :race_b,
    :duration,
    :game_version,
    :played_at,
    :parsed_data
  ]
  @valid_races ~w(T P Z R)

  @doc false
  def changeset(replay, attrs) do
    replay
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:race_a, @valid_races)
    |> validate_inclusion(:race_b, @valid_races)
    |> unique_constraint(:file_hash)
  end
end

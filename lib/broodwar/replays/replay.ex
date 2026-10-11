defmodule Broodwar.Replays.Replay do
  @moduledoc """
  A parsed `.rep` file. `parsed_data` holds the full NIF output; the other
  columns are denormalized from it for cheap filtering.
  """
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
    field :matchup, :string
    field :map_name_normalized, :string
    field :player_a_name, :string
    field :player_b_name, :string
    field :winner_name, :string
    field :classification_a, :string
    field :classification_b, :string
    field :source, :string, default: "upload"
    field :rated_at, :utc_datetime

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
    :parsed_data,
    :matchup,
    :map_name_normalized,
    :player_a_name,
    :player_b_name,
    :winner_name,
    :classification_a,
    :classification_b,
    :source,
    :rated_at
  ]
  @valid_races ~w(T P Z R)
  @valid_sources ~w(upload import admin)

  @doc "All columns except `parsed_data`, for list queries."
  def summary_fields, do: __schema__(:fields) -- [:parsed_data]

  @doc false
  def changeset(replay, attrs) do
    replay
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:race_a, @valid_races)
    |> validate_inclusion(:race_b, @valid_races)
    |> validate_inclusion(:source, @valid_sources)
    |> unique_constraint(:file_hash)
  end
end

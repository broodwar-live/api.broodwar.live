defmodule Broodwar.Streams.Stream do
  use Ecto.Schema
  import Ecto.Changeset

  schema "streams" do
    belongs_to :player, Broodwar.Players.Player

    field :channel_id, :string
    field :platform, :string
    field :title, :string
    field :is_live, :boolean, default: false
    field :viewer_count, :integer, default: 0
    field :last_seen_at, :utc_datetime

    timestamps()
  end

  @required_fields [:channel_id, :platform]
  @optional_fields [:player_id, :title, :is_live, :viewer_count, :last_seen_at]
  @valid_platforms ~w(afreeca twitch youtube)

  @doc false
  def changeset(stream, attrs) do
    stream
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:platform, @valid_platforms)
    |> unique_constraint([:platform, :channel_id])
  end
end

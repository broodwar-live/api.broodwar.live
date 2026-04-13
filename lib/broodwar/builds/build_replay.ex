defmodule Broodwar.Builds.BuildReplay do
  use Ecto.Schema
  import Ecto.Changeset

  schema "build_replays" do
    belongs_to :build, Broodwar.Builds.Build
    belongs_to :replay, Broodwar.Replays.Replay

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(build_replay, attrs) do
    build_replay
    |> cast(attrs, [:build_id, :replay_id])
    |> validate_required([:build_id, :replay_id])
    |> unique_constraint([:build_id, :replay_id])
    |> foreign_key_constraint(:build_id)
    |> foreign_key_constraint(:replay_id)
  end
end

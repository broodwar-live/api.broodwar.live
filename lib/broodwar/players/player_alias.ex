defmodule Broodwar.Players.PlayerAlias do
  @moduledoc """
  A name a player is known by. Sources: `"liquipedia"` (page title),
  `"name"` (display name), `"profile"` (IDs from the Liquipedia infobox),
  `"admin"` (in-game name confirmed when an admin linked a replay).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_aliases" do
    belongs_to :player, Broodwar.Players.Player
    field :alias, :string
    field :normalized, :string
    field :source, :string

    timestamps()
  end

  @doc false
  def changeset(player_alias, attrs) do
    player_alias
    |> cast(attrs, [:player_id, :alias, :normalized, :source])
    |> validate_required([:player_id, :alias, :normalized, :source])
    |> validate_inclusion(:source, ~w(liquipedia name profile admin))
    |> unique_constraint([:player_id, :normalized])
  end
end

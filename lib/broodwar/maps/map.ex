defmodule Broodwar.Maps.Map do
  use Ecto.Schema
  import Ecto.Changeset

  schema "maps" do
    field :name, :string
    field :width, :integer
    field :height, :integer
    field :tileset, :string
    field :spawn_positions, {:array, :map}, default: []

    timestamps()
  end

  @required_fields [:name]
  @optional_fields [:width, :height, :tileset, :spawn_positions]

  @doc false
  def changeset(map, attrs) do
    map
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
  end
end

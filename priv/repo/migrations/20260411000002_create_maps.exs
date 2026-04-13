defmodule Broodwar.Repo.Migrations.CreateMaps do
  use Ecto.Migration

  def change do
    create table(:maps) do
      add :name, :string, null: false
      add :width, :integer
      add :height, :integer
      add :tileset, :string
      add :spawn_positions, :string, default: "[]"

      timestamps()
    end

    create unique_index(:maps, [:name])
  end
end

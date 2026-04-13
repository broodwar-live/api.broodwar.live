defmodule Broodwar.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players) do
      add :name, :string, null: false
      add :aliases, :string, default: "[]"
      add :race, :string
      add :country, :string
      add :rating, :integer

      timestamps()
    end

    create unique_index(:players, [:name])
  end
end

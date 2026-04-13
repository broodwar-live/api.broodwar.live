defmodule Broodwar.Repo.Migrations.CreateTournaments do
  use Ecto.Migration

  def change do
    create table(:tournaments) do
      add :name, :string, null: false
      add :short_name, :string
      add :type, :string
      add :year, :integer
      add :season, :integer

      timestamps()
    end
  end
end

defmodule Broodwar.Repo.Migrations.AddLiquipediaFieldsToTournaments do
  use Ecto.Migration

  def change do
    alter table(:tournaments) do
      add :liquipedia_page, :string
      add :liquipedia_data, :map, default: %{}
    end

    create index(:tournaments, [:short_name, :season], unique: true)
  end
end

defmodule Broodwar.Repo.Migrations.AddPlayerProfileFields do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :real_name, :string
      add :real_name_ko, :string
      add :birth_date, :string
      add :team, :string
      add :status, :string, default: "active"
      add :image_url, :string
      add :liquipedia_page, :string
      add :liquipedia_data, :map, default: %{}
    end
  end
end

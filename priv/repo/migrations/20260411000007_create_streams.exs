defmodule Broodwar.Repo.Migrations.CreateStreams do
  use Ecto.Migration

  def change do
    create table(:streams) do
      add :channel_id, :string, null: false
      add :platform, :string, null: false
      add :player_id, references(:players, on_delete: :nilify_all)
      add :title, :string
      add :is_live, :boolean, default: false
      add :viewer_count, :integer, default: 0
      add :last_seen_at, :utc_datetime

      timestamps()
    end

    create unique_index(:streams, [:platform, :channel_id])
    create index(:streams, [:player_id])
    create index(:streams, [:is_live])
  end
end

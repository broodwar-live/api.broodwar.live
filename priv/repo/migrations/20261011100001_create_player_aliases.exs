defmodule Broodwar.Repo.Migrations.CreatePlayerAliases do
  use Ecto.Migration

  # Names a player is known by (Liquipedia page, display name, IDs from the
  # infobox, in-game names confirmed by an admin). `normalized` is what
  # lookups compare against; see Broodwar.Players.normalize_alias/1.
  def up do
    create table(:player_aliases) do
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :alias, :string, null: false
      add :normalized, :string, null: false
      add :source, :string, null: false

      timestamps()
    end

    create unique_index(:player_aliases, [:player_id, :normalized])
    create index(:player_aliases, [:normalized])

    flush()
    backfill()
  end

  def down do
    drop table(:player_aliases)
  end

  # Seed aliases from existing player names, Liquipedia pages and the
  # `aliases` JSON array.
  defp backfill do
    %{rows: rows} = repo().query!("SELECT id, name, liquipedia_page, aliases FROM players")
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      for [id, name, page, aliases] <- rows,
          {value, source} <- [{name, "name"}, {page, "liquipedia"}] ++ json_aliases(aliases),
          is_binary(value),
          normalized = normalize(value),
          normalized != "",
          uniq: true do
        %{
          player_id: id,
          alias: value,
          normalized: normalized,
          source: source,
          inserted_at: now,
          updated_at: now
        }
      end

    entries
    |> Enum.uniq_by(&{&1.player_id, &1.normalized})
    |> Enum.chunk_every(500)
    |> Enum.each(&repo().insert_all("player_aliases", &1))
  end

  defp json_aliases(nil), do: []

  defp json_aliases(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> Enum.map(list, &{&1, "profile"})
      _ -> []
    end
  end

  # Must match Broodwar.Players.normalize_alias/1 at the time of writing.
  defp normalize(value) do
    value
    |> String.replace("_", " ")
    |> String.downcase()
    |> String.replace(~r/\s+/u, "")
  end
end

defmodule Broodwar.Ingestion.PlayerSync do
  @moduledoc """
  Syncs player profiles from Liquipedia.
  Fetches player page, extracts infobox data, downloads image, upserts into DB.
  """

  alias Broodwar.Ingestion.Liquipedia
  alias Broodwar.Repo
  alias Broodwar.Players.Player

  import Ecto.Query
  require Logger

  @notable_players [
    # Active Korean pros (ASL regulars)
    {"Flash", "Flash", "T"},
    {"Rain", "Rain", "P"},
    {"Snow", "SnOw", "P"},
    {"Soulkey", "Soulkey", "Z"},
    {"Sharp", "Sharp", "T"},
    {"Mini", "Mini", "P"},
    {"Last", "Last", "T"},
    {"hero", "Hero", "Z"},
    {"Best", "Best", "P"},
    {"Light", "Light", "T"},
    {"Soma", "Soma", "Z"},
    {"Mind", "Mind", "T"},
    {"Rush", "Rush", "Z"},
    {"JyJ", "JyJ", "T"},
    {"RoyaL", "RoyaL", "Z"},
    {"ZerO", "ZerO", "Z"},
    {"Larva", "Larva", "Z"},
    {"Action", "Action", "T"},
    {"Mong", "Mong", "T"},
    {"Shuttle", "Shuttle", "P"},
    {"BarrackS", "BarrackS", "T"},
    {"Sea", "Sea", "T"},
    {"Killer", "Killer", "Z"},
    {"Shine", "Shine", "Z"},
    {"TY", "TY", "T"},
    {"sSak", "SSak", "P"},
    {"TaeNgGu", "TaeNgGu", "T"},
    {"ZeLoT", "ZeLoT", "P"},
    {"Speed", "Speed", "Z"},
    {"beast", "Beast", "Z"},
    {"cRoSs", "CRoSs", "Z"},
    {"Hawk", "Hawk", "T"},
    {"DragOn", "DragOn", "T"},

    # Legends / retired Korean pros
    {"Bisu", "Bisu", "P"},
    {"Jaedong", "Jaedong", "Z"},
    {"Stork", "Stork", "P"},
    {"EffOrt", "EffOrt", "Z"},
    {"Calm", "Calm", "Z"},
    {"BoxeR", "BoxeR", "T"},
    {"NaDa", "NaDa", "T"},
    {"iloveoov", "Iloveoov", "T"},
    {"July", "July", "Z"},
    {"Savior", "Savior", "Z"},
    {"Fantasy", "Fantasy", "T"},
    {"Jangbi", "Jangbi", "P"},
    {"Yellow", "Yellow", "Z"},
    {"Reach", "Reach", "P"},
    {"firebathero", "Firebathero", "T"},
    {"GGPlay", "GGPlay", "P"},
    {"Iris", "Iris", "P"},
    {"Much", "Much", "T"},
    {"Guemchi", "Guemchi", "T"},

    # International BSL players
    {"Dewalt", "Dewalt", "T"},
    {"Bonyth", "Bonyth", "P"},
    {"Sziky", "Sziky", "P"},
    {"Scan", "Scan", "T"},
    {"Trutacz", "TrutaCz", "Z"},
    {"TerrOr", "TerrOr", "T"},
    {"Mihu", "Mihu", "Z"},
    {"eOnzErG", "EOnzErG", "Z"},
    {"Dandy", "Dandy", "P"},
    {"g0rynich", "G0rynich", "T"},
    {"BoA", "BoA", "Z"},
    {"Zhanhun", "Zhanhun", "T"},
    {"Dewalt", "Dewalt", "T"}
  ]

  @doc """
  Syncs all notable players from Liquipedia.
  Fetches profile data and images for each player.
  """
  def sync_all do
    @notable_players
    |> Enum.uniq_by(fn {name, _, _} -> name end)
    |> Enum.each(fn {name, page, race} ->
      sync_player(name, page, race)
    end)
  end

  @doc """
  Syncs a single player from Liquipedia.
  """
  def sync_player(name, page, default_race) do
    Logger.info("[PlayerSync] #{name} (#{page})")

    case Liquipedia.get_page(page) do
      {:ok, wikitext} ->
        fields = parse_player_infobox(wikitext)
        image_filename = extract_image(wikitext)
        team_history = extract_team_history(wikitext)

        # Extract aliases from infobox (|id2=, |id3=, etc.)
        aliases =
          1..5
          |> Enum.map(fn i -> fields["id#{i}"] end)
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&(&1 == ""))

        attrs = %{
          name: name,
          race: map_race(fields["race"] || default_race),
          real_name: fields["name"],
          real_name_ko: fields["romanized_name"] || fields["hangul"],
          aliases: aliases,
          birth_date: fields["birth_date"],
          country: map_country(fields["country"]),
          team: fields["team"],
          status: map_status(fields["status"]),
          liquipedia_page: page,
          liquipedia_data: Map.put(fields, "team_history", team_history)
        }

        # Upsert player
        player =
          case Repo.one(from p in Player, where: p.name == ^name) do
            nil ->
              %Player{}
              |> Player.changeset(attrs)
              |> Repo.insert!()

            existing ->
              # Only update fields that are nil or empty in existing record
              update_attrs =
                attrs
                |> Enum.reject(fn {k, v} -> is_nil(v) or v == "" or (k in [:name, :rating] and not is_nil(Map.get(existing, k))) end)
                |> Enum.into(%{})

              existing
              |> Player.changeset(update_attrs)
              |> Repo.update!()
          end

        # Download image if needed
        if !player.image_url && image_filename do
          download_player_image(player, image_filename)
        end

        Logger.info("[PlayerSync] #{name}: #{attrs.real_name || "?"} (#{attrs.race})")

      {:error, reason} ->
        Logger.warning("[PlayerSync] #{name}: page not found (#{inspect(reason)})")
    end
  end

  @doc """
  Extract team history from a player's wikitext.
  Returns a list of %{team, start_date, end_date, role}.
  """
  def extract_team_history(wikitext) do
    # Match {{TeamHistory|...}} blocks or team entries in infobox
    Regex.scan(~r/\{\{TeamCard\|([^}]+)\}\}/, wikitext)
    |> Enum.map(fn [_, content] ->
      fields =
        content
        |> String.split("|")
        |> Enum.reduce(%{}, fn part, acc ->
          case String.split(part, "=", parts: 2) do
            [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
            _ -> acc
          end
        end)

      %{
        team: fields["team"] || content |> String.split("|") |> List.first() |> String.trim(),
        start_date: fields["sdate"],
        end_date: fields["edate"],
        role: fields["role"]
      }
    end)
  end

  defp parse_player_infobox(wikitext) do
    wikitext
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/^\s*\|([^=]+)=(.+)$/, String.trim(line)) do
        [_, key, value] ->
          Map.put(acc, String.trim(key), String.trim(value))

        _ ->
          acc
      end
    end)
  end

  defp extract_image(wikitext) do
    case Regex.run(~r/\|image\s*=\s*(.+)$/m, wikitext) do
      [_, filename] -> String.trim(filename)
      _ -> nil
    end
  end

  defp download_player_image(player, filename) do
    slug = player.name |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "-")
    ext = Path.extname(filename) |> String.downcase()
    dest = "priv/static/images/players/#{slug}#{ext}"

    with {:ok, url} <- Liquipedia.get_image_url(filename),
         {:ok, _} <- Liquipedia.download_image(url, dest) do
      Repo.update!(Player.changeset(player, %{image_url: "/images/players/#{slug}#{ext}"}))
      Logger.info("[PlayerSync] Downloaded image for #{player.name}")
    else
      {:error, reason} ->
        Logger.warning("[PlayerSync] Image failed for #{player.name}: #{inspect(reason)}")
    end
  end

  defp map_race(race) when is_binary(race) do
    race = String.downcase(race)
    cond do
      String.contains?(race, "terran") -> "T"
      String.contains?(race, "protoss") -> "P"
      String.contains?(race, "zerg") -> "Z"
      race in ~w(t p z r) -> String.upcase(race)
      true -> nil
    end
  end

  defp map_race(_), do: nil

  defp map_country(nil), do: nil

  defp map_country(country) do
    country = String.downcase(country)
    cond do
      String.contains?(country, "korea") -> "KR"
      String.contains?(country, "poland") -> "PL"
      String.contains?(country, "canada") -> "CA"
      String.contains?(country, "russia") -> "RU"
      String.contains?(country, "ukraine") -> "UA"
      String.contains?(country, "czech") -> "CZ"
      String.contains?(country, "hungary") -> "HU"
      String.contains?(country, "germany") -> "DE"
      String.contains?(country, "china") -> "CN"
      String.contains?(country, "united states") -> "US"
      true -> country |> String.upcase() |> String.slice(0, 2)
    end
  end

  defp map_status(nil), do: "active"

  defp map_status(status) do
    status = String.downcase(status)
    cond do
      String.contains?(status, "retired") -> "inactive"
      String.contains?(status, "inactive") -> "inactive"
      String.contains?(status, "active") -> "active"
      true -> "active"
    end
  end
end

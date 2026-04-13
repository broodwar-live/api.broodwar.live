defmodule Broodwar.Ingestion.TournamentSync do
  @moduledoc """
  Oban worker that syncs tournament data from Liquipedia.

  Fetches tournament pages via the MediaWiki API, parses Infobox league
  templates, and upserts into the local database.

  Usage:
    # Sync a single tournament page
    %{page: "AfreecaTV/StarCraft_League_Remastered/21"}
    |> Broodwar.Ingestion.TournamentSync.new()
    |> Oban.insert()

    # Sync all major tournament series
    Broodwar.Ingestion.TournamentSync.sync_all_series()
  """

  use Oban.Worker, queue: :ingestion, max_attempts: 3

  alias Broodwar.Ingestion.Liquipedia
  alias Broodwar.Repo
  alias Broodwar.Tournaments.Tournament

  import Ecto.Query

  require Logger

  @major_series [
    %{
      prefix: "AfreecaTV/StarCraft_League_Remastered",
      short_name: "ASL",
      type: "premier",
      seasons: 1..21
    },
    %{
      prefix: "Bombastic_StarLeague",
      short_name: "BSL",
      type: "major",
      seasons: 1..20
    },
    %{
      prefix: "Korean_StarCraft_League",
      short_name: "KSL",
      type: "premier",
      seasons: 1..3
    }
  ]

  @doc """
  Enqueues sync jobs for all major tournament series.
  """
  def sync_all_series do
    @major_series
    |> Enum.flat_map(fn series ->
      Enum.map(series.seasons, fn season ->
        page = "#{series.prefix}/#{season}"

        %{page: page, short_name: series.short_name, type: series.type, season: season}
        |> new()
      end)
    end)
    |> Oban.insert_all()
  end

  @doc """
  Enqueues a sync job for a single series (all seasons).
  """
  def sync_series(series_key) do
    case Enum.find(@major_series, fn s -> s.short_name == series_key end) do
      nil ->
        {:error, :unknown_series}

      series ->
        jobs =
          Enum.map(series.seasons, fn season ->
            %{page: "#{series.prefix}/#{season}", short_name: series.short_name, type: series.type, season: season}
            |> new()
          end)

        Oban.insert_all(jobs)
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"page" => page} = args}) do
    short_name = args["short_name"]
    season = args["season"]
    type = args["type"]

    Logger.info("[TournamentSync] Fetching #{page}")

    case Liquipedia.fetch_tournament(page) do
      {:ok, data} when map_size(data) > 0 ->
        upsert_tournament(data, short_name, season, type, page)
        Logger.info("[TournamentSync] Synced #{page}: #{data[:first_place] || "in progress"}")
        :ok

      {:ok, _empty} ->
        Logger.warning("[TournamentSync] No infobox found for #{page}")
        :ok

      {:error, :page_not_found} ->
        Logger.warning("[TournamentSync] Page not found: #{page}")
        :ok

      {:error, reason} ->
        Logger.error("[TournamentSync] Failed to fetch #{page}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp upsert_tournament(data, short_name, season, type, page) do
    name = data[:name] || "#{short_name} Season #{season}"

    attrs = %{
      name: name,
      short_name: short_name || data[:abbreviation],
      type: type || data[:tier],
      year: parse_year(data[:start_date]),
      season: season || parse_int(data[:edition]),
      liquipedia_page: page,
      liquipedia_data: %{
        prize_pool: data[:prize_pool],
        prize_pool_usd: data[:prize_pool_usd],
        start_date: data[:start_date],
        end_date: data[:end_date],
        format: data[:format],
        organizer: data[:organizer],
        country: data[:country],
        player_count: data[:player_count],
        terran_count: data[:terran_count],
        protoss_count: data[:protoss_count],
        zerg_count: data[:zerg_count],
        maps: data[:maps],
        first_place: data[:first_place],
        first_place_race: data[:first_place_race],
        second_place: data[:second_place],
        second_place_race: data[:second_place_race],
        third_place: data[:third_place],
        fourth_place: data[:fourth_place],
        participants: data[:participants],
        matches: data[:matches]
      }
    }

    # Upsert by short_name + season
    case Repo.one(from t in Tournament, where: t.short_name == ^attrs.short_name and t.season == ^attrs.season) do
      nil ->
        %Tournament{}
        |> Tournament.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Tournament.changeset(attrs)
        |> Repo.update()
    end
  end

  defp parse_year(nil), do: nil

  defp parse_year(date_str) do
    case Regex.run(~r/(\d{4})/, date_str) do
      [_, year] -> String.to_integer(year)
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp parse_int(n) when is_integer(n), do: n
end

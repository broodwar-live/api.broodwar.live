defmodule Broodwar.Ingestion.MatchSync do
  @moduledoc """
  Oban worker: ingest series/games from Liquipedia tournament pages, then
  recompute ratings once for the batch.

      %{"pages" => ["AfreecaTV/StarCraft League Remastered/17"]}
      |> Broodwar.Ingestion.MatchSync.new()
      |> Oban.insert()

  Pages are fetched one after another through the shared Liquipedia
  throttle. Afterwards, players still missing a race get it from their
  Liquipedia player pages (one request per 50 players). A 403/429 from Liquipedia cancels the job (no retries): it
  means we are being rate limited and must back off.
  """
  use Oban.Worker,
    queue: :ingestion,
    max_attempts: 3,
    unique: [period: 3600, fields: [:args]]

  require Logger

  alias Broodwar.Ingestion.MatchIngest
  alias Broodwar.Ratings

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"pages" => pages}}) when is_list(pages) do
    case run(pages) do
      {:ok, _summaries} -> :ok
      {:error, {:rate_limited, _} = reason} -> {:cancel, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"page" => page}} = job),
    do: perform(%{job | args: %{"pages" => [page]}})

  @doc """
  Ingests `pages` in order and recomputes ratings if anything was written.
  Stops at the first fetch error.
  """
  @spec run([String.t()]) :: {:ok, [MatchIngest.summary()]} | {:error, term()}
  def run(pages) do
    result =
      Enum.reduce_while(pages, {:ok, []}, fn page, {:ok, acc} ->
        case MatchIngest.ingest_page(page) do
          {:ok, summary} ->
            log(summary)
            {:cont, {:ok, [summary | acc]}}

          {:error, reason} ->
            Logger.error("[MatchSync] #{page}: #{inspect(reason)}")
            {:halt, {:error, reason, acc}}
        end
      end)

    {status, summaries} =
      case result do
        {:ok, acc} -> {:ok, Enum.reverse(acc)}
        {:error, reason, acc} -> {{:error, reason}, Enum.reverse(acc)}
      end

    if summaries != [] do
      fill_races()
      Ratings.recompute()
    end

    case status do
      :ok -> {:ok, summaries}
      error -> error
    end
  end

  # Best effort: a failure here leaves races empty but keeps the results.
  defp fill_races do
    case MatchIngest.fill_missing_races() do
      {:ok, n} -> Logger.info("[MatchSync] races looked up for #{n} players")
      {:error, reason} -> Logger.warning("[MatchSync] race lookup failed: #{inspect(reason)}")
    end
  end

  defp log(s) do
    Logger.info(
      "[MatchSync] #{s.page} rev #{s.revision_id}: #{s.upserted}/#{s.matches_found} series, " <>
        "#{s.games} games, #{length(s.failed)} failed, #{length(s.skipped)} skipped"
    )
  end
end

defmodule Mix.Tasks.Broodwar.IngestMatches do
  @moduledoc """
  Ingest series and games from Liquipedia tournament pages, then recompute
  ratings.

  ## Usage

      mix broodwar.ingest_matches --tournament "AfreecaTV/StarCraft League Remastered/17"
      mix broodwar.ingest_matches --tournament "Page A" --tournament "Page B"
      mix broodwar.ingest_matches --tournament "Page A" --enqueue   # via Oban

  Runs synchronously by default and prints a per-page summary. Requests go
  through the shared Liquipedia throttle (1 request / 2 s). Do not use this
  to bulk-scrape; see the README for backfill guidance.
  """
  use Mix.Task

  alias Broodwar.Ingestion.MatchSync

  @shortdoc "Ingest matches from Liquipedia tournament pages"

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [tournament: :keep, enqueue: :boolean])

    pages = Keyword.get_values(opts, :tournament)

    cond do
      pages == [] ->
        Mix.raise(~s(Usage: mix broodwar.ingest_matches --tournament "Page_Title"))

      opts[:enqueue] ->
        Mix.Task.run("app.start")
        Oban.insert!(MatchSync.new(%{"pages" => pages}))
        Mix.shell().info("Enqueued ingestion of #{length(pages)} page(s).")

      true ->
        Mix.Task.run("app.start")
        report(MatchSync.run(pages))
    end
  end

  defp report({:ok, summaries}) do
    Enum.each(summaries, &print/1)
    Mix.shell().info("Ratings recomputed.")
  end

  defp report({:error, reason}), do: Mix.raise("Ingestion stopped: #{inspect(reason)}")

  defp print(s) do
    Mix.shell().info("""
    #{s.page} (revision #{s.revision_id})
      series found: #{s.matches_found}, upserted: #{s.upserted}, walkovers: #{s.walkovers}
      games: #{s.games}, stale series deleted: #{s.deleted}
      skipped: #{length(s.skipped)}, failed: #{length(s.failed)}\
    """)

    Enum.each(s.skipped, &Mix.shell().info("    skipped #{&1.key}: #{&1.reason}"))
    Enum.each(s.failed, &Mix.shell().error("    failed #{&1.key}: #{&1.reason}"))

    if s.transclusions != [] do
      Mix.shell().info("  transcluded pages (not ingested): #{Enum.join(s.transclusions, ", ")}")
    end
  end
end

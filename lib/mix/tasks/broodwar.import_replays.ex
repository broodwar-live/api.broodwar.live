defmodule Mix.Tasks.Broodwar.ImportReplays do
  @moduledoc """
  Batch import replay files from a directory.

  ## Usage

      mix broodwar.import_replays /path/to/replays
      mix broodwar.import_replays /path/to/replays --no-recursive

  Finds all `.rep` files and enqueues a ReplayImport Oban job.
  Progress is logged as the job runs in the :ingestion queue.
  Idempotent — already-imported replays (by SHA-256 hash) are skipped.
  """
  use Mix.Task

  @shortdoc "Import replay files from a directory"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _} = OptionParser.parse(args, switches: [recursive: :boolean])
    recursive = Keyword.get(opts, :recursive, true)

    case positional do
      [directory | _] ->
        if File.dir?(directory) do
          Mix.shell().info("Enqueuing replay import for: #{directory}")

          %{"directory" => directory, "recursive" => recursive}
          |> Broodwar.Ingestion.ReplayImport.new()
          |> Oban.insert!()

          Mix.shell().info("Import job enqueued. Watch logs for progress.")
        else
          Mix.shell().error("Directory not found: #{directory}")
        end

      [] ->
        Mix.shell().error("Usage: mix broodwar.import_replays <directory>")
    end
  end
end

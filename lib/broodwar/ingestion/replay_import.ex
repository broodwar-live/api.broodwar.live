defmodule Broodwar.Ingestion.ReplayImport do
  @moduledoc """
  Oban worker for batch importing replay files from a directory.

  Finds all `.rep` files in the given directory, parses each one, and
  persists to the database. Idempotent — skips files already imported
  (matched by SHA-256 hash).

  ## Usage

      Broodwar.Ingestion.ReplayImport.new(%{"directory" => "/path/to/replays"})
      |> Oban.insert()

  ## Options

  - `directory` (required) — path to scan for `.rep` files
  - `recursive` (optional, default true) — scan subdirectories
  """
  use Oban.Worker,
    queue: :ingestion,
    max_attempts: 1,
    unique: [period: 3600, fields: [:args]]

  require Logger
  alias Broodwar.Replays

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"directory" => directory} = args}) do
    recursive = Map.get(args, "recursive", true)

    files = find_rep_files(directory, recursive)
    total = length(files)
    Logger.info("[ReplayImport] Found #{total} .rep files in #{directory}")

    results =
      files
      |> Enum.with_index(1)
      |> Enum.map(fn {path, index} ->
        if rem(index, 10) == 0 do
          Logger.info("[ReplayImport] Progress: #{index}/#{total}")
        end

        case File.read(path) do
          {:ok, data} ->
            case Replays.parse_and_save(data, file_path: path) do
              {:ok, replay} -> {:ok, replay.id}
              {:error, reason} -> {:error, path, reason}
            end

          {:error, reason} ->
            {:error, path, reason}
        end
      end)

    imported = Enum.count(results, &match?({:ok, _}, &1))
    errors = Enum.count(results, &match?({:error, _, _}, &1))

    Logger.info(
      "[ReplayImport] Complete: #{imported} imported, #{errors} errors, #{total} total"
    )

    :ok
  end

  def perform(%Oban.Job{}) do
    {:error, "Missing required \"directory\" argument"}
  end

  defp find_rep_files(directory, recursive) do
    pattern = if recursive, do: "**/*.rep", else: "*.rep"

    Path.join(directory, pattern)
    |> Path.wildcard()
    |> Enum.sort()
  end
end

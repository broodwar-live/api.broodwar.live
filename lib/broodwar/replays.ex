defmodule Broodwar.Replays do
  @moduledoc """
  Context for replay parsing, storage, and retrieval.

  Replays enter the system through two kinds of paths:

    * **Untrusted** (anonymous `POST /api/replays`): the replay is parsed and
      stored with its derived data only. It is never linked to player
      records and never affects ratings.
    * **Trusted** (operator batch import, admin API): after storing, the
      replay may be linked to players and rated via `link_and_rate/1`.
  """
  import Ecto.Query

  alias Broodwar.Elo
  alias Broodwar.Pagination
  alias Broodwar.Players.Player
  alias Broodwar.Replays.Replay
  alias Broodwar.Repo

  # 5 MiB. Real 1v1 replays are typically 50–300 KB.
  @max_size 5 * 1024 * 1024
  @valid_races ~w(T P Z R)

  @doc "Maximum accepted replay size in bytes."
  def max_size, do: @max_size

  @doc """
  Lists replays newest first, paginated in the database. `parsed_data` is
  not loaded (it can be hundreds of KB per replay).
  """
  def list_replays(opts \\ []) do
    Replay
    |> select([r], struct(r, ^Replay.summary_fields()))
    |> order_by(desc: :inserted_at, desc: :id)
    |> Pagination.paginate(opts)
    |> preload([:player_a, :player_b, :map])
    |> Repo.all()
  end

  def get_replay!(id) do
    Replay
    |> preload([:player_a, :player_b, :map, :match])
    |> Repo.get!(id)
  end

  @doc """
  Cheap structural check before handing bytes to the NIF.

  Every `.rep` (1.16 through Remastered) starts with a section whose first
  4-byte chunk is stored uncompressed and holds the replay magic: bytes
  12..15 are `"reRS"` (legacy) or `"seRS"` (1.18+).
  """
  @spec validate_format(binary()) :: :ok | {:error, :too_large | :invalid_format}
  def validate_format(data) when byte_size(data) > @max_size, do: {:error, :too_large}

  def validate_format(
        <<_checksum::binary-4, _chunks::binary-4, _len::binary-4, magic::binary-4, _rest::binary>>
      )
      when magic in ["reRS", "seRS"],
      do: :ok

  def validate_format(_data), do: {:error, :invalid_format}

  @doc """
  Validate, parse and persist raw `.rep` data.

  Options:
    * `:source` — `"upload"` (default), `"import"` or `"admin"`
    * `:file_path` — original path for batch imports

  Returns `{:ok, replay, :created | :existing}` or `{:error, reason}`.
  Never links players or changes ratings; see `link_and_rate/1`.
  """
  def parse_and_save(data, opts \\ []) when is_binary(data) do
    with :ok <- validate_format(data),
         {:ok, parsed} <- parse_replay(data) do
      file_hash = :crypto.hash(:sha256, data) |> Base.hex_encode32(case: :lower, padding: false)

      case Repo.get_by(Replay, file_hash: file_hash) do
        nil -> insert_replay(file_hash, parsed, opts)
        existing -> {:ok, existing, :existing}
      end
    end
  end

  defp insert_replay(file_hash, parsed, opts) do
    attrs =
      parsed
      |> derived_attrs()
      |> Map.merge(%{
        file_hash: file_hash,
        file_path: opts[:file_path],
        source: opts[:source] || "upload",
        parsed_data: parsed
      })

    case Repo.insert(Replay.changeset(%Replay{}, attrs)) do
      {:ok, replay} ->
        Broodwar.Cache.invalidate_all()
        {:ok, replay, :created}

      {:error, changeset} ->
        # Lost a race with a concurrent upload of the same file.
        case Repo.get_by(Replay, file_hash: file_hash) do
          nil -> {:error, changeset}
          existing -> {:ok, existing, :existing}
        end
    end
  end

  @doc """
  Trusted-only: link a stored replay to existing player records by name and
  apply its result to Elo ratings. Idempotent — a replay is rated at most
  once (tracked via `rated_at`).
  """
  def link_and_rate(%Replay{rated_at: %DateTime{}} = replay), do: {:ok, replay}

  def link_and_rate(%Replay{} = replay) do
    Repo.transaction(fn ->
      # Rate first: Elo may create player records for unknown names, which
      # the link step below then picks up.
      with :ok <- apply_rating(replay),
           {:ok, replay} <- Repo.update(Replay.changeset(replay, link_attrs(replay))) do
        Broodwar.Cache.invalidate_all()
        replay
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp link_attrs(replay) do
    %{
      player_a_id: player_id_by_name(replay.player_a_name),
      player_b_id: player_id_by_name(replay.player_b_name),
      rated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  defp apply_rating(replay) do
    case Elo.update_from_replay(replay.parsed_data || %{}) do
      {:ok, _ratings} -> :ok
      # No decisive result (e.g. both left) — nothing to rate.
      {:error, reason} when reason in [:no_winner, :insufficient_data] -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Parse a replay from raw `.rep` file binary data (without persisting).
  """
  @spec parse_replay(binary()) :: {:ok, map()} | {:error, String.t()}
  def parse_replay(data) when is_binary(data) do
    BroodwarNif.ReplayParser.parse(data)
  end

  @doc """
  Parse a replay file from disk.
  """
  @spec parse_replay_file(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_replay_file(path) do
    case File.read(path) do
      {:ok, data} -> parse_replay(data)
      {:error, reason} -> {:error, "failed to read file: #{reason}"}
    end
  end

  @doc """
  Compare build orders between two replay binaries.
  """
  @spec compare_builds(binary(), binary(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def compare_builds(data_a, data_b, player_index \\ 0) do
    BroodwarNif.ReplayParser.compare_builds(data_a, data_b, player_index)
  end

  @doc """
  Normalize a player name (strip clan tags, whitespace).
  """
  @spec normalize_player_name(String.t()) :: map()
  def normalize_player_name(name) do
    BroodwarNif.ReplayParser.normalize_name(name)
  end

  # -- Private helpers --

  defp derived_attrs(parsed) do
    header = parsed["header"] || %{}
    metadata = parsed["metadata"] || %{}
    classifications = parsed["classifications"] || []
    players = header["players"] || []

    %{
      duration: trunc(header["duration_secs"] || 0),
      race_a: player_race_code(players, 0),
      race_b: player_race_code(players, 1),
      player_a_name: player_name(players, 0),
      player_b_name: player_name(players, 1),
      winner_name: winner_name(metadata["result"]),
      matchup: get_in(metadata, ["matchup", "code"]),
      map_name_normalized: metadata["map_name"],
      classification_a: opening_tag(classifications, 0),
      classification_b: opening_tag(classifications, 1),
      map_id: map_id_by_name(header["map_name"])
    }
  end

  defp player_race_code(players, index) do
    case Enum.at(players, index) do
      %{"race_code" => code} when code in @valid_races -> code
      _ -> nil
    end
  end

  defp player_name(players, index) do
    case Enum.at(players, index) do
      %{"name" => name} when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  # result is a map for a decided game, or the string "unknown".
  defp winner_name(%{"player_name" => name}), do: name
  defp winner_name(_), do: nil

  defp opening_tag(classifications, index) do
    case Enum.at(classifications, index) do
      %{"tag" => tag} -> tag
      _ -> nil
    end
  end

  defp map_id_by_name(nil), do: nil

  defp map_id_by_name(map_name) do
    Repo.one(from(m in Broodwar.Maps.Map, where: m.name == ^map_name, select: m.id, limit: 1))
  end

  defp player_id_by_name(nil), do: nil

  defp player_id_by_name(name) do
    Repo.one(from(p in Player, where: p.name == ^name, select: p.id, limit: 1))
  end
end

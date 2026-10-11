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

  alias Broodwar.Matches.Game
  alias Broodwar.Pagination
  alias Broodwar.Players.Identity
  alias Broodwar.Players.Player
  alias Broodwar.Ratings
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
  Trusted-only (admin API, operator import): link a stored replay to
  existing players and record its result as a rated game.

  In-game names are resolved through player aliases
  (`Broodwar.Players.Identity.resolve_in_game/1`); players are never
  created from replay names. `overrides` may pin a slot to a player id
  (`"player_a_id"` / `"player_b_id"`), which also records the in-game name
  as an alias of that player for next time.

  Returns `{:error, {:unresolved_players, details}}` when a name is unknown
  or matches several players, with the candidates in `details`.

  Idempotent: a replay is linked at most once (`rated_at`). Ratings are
  recomputed afterwards unless `recompute: false` is given (batch imports
  recompute once at the end).
  """
  def link_and_rate(replay, overrides \\ %{}, opts \\ [])

  def link_and_rate(%Replay{rated_at: %DateTime{}} = replay, _overrides, _opts),
    do: {:ok, replay}

  def link_and_rate(%Replay{} = replay, overrides, opts) do
    slots = [
      {"a", replay.player_a_name, overrides["player_a_id"]},
      {"b", replay.player_b_name, overrides["player_b_id"]}
    ]

    resolved = Enum.map(slots, &resolve_slot/1)

    case Enum.filter(resolved, &match?({:error, _}, &1)) do
      [] ->
        [{:ok, pa, pin_a}, {:ok, pb, pin_b}] = resolved
        link(replay, {pa, pin_a}, {pb, pin_b}, opts)

      errors ->
        {:error, {:unresolved_players, Enum.map(errors, &elem(&1, 1))}}
    end
  end

  defp link(_replay, {%Player{id: id}, _}, {%Player{id: id}, _}, _opts),
    do: {:error, "Both replay slots resolve to the same player"}

  defp link(replay, {pa, pin_a}, {pb, pin_b}, opts) do
    result =
      Repo.transaction(fn ->
        if pin_a, do: Identity.add_alias(pa, replay.player_a_name, "admin")
        if pin_b, do: Identity.add_alias(pb, replay.player_b_name, "admin")

        attrs = %{
          player_a_id: pa.id,
          player_b_id: pb.id,
          rated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        with {:ok, replay} <- Repo.update(Replay.changeset(replay, attrs)),
             :ok <- insert_game(replay, pa, pb) do
          replay
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    with {:ok, replay} <- result do
      if Keyword.get(opts, :recompute, true), do: Ratings.recompute()
      Broodwar.Cache.invalidate_all()
      {:ok, replay}
    end
  end

  defp resolve_slot({slot, name, nil}) do
    variants = [name, name && normalize_player_name(name)["normalized"]]

    case Identity.resolve_in_game(variants) do
      {:ok, player} -> {:ok, player, false}
      {:error, {kind, candidates}} -> {:error, unresolved(slot, name, kind, candidates)}
    end
  end

  defp resolve_slot({slot, name, id}) do
    case Repo.get(Player, parse_id(id)) do
      %Player{} = player -> {:ok, player, true}
      nil -> {:error, unresolved(slot, name, :unknown_player_id, [])}
    end
  end

  defp unresolved(slot, name, kind, candidates) do
    %{slot: slot, name: name, reason: kind, candidates: candidates}
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp parse_id(_), do: 0

  # A game is recorded only for a decided 1v1 result.
  defp insert_game(%Replay{winner_name: nil}, _pa, _pb), do: :ok

  defp insert_game(replay, pa, pb) do
    winner =
      cond do
        replay.winner_name == replay.player_a_name -> pa
        replay.winner_name == replay.player_b_name -> pb
        true -> nil
      end

    if winner do
      %Game{}
      |> Game.changeset(%{
        replay_id: replay.id,
        map_id: replay.map_id,
        map_name: replay.map_name_normalized,
        player_a_id: pa.id,
        player_b_id: pb.id,
        winner_id: winner.id,
        race_a: replay.race_a,
        race_b: replay.race_b,
        played_at: replay_played_at(replay),
        source: "replay"
      })
      |> Repo.insert()
      |> case do
        {:ok, _game} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    else
      :ok
    end
  end

  defp replay_played_at(%Replay{played_at: %DateTime{} = at}), do: at

  defp replay_played_at(replay) do
    case get_in(replay.parsed_data || %{}, ["header", "start_time"]) do
      ts when is_integer(ts) and ts > 0 -> DateTime.from_unix!(ts)
      _ -> replay.inserted_at && DateTime.from_naive!(replay.inserted_at, "Etc/UTC")
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
end

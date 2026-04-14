defmodule Broodwar.Replays do
  @moduledoc """
  Context for replay parsing, storage, and retrieval.
  """
  import Ecto.Query
  alias Broodwar.Repo
  alias Broodwar.Replays.Replay

  def list_replays do
    Replay
    |> order_by(desc: :inserted_at)
    |> preload([:player_a, :player_b, :map, :match])
    |> Repo.all()
  end

  def get_replay!(id) do
    Replay
    |> preload([:player_a, :player_b, :map, :match])
    |> Repo.get!(id)
  end

  @doc """
  Parse raw `.rep` binary data and persist the replay to the database.
  Returns `{:ok, %Replay{}}` or `{:error, reason}`.
  """
  def parse_and_save(data, opts \\ []) when is_binary(data) do
    with {:ok, parsed} <- parse_replay(data) do
      file_hash = :crypto.hash(:sha256, data) |> Base.hex_encode32(case: :lower, padding: false)

      metadata = parsed["metadata"] || %{}
      classifications = parsed["classifications"] || []

      attrs =
        %{
          file_hash: file_hash,
          file_path: opts[:file_path],
          duration: trunc(parsed["header"]["duration_secs"]),
          parsed_data: parsed,
          race_a: player_race_code(parsed, 0),
          race_b: player_race_code(parsed, 1),
          matchup: get_in(metadata, ["matchup", "code"]),
          map_name_normalized: metadata["map_name"],
          winner_id: winner_player_id(metadata),
          classification_a: opening_tag(classifications, 0),
          classification_b: opening_tag(classifications, 1)
        }
        |> maybe_put_map_id(parsed["header"]["map_name"])
        |> maybe_put_player_ids(parsed["header"]["players"])

      case Repo.get_by(Replay, file_hash: file_hash) do
        nil ->
          case Repo.insert(Replay.changeset(%Replay{}, attrs)) do
            {:ok, replay} ->
              # Update Elo ratings from this replay's result.
              Broodwar.Elo.update_from_replay(parsed)
              # Invalidate cached stats.
              Broodwar.Cache.invalidate_all()
              {:ok, replay}

            error ->
              error
          end

        existing ->
          {:ok, existing}
      end
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

  defp player_race_code(parsed, index) do
    players = parsed["header"]["players"] || []

    case Enum.at(players, index) do
      %{"race_code" => code} -> code
      _ -> nil
    end
  end

  defp winner_player_id(%{"result" => %{"player_id" => id}}), do: id
  defp winner_player_id(_), do: nil

  defp opening_tag(classifications, index) do
    case Enum.at(classifications, index) do
      %{"tag" => tag} -> tag
      _ -> nil
    end
  end

  defp maybe_put_map_id(attrs, nil), do: attrs

  defp maybe_put_map_id(attrs, map_name) do
    alias Broodwar.Maps.Map

    case Repo.one(from(m in Map, where: m.name == ^map_name, limit: 1)) do
      %{id: id} -> Elixir.Map.put(attrs, :map_id, id)
      nil -> attrs
    end
  end

  defp maybe_put_player_ids(attrs, nil), do: attrs
  defp maybe_put_player_ids(attrs, []), do: attrs

  defp maybe_put_player_ids(attrs, players) do
    attrs
    |> maybe_match_player(:player_a_id, Enum.at(players, 0))
    |> maybe_match_player(:player_b_id, Enum.at(players, 1))
  end

  defp maybe_match_player(attrs, _key, nil), do: attrs

  defp maybe_match_player(attrs, key, %{"name" => name}) do
    alias Broodwar.Players.Player

    case Broodwar.Repo.one(from(p in Player, where: p.name == ^name, limit: 1)) do
      %{id: id} -> Elixir.Map.put(attrs, key, id)
      nil -> attrs
    end
  end

  defp maybe_match_player(attrs, _key, _), do: attrs
end

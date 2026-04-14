defmodule BroodwarNif.ReplayParser do
  @moduledoc """
  Rust NIF bindings for the StarCraft: Brood War replay parser.

  Provides 4 NIF functions:
  - `parse/1` — full replay parse with metadata, classification, phases, skill
  - `compare_builds/3` — build order similarity between two replays
  - `normalize_name/1` — normalize a player name (strip clan tags)

  Do not call these functions directly — use context modules instead.
  """
  use Rustler, otp_app: :broodwar, crate: "replay_parser"

  @doc """
  Parse a replay from raw binary data.

  Returns `{:ok, replay_map}` or `{:error, reason}`.
  The replay_map includes: header, build_order, player_apm, timeline,
  apm_timeline, metadata, classifications, phases, skill_profiles.
  """
  @spec parse(binary()) :: {:ok, map()} | {:error, String.t()}
  def parse(_data), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Compare build orders from two replays.

  `player_index` is 0 or 1 (first or second player).
  Returns `{:ok, %{edit_similarity, lcs_similarity, len_a, len_b}}`.
  """
  @spec compare_builds(binary(), binary(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def compare_builds(_data_a, _data_b, _player_index),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Normalize a player name: strip clan tags, whitespace, special chars.

  Returns `%{original, normalized, clan_tag}`.
  """
  @spec normalize_name(String.t()) :: map()
  def normalize_name(_name), do: :erlang.nif_error(:nif_not_loaded)
end

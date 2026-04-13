defmodule BroodwarNif.ReplayParser do
  @moduledoc """
  Rust NIF bindings for the StarCraft: Brood War replay parser.

  Do not call these functions directly — use `Broodwar.Replays` instead.
  """
  use Rustler, otp_app: :broodwar, crate: "replay_parser"

  @doc """
  Parse a replay from raw binary data.

  Returns `{:ok, replay_map}` or `{:error, reason}`.
  """
  @spec parse(binary()) :: {:ok, map()} | {:error, String.t()}
  def parse(_data), do: :erlang.nif_error(:nif_not_loaded)
end

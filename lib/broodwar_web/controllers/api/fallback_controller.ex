defmodule BroodwarWeb.Api.FallbackController do
  @moduledoc """
  Translates `{:error, reason}` results from API actions into the standard
  `{"error": {"code", "message"}}` response shape.
  """
  use Phoenix.Controller, formats: [:json]

  alias BroodwarWeb.Api.JSON

  def call(conn, {:error, :not_found}) do
    error(conn, :not_found, "NOT_FOUND", "Resource not found")
  end

  def call(conn, {:error, :too_large}) do
    max_mb = div(Broodwar.Replays.max_size(), 1024 * 1024)
    error(conn, :request_entity_too_large, "TOO_LARGE", "Replay exceeds #{max_mb} MB")
  end

  def call(conn, {:error, :invalid_format}) do
    error(conn, :unprocessable_entity, "INVALID_REPLAY", "Not a StarCraft: Brood War replay")
  end

  def call(conn, {:error, {:unparseable, reason}}) do
    error(conn, :unprocessable_entity, "INVALID_REPLAY", "Could not parse replay: #{reason}")
  end

  def call(conn, {:error, {:unresolved_players, replay_id, details}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "UNRESOLVED_PLAYERS",
        message:
          "Replay player names could not be matched to exactly one known player. " <>
            "Retry POST /api/admin/replays/#{replay_id}/rate with player_a_id / player_b_id.",
        details: %{
          replay_id: replay_id,
          players:
            Enum.map(details, fn d ->
              %{
                slot: d.slot,
                name: d.name,
                reason: d.reason,
                candidates: Enum.map(d.candidates, &JSON.player_summary/1)
              }
            end)
        }
      }
    })
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "VALIDATION_ERROR", message: "Validation failed", details: errors}})
  end

  def call(conn, {:error, message}) when is_binary(message) do
    error(conn, :bad_request, "BAD_REQUEST", message)
  end

  def call(conn, {:error, reason}) do
    error(conn, :internal_server_error, "INTERNAL_ERROR", "Unexpected error: #{inspect(reason)}")
  end

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end
end

defmodule BroodwarWeb.Api.ReplayController do
  use BroodwarWeb, :controller

  alias Broodwar.Pagination
  alias Broodwar.Replays
  alias BroodwarWeb.Api.JSON

  action_fallback BroodwarWeb.Api.FallbackController

  def index(conn, params) do
    pagination_opts = [
      page: parse_int(params["page"], 1),
      per_page: parse_int(params["per_page"], 50)
    ]

    replays = Replays.list_replays(pagination_opts)

    json(conn, %{
      data: Enum.map(replays, &JSON.replay_summary/1),
      pagination: Pagination.pagination_meta(pagination_opts)
    })
  end

  def show(conn, %{"id" => id}) do
    replay = Replays.get_replay!(id)
    json(conn, %{data: JSON.replay(replay)})
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  @doc """
  POST /api/replays — anonymous upload. Stores the parsed replay only; it is
  never linked to players and never affects ratings.
  """
  def create(conn, params), do: upload(conn, params, "upload")

  @doc """
  POST /api/admin/replays — authenticated upload. Same as `create/2`, then
  links players and applies Elo.
  """
  def admin_create(conn, params) do
    with {:ok, conn, replay} <- do_upload(conn, params, "admin"),
         {:ok, replay} <- Replays.link_and_rate(replay) do
      respond(conn, replay)
    end
  end

  @doc """
  POST /api/admin/replays/:id/rate — link an existing replay to players and
  apply Elo (idempotent).
  """
  def rate(conn, %{"id" => id}) do
    with {:ok, replay} <- Replays.link_and_rate(Replays.get_replay!(id)) do
      json(conn, %{data: JSON.replay_summary(Replays.get_replay!(replay.id))})
    end
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  defp upload(conn, params, source) do
    with {:ok, conn, replay} <- do_upload(conn, params, source) do
      respond(conn, replay)
    end
  end

  defp do_upload(conn, %{"file" => %Plug.Upload{path: path}}, source) do
    max = Replays.max_size()

    with {:ok, %File.Stat{size: size}} when size <= max <- File.stat(path),
         {:ok, data} <- File.read(path),
         {:ok, replay, status} <- Replays.parse_and_save(data, source: source) do
      status = if status == :created, do: :created, else: :ok
      {:ok, put_status(conn, status), replay}
    else
      {:ok, %File.Stat{}} -> {:error, :too_large}
      {:error, reason} when is_atom(reason) or is_binary(reason) -> upload_error(reason)
      {:error, %Ecto.Changeset{}} = error -> error
    end
  end

  defp do_upload(_conn, _params, _source) do
    {:error, "Missing file upload. Send a multipart form with a \"file\" field."}
  end

  # File.read/stat errors are POSIX atoms; NIF parse errors are strings.
  defp upload_error(reason) when reason in [:too_large, :invalid_format], do: {:error, reason}
  defp upload_error(reason) when is_atom(reason), do: {:error, "Failed to read upload: #{reason}"}
  defp upload_error(reason), do: {:error, {:unparseable, reason}}

  defp respond(conn, replay) do
    json(conn, %{data: JSON.replay(Replays.get_replay!(replay.id))})
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(_, default), do: default
end

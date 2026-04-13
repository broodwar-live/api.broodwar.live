defmodule BroodwarWeb.Api.ReplayController do
  use BroodwarWeb, :controller

  alias Broodwar.Replays
  alias Broodwar.Pagination
  alias BroodwarWeb.Api.JSON

  action_fallback BroodwarWeb.Api.FallbackController

  def index(conn, params) do
    pagination_opts = parse_pagination(params)

    replays =
      Replays.list_replays()
      |> paginate(pagination_opts)

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

  def create(conn, %{"file" => %Plug.Upload{path: path}}) do
    case File.read(path) do
      {:ok, data} ->
        case Replays.parse_and_save(data) do
          {:ok, replay} ->
            replay = Replays.get_replay!(replay.id)

            conn
            |> put_status(:created)
            |> json(%{data: JSON.replay(replay)})

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, "Failed to read upload: #{reason}"}
    end
  end

  def create(_conn, _params) do
    {:error, "Missing file upload. Send a multipart form with a \"file\" field."}
  end

  defp parse_pagination(params) do
    [
      page: parse_int(params["page"], 1),
      per_page: parse_int(params["per_page"], 50)
    ]
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end
  defp parse_int(val, _default) when is_integer(val), do: val
  defp parse_int(_, default), do: default

  defp paginate(list, opts) when is_list(list) do
    meta = Pagination.pagination_meta(opts)
    offset = (meta.page - 1) * meta.per_page

    list
    |> Enum.drop(offset)
    |> Enum.take(meta.per_page)
  end
end

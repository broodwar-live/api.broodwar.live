defmodule Broodwar.Ingestion.StreamPoll do
  @moduledoc """
  Oban worker that polls live BW streams from Twitch via Helix API.

  Runs every 5 minutes on the `:ingestion` queue. Fetches all live streams
  for StarCraft: Brood War (game_id 1466), upserts stream records, and
  marks stale streams as offline.

  ## Configuration

  Set in config or environment variables:

      config :broodwar, :twitch,
        client_id: "your_client_id",
        client_secret: "your_client_secret"

  ## Scheduling

      Oban.insert(Broodwar.Ingestion.StreamPoll.new(%{}))
  """
  use Oban.Worker,
    queue: :ingestion,
    max_attempts: 3,
    unique: [period: 120]

  require Logger
  import Ecto.Query
  alias Broodwar.Repo
  alias Broodwar.Streams.Stream

  @poll_interval_seconds 300
  @stale_threshold_seconds 600
  @twitch_token_url "https://id.twitch.tv/oauth2/token"
  @twitch_streams_url "https://api.twitch.tv/helix/streams"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    config = Application.get_env(:broodwar, :twitch, [])
    client_id = config[:client_id] || ""
    client_secret = config[:client_secret] || ""

    if client_id == "" or client_secret == "" do
      Logger.warning("[StreamPoll] Twitch credentials not configured, skipping poll")
      reschedule()
      :ok
    else
      case get_access_token(client_id, client_secret) do
        {:ok, token} ->
          poll_streams(client_id, token, config[:bw_game_id] || "1466")
          mark_stale_offline()
          reschedule()
          :ok

        {:error, reason} ->
          Logger.error("[StreamPoll] Failed to get Twitch token: #{inspect(reason)}")
          reschedule()
          {:error, reason}
      end
    end
  end

  # -- Twitch OAuth --

  defp get_access_token(client_id, client_secret) do
    case Req.post(@twitch_token_url,
           form: [
             client_id: client_id,
             client_secret: client_secret,
             grant_type: "client_credentials"
           ]
         ) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Stream polling --

  defp poll_streams(client_id, token, game_id) do
    case fetch_live_streams(client_id, token, game_id) do
      {:ok, streams} ->
        now = DateTime.utc_now()

        for stream <- streams do
          upsert_stream(%{
            platform: "twitch",
            channel_id: stream["user_login"],
            title: stream["title"],
            is_live: true,
            viewer_count: stream["viewer_count"] || 0,
            last_seen_at: now
          })
        end

        Logger.info("[StreamPoll] Found #{length(streams)} live BW streams")

      {:error, reason} ->
        Logger.error("[StreamPoll] Failed to fetch streams: #{inspect(reason)}")
    end
  end

  defp fetch_live_streams(client_id, token, game_id) do
    case Req.get(@twitch_streams_url,
           params: [game_id: game_id, first: 100],
           headers: [
             {"Authorization", "Bearer #{token}"},
             {"Client-Id", client_id}
           ]
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Database operations --

  defp upsert_stream(attrs) do
    case Repo.one(
           from(s in Stream,
             where: s.platform == ^attrs.platform and s.channel_id == ^attrs.channel_id,
             limit: 1
           )
         ) do
      nil ->
        %Stream{}
        |> Stream.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Stream.changeset(attrs)
        |> Repo.update()
    end
  end

  defp mark_stale_offline do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_threshold_seconds, :second)

    {count, _} =
      from(s in Stream,
        where: s.is_live == true and s.last_seen_at < ^cutoff
      )
      |> Repo.update_all(set: [is_live: false, viewer_count: 0])

    if count > 0, do: Logger.info("[StreamPoll] Marked #{count} stale streams offline")
  end

  defp reschedule do
    %{}
    |> __MODULE__.new(schedule_in: @poll_interval_seconds)
    |> Oban.insert()
  end
end

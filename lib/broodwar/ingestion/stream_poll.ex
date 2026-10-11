defmodule Broodwar.Ingestion.StreamPoll do
  @moduledoc """
  Oban worker that polls live BW streams from Twitch and SOOP (formerly
  AfreecaTV), upserts stream records, and marks stale streams offline.

  Scheduled every 3 minutes by the `Oban.Plugins.Cron` entry in
  `config/config.exs`. Each platform is skipped (with a warning) unless its
  credentials are configured, and HTTP failures are logged, never raised,
  so one platform being down doesn't block the other.

  ## Configuration

      config :broodwar, :twitch,
        client_id: "...",          # TWITCH_CLIENT_ID
        client_secret: "...",      # TWITCH_CLIENT_SECRET
        bw_game_id: "1466"

      config :broodwar, :soop,
        client_id: "...",          # SOOP_CLIENT_ID (developers.sooplive.co.kr)
        category: "..."            # SOOP_CATEGORY (StarCraft category number)

  The legacy `openapi.afreecatv.com/broad/search` endpoint is gone (404).
  SOOP's `openapi.sooplive.co.kr/broad/list` exists but rejects requests
  without a registered `client_id`, so SOOP polling is opt-in. SOOP streams
  are stored with platform `"afreeca"` for compatibility with existing data.
  """
  use Oban.Worker,
    queue: :ingestion,
    max_attempts: 1,
    unique: [period: 120]

  require Logger
  import Ecto.Query
  alias Broodwar.Repo
  alias Broodwar.Streams.Stream

  @stale_threshold_seconds 600
  @twitch_token_url "https://id.twitch.tv/oauth2/token"
  @twitch_streams_url "https://api.twitch.tv/helix/streams"
  @soop_broad_list_url "https://openapi.sooplive.co.kr/broad/list"
  @http_opts [retry: false, receive_timeout: 15_000]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    poll_twitch_streams()
    poll_soop_streams()
    mark_stale_offline()
    :ok
  end

  defp poll_twitch_streams do
    config = Application.get_env(:broodwar, :twitch, [])
    client_id = config[:client_id] || ""
    client_secret = config[:client_secret] || ""

    if client_id == "" or client_secret == "" do
      Logger.warning("[StreamPoll] Twitch credentials not configured, skipping")
    else
      case cached_access_token(client_id, client_secret) do
        {:ok, token} ->
          poll_streams(client_id, token, config[:bw_game_id] || "1466")

        {:error, reason} ->
          Logger.error("[StreamPoll] Failed to get Twitch token: #{inspect(reason)}")
      end
    end
  end

  # -- Twitch OAuth --

  # App access tokens live ~60 days; reuse one for an hour instead of
  # requesting a new token every poll. Errors are not cached.
  defp cached_access_token(client_id, client_secret) do
    case Broodwar.Cache.fetch("twitch_token", 3600, fn ->
           get_access_token(client_id, client_secret)
         end) do
      {:ok, _token} = ok ->
        ok

      error ->
        Broodwar.Cache.invalidate("twitch_token")
        error
    end
  end

  defp get_access_token(client_id, client_secret) do
    case Req.post(
           @twitch_token_url,
           @http_opts ++
             [
               form: [
                 client_id: client_id,
                 client_secret: client_secret,
                 grant_type: "client_credentials"
               ]
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
    case Req.get(
           @twitch_streams_url,
           @http_opts ++
             [
               params: [game_id: game_id, first: 100],
               headers: [
                 {"Authorization", "Bearer #{token}"},
                 {"Client-Id", client_id}
               ]
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

  # -- SOOP (AfreecaTV) polling --

  defp poll_soop_streams do
    config = Application.get_env(:broodwar, :soop, [])
    client_id = config[:client_id] || ""
    category = config[:category] || ""

    if client_id == "" or category == "" do
      Logger.warning("[StreamPoll] SOOP client_id/category not configured, skipping")
    else
      fetch_soop_streams(client_id, category)
    end
  end

  defp fetch_soop_streams(client_id, category) do
    params = [
      client_id: client_id,
      select_key: "cate",
      select_value: category,
      order_type: "view_cnt",
      page_no: 1
    ]

    case Req.get(@soop_broad_list_url, @http_opts ++ [params: params]) do
      {:ok, %{status: 200, body: %{"broad" => broadcasts}}} when is_list(broadcasts) ->
        now = DateTime.utc_now()
        Enum.each(broadcasts, &upsert_soop_broadcast(&1, now))
        Logger.info("[StreamPoll] Found #{length(broadcasts)} SOOP BW streams")

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[StreamPoll] SOOP returned HTTP #{status}: #{inspect(body)}")

      {:error, reason} ->
        Logger.error("[StreamPoll] SOOP error: #{inspect(reason)}")
    end
  end

  defp upsert_soop_broadcast(b, now) do
    case b["user_id"] || b["broad_no"] do
      nil ->
        :skip

      channel_id ->
        upsert_stream(%{
          platform: "afreeca",
          channel_id: to_string(channel_id),
          title: b["broad_title"],
          is_live: true,
          viewer_count: parse_viewer_count(b["total_view_cnt"]),
          last_seen_at: now
        })
    end
  end

  defp parse_viewer_count(nil), do: 0
  defp parse_viewer_count(n) when is_integer(n), do: n

  defp parse_viewer_count(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
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
end

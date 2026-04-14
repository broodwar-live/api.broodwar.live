defmodule Broodwar.Ingestion.StreamPoll do
  @moduledoc """
  Oban worker that polls Korean BW streams on Twitch and AfreecaTV.

  Runs periodically (default: every 5 minutes) on the `:ingestion` queue.
  Updates the `streams` table with live status, viewer count, and title.

  ## Scheduling

  Add to your application supervisor or runtime config:

      Oban.insert(Broodwar.Ingestion.StreamPoll.new(%{}, schedule_in: 0))

  The worker reschedules itself after each run.
  """
  use Oban.Worker,
    queue: :ingestion,
    max_attempts: 3,
    unique: [period: 120]

  import Ecto.Query
  alias Broodwar.Repo
  alias Broodwar.Streams.Stream

  @poll_interval_seconds 300

  # Known BW streamer channels to poll.
  # In production, this would come from the database or config.
  @twitch_channels [
    "starcraft",
    "broodwar",
    "asl_en",
    "asl_kr",
    "bsl_en"
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    poll_twitch()
    mark_stale_offline()
    reschedule()
    :ok
  end

  defp poll_twitch do
    # In production, this would use the Twitch Helix API with OAuth.
    # For now, we update known channels from the database.
    #
    # GET https://api.twitch.tv/helix/streams?game_id=1466&first=50
    # (game_id 1466 = StarCraft: Brood War)
    #
    # Headers: Authorization: Bearer {token}, Client-Id: {client_id}
    #
    # For each live stream, upsert into the streams table.
    #
    # This is a placeholder that demonstrates the pattern.
    # Actual HTTP calls require :req or :httpoison dependency.

    for channel_id <- @twitch_channels do
      upsert_stream(%{
        platform: "twitch",
        channel_id: channel_id,
        # These would come from API response:
        is_live: false,
        viewer_count: 0,
        title: nil,
        last_seen_at: DateTime.utc_now()
      })
    end
  end

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

  # Mark streams as offline if they haven't been seen in 10 minutes.
  defp mark_stale_offline do
    cutoff = DateTime.add(DateTime.utc_now(), -600, :second)

    from(s in Stream,
      where: s.is_live == true and s.last_seen_at < ^cutoff
    )
    |> Repo.update_all(set: [is_live: false, viewer_count: 0])
  end

  defp reschedule do
    %{}
    |> __MODULE__.new(schedule_in: @poll_interval_seconds)
    |> Oban.insert()
  end
end

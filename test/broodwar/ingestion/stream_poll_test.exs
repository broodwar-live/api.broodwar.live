defmodule Broodwar.Ingestion.StreamPollTest do
  use Broodwar.DataCase

  use Oban.Testing, repo: Broodwar.Repo

  import ExUnit.CaptureLog

  alias Broodwar.Ingestion.StreamPoll
  alias Broodwar.Streams.Stream

  test "perform/1 without credentials skips platforms and marks stale streams offline" do
    stale = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)

    {:ok, stream} =
      %Stream{}
      |> Stream.changeset(%{
        platform: "twitch",
        channel_id: "old",
        is_live: true,
        viewer_count: 42,
        last_seen_at: stale
      })
      |> Repo.insert()

    capture_log(fn -> assert :ok = perform_job(StreamPoll, %{}) end)

    stream = Repo.reload!(stream)
    refute stream.is_live
    assert stream.viewer_count == 0
  end

  test "cron config schedules StreamPoll" do
    plugins = Application.fetch_env!(:broodwar, Oban)[:plugins]
    {Oban.Plugins.Cron, opts} = List.keyfind(plugins, Oban.Plugins.Cron, 0)
    assert {_expr, StreamPoll} = List.keyfind(opts[:crontab], StreamPoll, 1)
  end
end

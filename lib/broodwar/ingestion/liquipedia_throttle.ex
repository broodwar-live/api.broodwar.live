defmodule Broodwar.Ingestion.LiquipediaThrottle do
  @moduledoc """
  Node-wide pacing for Liquipedia API requests, per their API terms:
  at most 1 request per 2 s, and at most 1 `action=parse` per 30 s.

  Every caller (Oban workers, mix tasks, iex) reserves a slot here before
  sending, so concurrent jobs cannot exceed the limits. The intervals are
  configurable (tests set them to 0):

      config :broodwar, Broodwar.Ingestion.LiquipediaThrottle,
        query_interval_ms: 2_100,
        parse_interval_ms: 30_000
  """
  use GenServer

  @defaults [query_interval_ms: 2_100, parse_interval_ms: 30_000]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Blocks until a request of `kind` (`:query` or `:parse`) may be sent.
  Every request also counts against the general per-request interval.
  """
  @spec wait(:query | :parse) :: :ok
  def wait(kind) when kind in [:query, :parse] do
    case GenServer.call(__MODULE__, {:reserve, kind}, :infinity) do
      0 -> :ok
      ms -> Process.sleep(ms)
    end
  end

  @impl true
  def init(nil), do: {:ok, %{any: nil, parse: nil}}

  @impl true
  def handle_call({:reserve, kind}, _from, state) do
    now = System.monotonic_time(:millisecond)
    config = Keyword.merge(@defaults, Application.get_env(:broodwar, __MODULE__, []))

    earliest = next_slot(state.any, config[:query_interval_ms], now)

    earliest =
      if kind == :parse,
        do: max(earliest, next_slot(state.parse, config[:parse_interval_ms], now)),
        else: earliest

    state = %{state | any: earliest}
    state = if kind == :parse, do: %{state | parse: earliest}, else: state
    {:reply, earliest - now, state}
  end

  defp next_slot(nil, _interval, now), do: now
  defp next_slot(last, interval, now), do: max(now, last + interval)
end

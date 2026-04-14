defmodule Broodwar.Cache do
  @moduledoc """
  Simple ETS-based cache with TTL for expensive API responses.

  ## Usage

      Broodwar.Cache.fetch("balance_stats", 300, fn -> compute_expensive_thing() end)
      Broodwar.Cache.invalidate("balance_stats")
      Broodwar.Cache.invalidate_all()
  """
  use GenServer

  @table :broodwar_cache

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Fetch a cached value or compute it.

  `ttl_seconds` is how long the cached value is valid.
  `fun` is called to compute the value on cache miss.
  """
  def fetch(key, ttl_seconds, fun) do
    now = System.monotonic_time(:second)

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] when expires_at > now ->
        value

      _ ->
        value = fun.()
        :ets.insert(@table, {key, value, now + ttl_seconds})
        value
    end
  end

  @doc "Invalidate a single cache key."
  def invalidate(key) do
    :ets.delete(@table, key)
    :ok
  end

  @doc "Invalidate all cached entries."
  def invalidate_all do
    :ets.delete_all_objects(@table)
    :ok
  end

  # -- GenServer callbacks --

  @impl GenServer
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end
end

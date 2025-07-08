defmodule RubberDuck.Analysis.Cache do
  @moduledoc """
  Caching system for analysis results.

  This module provides caching capabilities for analysis results to avoid
  re-analyzing unchanged files and improve performance.
  """

  use GenServer

  @table_name :analysis_cache
  @cache_ttl :timer.hours(24)

  # Client API

  @doc """
  Starts the cache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a cached analysis result.
  """
  @spec get(String.t()) :: {:ok, term()} | :miss
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expiry}] ->
        if DateTime.compare(DateTime.utc_now(), expiry) == :lt do
          {:ok, value}
        else
          :ets.delete(@table_name, key)
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  @doc """
  Stores an analysis result in the cache.
  """
  @spec put(String.t(), term(), integer()) :: :ok
  def put(key, value, ttl \\ @cache_ttl) do
    expiry = DateTime.add(DateTime.utc_now(), ttl, :millisecond)
    :ets.insert(@table_name, {key, value, expiry})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Clears all cached entries.
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Generates a cache key for a file analysis.
  """
  @spec cache_key(String.t(), String.t(), map()) :: String.t()
  def cache_key(file_path, content_hash, options \\ %{}) do
    options_hash =
      :crypto.hash(:sha256, :erlang.term_to_binary(options))
      |> Base.encode16(case: :lower)

    "#{file_path}:#{content_hash}:#{options_hash}"
  end

  @doc """
  Computes content hash for a file.
  """
  @spec content_hash(String.t()) :: String.t()
  def content_hash(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, :timer.minutes(30))
  end

  defp cleanup_expired do
    now = DateTime.utc_now()

    :ets.safe_fixtable(@table_name, true)

    try do
      :ets.foldl(
        fn {key, _value, expiry}, acc ->
          if DateTime.compare(now, expiry) == :gt do
            :ets.delete(@table_name, key)
          end

          acc
        end,
        nil,
        @table_name
      )
    after
      :ets.safe_fixtable(@table_name, false)
    end
  end
end

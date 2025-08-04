defmodule RubberDuck.Jido.Signals.SignalPriority do
  @moduledoc """
  Priority-based signal delivery management.
  
  This module manages signal delivery based on priority levels, ensuring
  critical signals are processed first while maintaining fairness for
  lower priority signals. Uses priority queues with configurable processing ratios.
  """
  
  use GenServer
  require Logger
  
  @type priority :: :critical | :high | :normal | :low
  
  @priorities [:critical, :high, :normal, :low]
  @default_ratios %{
    critical: 1.0,  # Always process
    high: 0.7,      # Process 70% of the time
    normal: 0.4,    # Process 40% of the time
    low: 0.1        # Process 10% of the time
  }
  
  @type queue_entry :: %{
    signal: map(),
    priority: priority(),
    enqueued_at: DateTime.t(),
    metadata: map()
  }
  
  # Client API
  
  @doc """
  Starts the priority queue manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Enqueues a signal with the specified priority.
  """
  @spec enqueue(map(), priority(), keyword()) :: :ok
  def enqueue(signal, priority \\ :normal, opts \\ []) do
    GenServer.cast(__MODULE__, {:enqueue, signal, priority, opts})
  end
  
  @doc """
  Dequeues the next signal based on priority.
  """
  @spec dequeue() :: {:ok, queue_entry()} | {:error, :empty}
  def dequeue do
    GenServer.call(__MODULE__, :dequeue)
  end
  
  @doc """
  Dequeues multiple signals at once.
  """
  @spec dequeue_batch(non_neg_integer()) :: {:ok, [queue_entry()]} | {:error, :empty}
  def dequeue_batch(count \\ 10) do
    GenServer.call(__MODULE__, {:dequeue_batch, count})
  end
  
  @doc """
  Returns the current queue sizes by priority.
  """
  @spec queue_sizes() :: %{priority() => non_neg_integer()}
  def queue_sizes do
    GenServer.call(__MODULE__, :queue_sizes)
  end
  
  @doc """
  Updates the processing ratios for priorities.
  """
  @spec update_ratios(map()) :: :ok
  def update_ratios(ratios) do
    GenServer.call(__MODULE__, {:update_ratios, ratios})
  end
  
  @doc """
  Returns queue statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    state = %{
      queues: initialize_queues(),
      ratios: Keyword.get(opts, :ratios, @default_ratios),
      max_queue_size: Keyword.get(opts, :max_queue_size, 10_000),
      stats: %{
        enqueued: %{critical: 0, high: 0, normal: 0, low: 0},
        dequeued: %{critical: 0, high: 0, normal: 0, low: 0},
        dropped: %{critical: 0, high: 0, normal: 0, low: 0},
        avg_wait_time: %{critical: 0, high: 0, normal: 0, low: 0}
      },
      last_dequeue: %{critical: 0, high: 0, normal: 0, low: 0}
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:enqueue, signal, priority, opts}, state) do
    if valid_priority?(priority) do
      entry = %{
        signal: signal,
        priority: priority,
        enqueued_at: DateTime.utc_now(),
        metadata: Keyword.get(opts, :metadata, %{})
      }
      
      new_state = add_to_queue(state, priority, entry)
      {:noreply, new_state}
    else
      Logger.error("Invalid priority: #{inspect(priority)}")
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_call(:dequeue, _from, state) do
    case select_next_signal(state) do
      {nil, _} ->
        {:reply, {:error, :empty}, state}
        
      {entry, new_state} ->
        updated_state = update_dequeue_stats(new_state, entry)
        {:reply, {:ok, entry}, updated_state}
    end
  end
  
  @impl true
  def handle_call({:dequeue_batch, count}, _from, state) do
    {entries, new_state} = dequeue_multiple(state, count, [])
    
    if Enum.empty?(entries) do
      {:reply, {:error, :empty}, new_state}
    else
      {:reply, {:ok, entries}, new_state}
    end
  end
  
  @impl true
  def handle_call(:queue_sizes, _from, state) do
    sizes = Enum.reduce(@priorities, %{}, fn priority, acc ->
      queue = Map.get(state.queues, priority, :queue.new())
      Map.put(acc, priority, :queue.len(queue))
    end)
    
    {:reply, sizes, state}
  end
  
  @impl true
  def handle_call({:update_ratios, ratios}, _from, state) do
    merged_ratios = Map.merge(state.ratios, ratios)
    {:reply, :ok, %{state | ratios: merged_ratios}}
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    current_sizes = Enum.reduce(@priorities, %{}, fn priority, acc ->
      queue = Map.get(state.queues, priority, :queue.new())
      Map.put(acc, priority, :queue.len(queue))
    end)
    
    stats = Map.merge(state.stats, %{
      current_sizes: current_sizes,
      ratios: state.ratios,
      total_enqueued: sum_stats(state.stats.enqueued),
      total_dequeued: sum_stats(state.stats.dequeued),
      total_dropped: sum_stats(state.stats.dropped)
    })
    
    {:reply, stats, state}
  end
  
  # Private functions
  
  defp initialize_queues do
    Enum.reduce(@priorities, %{}, fn priority, acc ->
      Map.put(acc, priority, :queue.new())
    end)
  end
  
  defp valid_priority?(priority), do: priority in @priorities
  
  defp add_to_queue(state, priority, entry) do
    queue = Map.get(state.queues, priority, :queue.new())
    
    # Check queue size limit
    if :queue.len(queue) >= state.max_queue_size do
      # Drop oldest entry if at limit (for non-critical)
      if priority == :critical do
        # Never drop critical signals
        new_queue = :queue.in(entry, queue)
        update_queue_and_stats(state, priority, new_queue, :enqueued)
      else
        Logger.warning("Queue full for priority #{priority}, dropping oldest")
        {_, smaller_queue} = :queue.out(queue)
        new_queue = :queue.in(entry, smaller_queue)
        state
        |> update_queue_and_stats(priority, new_queue, :enqueued)
        |> update_queue_and_stats(priority, new_queue, :dropped)
      end
    else
      new_queue = :queue.in(entry, queue)
      update_queue_and_stats(state, priority, new_queue, :enqueued)
    end
  end
  
  defp select_next_signal(state) do
    # Use weighted selection based on ratios and last dequeue times
    priority = select_priority_weighted(state)
    
    if priority do
      dequeue_from_priority(state, priority)
    else
      # All queues empty
      {nil, state}
    end
  end
  
  defp select_priority_weighted(state) do
    # Build candidates with their selection probability
    candidates = @priorities
      |> Enum.filter(fn priority ->
        queue = Map.get(state.queues, priority, :queue.new())
        :queue.len(queue) > 0
      end)
      |> Enum.map(fn priority ->
        ratio = Map.get(state.ratios, priority, 0.5)
        last = Map.get(state.last_dequeue, priority, 0)
        now = System.monotonic_time(:millisecond)
        
        # Increase weight for priorities that haven't been served recently
        time_factor = min((now - last) / 1000, 10) / 10  # 0 to 1
        weight = ratio * (1 + time_factor)
        
        {priority, weight}
      end)
    
    # Select based on weights
    if Enum.empty?(candidates) do
      nil
    else
      total_weight = candidates |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      
      if total_weight == 0 do
        # Fallback to first available
        {priority, _} = List.first(candidates)
        priority
      else
        random = :rand.uniform() * total_weight
        select_by_weight(candidates, random, 0)
      end
    end
  end
  
  defp select_by_weight([{priority, weight} | rest], random, accumulated) do
    new_accumulated = accumulated + weight
    if random <= new_accumulated do
      priority
    else
      select_by_weight(rest, random, new_accumulated)
    end
  end
  defp select_by_weight([], _, _), do: nil
  
  defp dequeue_from_priority(state, priority) do
    queue = Map.get(state.queues, priority, :queue.new())
    
    case :queue.out(queue) do
      {{:value, entry}, new_queue} ->
        new_queues = Map.put(state.queues, priority, new_queue)
        new_last = Map.put(state.last_dequeue, priority, System.monotonic_time(:millisecond))
        
        new_state = %{state | 
          queues: new_queues,
          last_dequeue: new_last
        }
        
        {entry, new_state}
        
      {:empty, _} ->
        {nil, state}
    end
  end
  
  defp dequeue_multiple(state, 0, accumulated), do: {Enum.reverse(accumulated), state}
  defp dequeue_multiple(state, count, accumulated) do
    case select_next_signal(state) do
      {nil, new_state} ->
        {Enum.reverse(accumulated), new_state}
        
      {entry, new_state} ->
        updated_state = update_dequeue_stats(new_state, entry)
        dequeue_multiple(updated_state, count - 1, [entry | accumulated])
    end
  end
  
  defp update_queue_and_stats(state, priority, new_queue, stat_type) do
    new_queues = Map.put(state.queues, priority, new_queue)
    
    new_stats = update_nested_stat(state.stats, stat_type, priority, fn count ->
      count + 1
    end)
    
    %{state | queues: new_queues, stats: new_stats}
  end
  
  defp update_dequeue_stats(state, entry) do
    priority = entry.priority
    wait_time = DateTime.diff(DateTime.utc_now(), entry.enqueued_at, :millisecond)
    
    new_stats = state.stats
      |> update_nested_stat(:dequeued, priority, &(&1 + 1))
      |> update_avg_wait_time(priority, wait_time)
    
    %{state | stats: new_stats}
  end
  
  defp update_nested_stat(stats, stat_type, priority, update_fn) do
    Map.update!(stats, stat_type, fn priorities ->
      Map.update!(priorities, priority, update_fn)
    end)
  end
  
  defp update_avg_wait_time(stats, priority, wait_time) do
    Map.update!(stats, :avg_wait_time, fn avgs ->
      current_avg = Map.get(avgs, priority, 0)
      dequeued_count = get_in(stats, [:dequeued, priority]) || 1
      
      # Calculate running average
      new_avg = ((current_avg * (dequeued_count - 1)) + wait_time) / dequeued_count
      Map.put(avgs, priority, round(new_avg))
    end)
  end
  
  defp sum_stats(stat_map) do
    Map.values(stat_map) |> Enum.sum()
  end
end
defmodule RubberDuck.ILP.RealTime.PriorityQueue do
  @moduledoc """
  Binary heap implementation for O(log n) request prioritization.
  Manages request ordering based on priority and deadline constraints.
  """
  use GenServer
  require Logger

  defstruct [:heap, :size]

  @doc """
  Starts the priority queue process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new priority queue.
  """
  def new do
    %__MODULE__{
      heap: :gb_trees.empty(),
      size: 0
    }
  end

  @doc """
  Inserts an item into the priority queue.
  """
  def insert(queue, item) do
    key = {item.priority, item.timestamp, item.id}
    new_heap = :gb_trees.insert(key, item, queue.heap)
    
    %{queue | 
      heap: new_heap,
      size: queue.size + 1
    }
  end

  @doc """
  Extracts the minimum (highest priority) item from the queue.
  """
  def extract_min(%{size: 0} = queue) do
    {:empty, queue}
  end

  def extract_min(queue) do
    case :gb_trees.take_smallest(queue.heap) do
      {_key, item, remaining_heap} ->
        new_queue = %{queue | 
          heap: remaining_heap,
          size: queue.size - 1
        }
        {:ok, item, new_queue}
      
      nil ->
        {:empty, queue}
    end
  end

  @doc """
  Gets the current size of the queue.
  """
  def size do
    GenServer.call(__MODULE__, :size)
  end

  @doc """
  Gets queue statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Checks for expired requests and removes them.
  """
  def cleanup_expired do
    GenServer.cast(__MODULE__, :cleanup_expired)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting ILP RealTime PriorityQueue")
    
    # Schedule periodic cleanup of expired requests
    Process.send_after(self(), :cleanup_expired, :timer.seconds(5))
    
    {:ok, new()}
  end

  @impl true
  def handle_call(:size, _from, state) do
    {:reply, state.size, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      size: state.size,
      is_empty: state.size == 0,
      heap_info: get_heap_info(state.heap)
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_cast(:cleanup_expired, state) do
    new_state = remove_expired_requests(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    new_state = remove_expired_requests(state)
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup_expired, :timer.seconds(5))
    
    {:noreply, new_state}
  end

  defp remove_expired_requests(state) do
    current_time = System.monotonic_time(:millisecond)
    
    {clean_heap, removed_count} = 
      :gb_trees.to_list(state.heap)
      |> Enum.filter(fn {_key, item} ->
        item.deadline > current_time
      end)
      |> Enum.reduce({:gb_trees.empty(), 0}, fn {key, item}, {heap, count} ->
        new_heap = :gb_trees.insert(key, item, heap)
        {new_heap, count}
      end)
    
    if removed_count > 0 do
      Logger.debug("Removed #{removed_count} expired requests from priority queue")
    end
    
    %{state |
      heap: clean_heap,
      size: state.size - removed_count
    }
  end

  defp get_heap_info(heap) do
    case :gb_trees.size(heap) do
      0 -> %{empty: true}
      size -> 
        {min_key, _} = :gb_trees.smallest(heap)
        {max_key, _} = :gb_trees.largest(heap)
        
        %{
          size: size,
          min_priority: elem(min_key, 0),
          max_priority: elem(max_key, 0)
        }
    end
  end
end
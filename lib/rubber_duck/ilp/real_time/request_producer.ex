defmodule RubberDuck.ILP.RealTime.RequestProducer do
  @moduledoc """
  GenStage producer for real-time processing requests.
  Handles incoming requests with priority-based dispatching.
  """
  use GenStage
  require Logger

  defstruct [:queue, :demand, :metrics]

  @doc """
  Starts the request producer.
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Submits a request for processing.
  """
  def submit_request(request) do
    GenStage.cast(__MODULE__, {:submit, request})
  end

  @doc """
  Gets current queue metrics.
  """
  def get_metrics do
    GenStage.call(__MODULE__, :get_metrics)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting ILP RealTime RequestProducer")
    
    state = %__MODULE__{
      queue: RubberDuck.ILP.RealTime.PriorityQueue.new(),
      demand: 0,
      metrics: %{
        total_requests: 0,
        avg_processing_time: 0,
        last_request_time: nil
      }
    }
    
    {:producer, state}
  end

  @impl true
  def handle_cast({:submit, request}, state) do
    start_time = System.monotonic_time(:millisecond)
    
    request_with_metadata = Map.merge(request, %{
      id: generate_request_id(),
      timestamp: start_time,
      priority: calculate_priority(request),
      deadline: start_time + get_deadline(request.type)
    })
    
    new_queue = RubberDuck.ILP.RealTime.PriorityQueue.insert(
      state.queue, 
      request_with_metadata
    )
    
    new_metrics = update_metrics(state.metrics, start_time)
    
    new_state = %{state | 
      queue: new_queue, 
      metrics: new_metrics
    }
    
    dispatch_events(new_state)
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    new_state = %{state | demand: state.demand + incoming_demand}
    dispatch_events(new_state)
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, [], state}
  end

  defp dispatch_events(%{demand: demand, queue: queue} = state) when demand > 0 do
    case RubberDuck.ILP.RealTime.PriorityQueue.extract_min(queue) do
      {:ok, event, remaining_queue} ->
        new_state = %{state | 
          queue: remaining_queue, 
          demand: demand - 1
        }
        
        {:noreply, [event], new_state}
      
      {:empty, queue} ->
        {:noreply, [], %{state | queue: queue}}
    end
  end

  defp dispatch_events(state) do
    {:noreply, [], state}
  end

  defp calculate_priority(%{type: :completion}), do: 1
  defp calculate_priority(%{type: :diagnostic}), do: 2
  defp calculate_priority(%{type: :hover}), do: 3
  defp calculate_priority(%{type: :definition}), do: 4
  defp calculate_priority(%{type: :references}), do: 5
  defp calculate_priority(_), do: 10

  defp get_deadline(:completion), do: 50    # 50ms for completions
  defp get_deadline(:diagnostic), do: 100   # 100ms for diagnostics
  defp get_deadline(:hover), do: 75         # 75ms for hover
  defp get_deadline(:definition), do: 150   # 150ms for go-to-definition
  defp get_deadline(:references), do: 200   # 200ms for find references
  defp get_deadline(_), do: 500             # 500ms default

  defp generate_request_id do
    System.unique_integer([:positive, :monotonic])
  end

  defp update_metrics(metrics, timestamp) do
    %{metrics |
      total_requests: metrics.total_requests + 1,
      last_request_time: timestamp
    }
  end
end
defmodule RubberDuck.ILP.RealTime.Pipeline do
  @moduledoc """
  Real-time processing pipeline using GenStage for sub-100ms response times.
  Implements demand-driven processing with sophisticated performance optimizations.
  """
  use Supervisor
  require Logger

  @doc """
  Starts the real-time processing pipeline.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting ILP RealTime Pipeline")
    
    children = [
      {RubberDuck.ILP.RealTime.RequestProducer, []},
      {RubberDuck.ILP.RealTime.IncrementalParser, 
        subscribe_to: [{RubberDuck.ILP.RealTime.RequestProducer, max_demand: 100}]},
      {RubberDuck.ILP.RealTime.SemanticAnalyzer,
        subscribe_to: [{RubberDuck.ILP.RealTime.IncrementalParser, max_demand: 50}]},
      {RubberDuck.ILP.RealTime.CompletionGenerator,
        subscribe_to: [{RubberDuck.ILP.RealTime.SemanticAnalyzer, max_demand: 25}]},
      {RubberDuck.ILP.RealTime.PredictiveCache, []},
      {RubberDuck.ILP.RealTime.PriorityQueue, []}
    ]
    
    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  Submits a request for real-time processing.
  """
  def process_request(request) do
    RubberDuck.ILP.RealTime.RequestProducer.submit_request(request)
  end

  @doc """
  Gets processing metrics for monitoring.
  """
  def get_metrics do
    %{
      queue_size: RubberDuck.ILP.RealTime.PriorityQueue.size(),
      cache_stats: RubberDuck.ILP.RealTime.PredictiveCache.stats(),
      pipeline_health: check_pipeline_health()
    }
  end

  defp check_pipeline_health do
    children = Supervisor.which_children(__MODULE__)
    
    Enum.all?(children, fn {_id, pid, _type, _modules} ->
      is_pid(pid) and Process.alive?(pid)
    end)
  end
end
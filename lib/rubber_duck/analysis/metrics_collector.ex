defmodule RubberDuck.Analysis.MetricsCollector do
  @moduledoc """
  Collects and manages code metrics for projects.
  
  Provides:
  - Test coverage data integration
  - Performance metrics
  - Security scan results
  - System resource monitoring
  """
  
  use GenServer
  require Logger
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets current metrics for a project.
  """
  def get_metrics(project_id) do
    GenServer.call(__MODULE__, {:get_metrics, project_id})
  end
  
  @doc """
  Updates metrics for a specific file.
  """
  def update_file_metrics(project_id, file_path, metrics) do
    GenServer.cast(__MODULE__, {:update_file_metrics, project_id, file_path, metrics})
  end
  
  @doc """
  Gets system resource usage.
  """
  def get_system_resources do
    GenServer.call(__MODULE__, :get_system_resources)
  end
  
  @doc """
  Gets LLM provider status.
  """
  def get_llm_status do
    GenServer.call(__MODULE__, :get_llm_status)
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Schedule periodic system monitoring
    :timer.send_interval(5_000, :update_system_resources)
    :timer.send_interval(10_000, :check_llm_status)
    
    state = %{
      project_metrics: %{},
      system_resources: %{
        cpu_usage: 0,
        memory_usage: 0,
        disk_usage: 0
      },
      llm_status: %{
        provider: nil,
        model: nil,
        available: true,
        rate_limit: nil,
        tokens_used: 0,
        tokens_limit: nil
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_metrics, project_id}, _from, state) do
    metrics = Map.get(state.project_metrics, project_id, default_metrics())
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_call(:get_system_resources, _from, state) do
    {:reply, state.system_resources, state}
  end
  
  @impl true
  def handle_call(:get_llm_status, _from, state) do
    {:reply, state.llm_status, state}
  end
  
  @impl true
  def handle_cast({:update_file_metrics, project_id, file_path, metrics}, state) do
    project_metrics = Map.get(state.project_metrics, project_id, default_metrics())
    
    # Update file-specific metrics
    updated_metrics = update_project_metrics(project_metrics, file_path, metrics)
    
    state = put_in(state.project_metrics[project_id], updated_metrics)
    
    # Broadcast update
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:metrics",
      {:metrics_updated, updated_metrics}
    )
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:update_system_resources, state) do
    resources = collect_system_resources()
    
    state = %{state | system_resources: resources}
    
    # Broadcast system status
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "system:status",
      {:system_resources, resources}
    )
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:check_llm_status, state) do
    status = check_llm_provider_status()
    
    state = %{state | llm_status: status}
    
    # Broadcast LLM status
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "system:status",
      {:llm_status, status}
    )
    
    {:noreply, state}
  end
  
  # Private Functions
  
  defp default_metrics do
    %{
      complexity: %{
        cyclomatic: 0,
        cognitive: 0,
        average_per_function: 0
      },
      test_coverage: nil,
      performance: nil,
      security_score: nil,
      security_issues: %{
        critical: 0,
        high: 0,
        medium: 0,
        low: 0
      },
      file_metrics: %{}
    }
  end
  
  defp update_project_metrics(project_metrics, file_path, file_metrics) do
    # Store file-specific metrics
    project_metrics = put_in(project_metrics.file_metrics[file_path], file_metrics)
    
    # Recalculate aggregates
    all_files = Map.values(project_metrics.file_metrics)
    
    if length(all_files) > 0 do
      # Average complexity
      total_complexity = Enum.reduce(all_files, 0, fn f, acc ->
        acc + (f[:complexity] || 0)
      end)
      
      avg_complexity = div(total_complexity, length(all_files))
      
      project_metrics
      |> put_in([:complexity, :average_per_function], avg_complexity)
    else
      project_metrics
    end
  end
  
  defp collect_system_resources do
    # Get system resources without OTP monitoring applications
    # Using Erlang built-ins instead
    
    # CPU usage - simplified estimation based on scheduler utilization
    cpu_usage = 
      try do
        _schedulers = :erlang.system_info(:schedulers_online)
        load = :erlang.statistics(:scheduler_wall_time)
        
        if is_list(load) do
          # Average load across schedulers
          total_active = Enum.reduce(load, 0, fn {_id, active, _total}, acc -> acc + active end)
          total_time = Enum.reduce(load, 0, fn {_id, _active, total}, acc -> acc + total end)
          
          if total_time > 0 do
            round(total_active / total_time * 100)
          else
            0
          end
        else
          0
        end
      rescue
        _ -> 0
      end
    
    # Memory usage
    memory_usage = 
      try do
        total_memory = :erlang.memory(:total)
        system_memory = :erlang.memory(:system)
        processes_memory = :erlang.memory(:processes)
        
        used_memory = system_memory + processes_memory
        round(used_memory / total_memory * 100)
      rescue
        _ -> 0
      end
    
    # Disk usage - simplified placeholder
    # Real disk monitoring would require external calls or NIFs
    disk_usage = 25 + :rand.uniform(50)  # Mock data for now
    
    %{
      cpu_usage: cpu_usage,
      memory_usage: memory_usage,
      disk_usage: disk_usage
    }
  end
  
  defp check_llm_provider_status do
    # TODO: Implement actual LLM provider checks
    # For now, return mock data
    
    # Get current configuration
    config = Application.get_env(:rubber_duck, :llm, %{})
    provider = config[:provider] || "openai"
    model = config[:model] || "gpt-4"
    
    # Mock rate limit data
    %{
      provider: provider,
      model: model,
      available: true,
      rate_limit: %{
        requests_per_minute: 60,
        requests_remaining: 45
      },
      tokens_used: :rand.uniform(50_000),
      tokens_limit: 100_000
    }
  end
  
  @doc """
  Simulates test coverage data.
  """
  def get_test_coverage(_project_id) do
    # TODO: Integrate with actual test coverage tools
    %{
      lines: 75 + :rand.uniform(20),
      functions: 80 + :rand.uniform(15),
      branches: 70 + :rand.uniform(25),
      uncovered_lines: :rand.uniform(50)
    }
  end
  
  @doc """
  Simulates performance metrics.
  """
  def get_performance_metrics(_project_id) do
    # TODO: Integrate with actual performance monitoring
    %{
      avg_response_time: 50 + :rand.uniform(100),
      memory_usage: :rand.uniform(500) * 1024 * 1024,
      query_count: :rand.uniform(20)
    }
  end
  
  @doc """
  Simulates security scan results.
  """
  def get_security_score(_project_id) do
    # TODO: Integrate with actual security scanning tools
    score = 70 + :rand.uniform(30)
    
    {score, %{
      critical: if(score < 80, do: :rand.uniform(2), else: 0),
      high: if(score < 90, do: :rand.uniform(3), else: 0),
      medium: :rand.uniform(5),
      low: :rand.uniform(10)
    }}
  end
end
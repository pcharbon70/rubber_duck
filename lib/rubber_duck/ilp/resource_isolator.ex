defmodule RubberDuck.ILP.ResourceIsolator do
  @moduledoc """
  Resource isolation system for separating real-time and batch workloads.
  Ensures real-time operations maintain sub-100ms response times.
  """
  use GenServer
  require Logger

  defstruct [
    :real_time_limits,
    :batch_limits,
    :current_usage,
    :resource_pools,
    :monitoring_enabled
  ]

  @real_time_priority_class 1
  @batch_priority_class 2
  @monitoring_interval :timer.seconds(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Allocates resources for a real-time operation.
  """
  def allocate_real_time_resources(operation_type, estimated_duration_ms) do
    GenServer.call(__MODULE__, {:allocate_real_time, operation_type, estimated_duration_ms})
  end

  @doc """
  Allocates resources for a batch operation.
  """
  def allocate_batch_resources(job_spec) do
    GenServer.call(__MODULE__, {:allocate_batch, job_spec})
  end

  @doc """
  Releases resources after operation completion.
  """
  def release_resources(allocation_id) do
    GenServer.cast(__MODULE__, {:release, allocation_id})
  end

  @doc """
  Gets current resource utilization.
  """
  def get_resource_usage do
    GenServer.call(__MODULE__, :get_usage)
  end

  @doc """
  Enables or disables strict resource monitoring.
  """
  def set_monitoring(enabled) do
    GenServer.cast(__MODULE__, {:set_monitoring, enabled})
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting ILP ResourceIsolator")
    
    state = %__MODULE__{
      real_time_limits: %{
        max_cpu_percent: 30,      # Reserve 30% CPU for real-time
        max_memory_mb: 512,       # Reserve 512MB memory for real-time
        max_concurrent_ops: 50,   # Max 50 concurrent real-time operations
        priority_class: @real_time_priority_class
      },
      batch_limits: %{
        max_cpu_percent: 60,      # Batch can use up to 60% CPU
        max_memory_mb: 2048,      # Batch can use up to 2GB memory
        max_concurrent_jobs: 5,   # Max 5 concurrent batch jobs
        priority_class: @batch_priority_class
      },
      current_usage: %{
        real_time: %{cpu_percent: 0, memory_mb: 0, active_operations: 0},
        batch: %{cpu_percent: 0, memory_mb: 0, active_jobs: 0}
      },
      resource_pools: %{
        real_time: %{},
        batch: %{}
      },
      monitoring_enabled: true
    }
    
    # Start resource monitoring
    Process.send_after(self(), :monitor_resources, @monitoring_interval)
    
    {:ok, state}
  end

  @impl true
  def handle_call({:allocate_real_time, operation_type, estimated_duration_ms}, _from, state) do
    required_resources = calculate_real_time_requirements(operation_type, estimated_duration_ms)
    
    case can_allocate_real_time?(required_resources, state) do
      true ->
        {allocation_id, new_state} = perform_real_time_allocation(required_resources, state)
        {:reply, {:ok, allocation_id}, new_state}
      
      false ->
        {:reply, {:error, :insufficient_resources}, state}
    end
  end

  @impl true
  def handle_call({:allocate_batch, job_spec}, _from, state) do
    required_resources = calculate_batch_requirements(job_spec)
    
    case can_allocate_batch?(required_resources, state) do
      true ->
        {allocation_id, new_state} = perform_batch_allocation(required_resources, state)
        {:reply, {:ok, allocation_id}, new_state}
      
      false ->
        {:reply, {:error, :insufficient_resources}, state}
    end
  end

  @impl true
  def handle_call(:get_usage, _from, state) do
    usage_report = %{
      real_time: state.current_usage.real_time,
      batch: state.current_usage.batch,
      limits: %{
        real_time: state.real_time_limits,
        batch: state.batch_limits
      },
      system: get_system_resources()
    }
    
    {:reply, usage_report, state}
  end

  @impl true
  def handle_cast({:release, allocation_id}, state) do
    new_state = release_allocation(allocation_id, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_monitoring, enabled}, state) do
    Logger.info("Resource monitoring #{if enabled, do: "enabled", else: "disabled"}")
    new_state = %{state | monitoring_enabled: enabled}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:monitor_resources, state) do
    new_state = if state.monitoring_enabled do
      monitor_and_adjust_resources(state)
    else
      state
    end
    
    # Schedule next monitoring cycle
    Process.send_after(self(), :monitor_resources, @monitoring_interval)
    
    {:noreply, new_state}
  end

  defp calculate_real_time_requirements(operation_type, estimated_duration_ms) do
    base_requirements = case operation_type do
      :completion ->
        %{cpu_percent: 2, memory_mb: 16, priority: 1}
      
      :diagnostic ->
        %{cpu_percent: 3, memory_mb: 24, priority: 2}
      
      :hover ->
        %{cpu_percent: 1, memory_mb: 8, priority: 1}
      
      :definition ->
        %{cpu_percent: 4, memory_mb: 32, priority: 3}
      
      :references ->
        %{cpu_percent: 5, memory_mb: 40, priority: 4}
      
      _ ->
        %{cpu_percent: 3, memory_mb: 20, priority: 5}
    end
    
    # Adjust based on estimated duration
    duration_multiplier = case estimated_duration_ms do
      ms when ms < 50 -> 1.0
      ms when ms < 100 -> 1.2
      ms when ms < 200 -> 1.5
      _ -> 2.0
    end
    
    %{base_requirements |
      cpu_percent: round(base_requirements.cpu_percent * duration_multiplier),
      memory_mb: round(base_requirements.memory_mb * duration_multiplier),
      estimated_duration_ms: estimated_duration_ms
    }
  end

  defp calculate_batch_requirements(%{type: type} = job_spec) do
    base_requirements = case type do
      :codebase_analysis ->
        %{cpu_percent: 25, memory_mb: 512, priority: 5}
      
      :refactoring ->
        %{cpu_percent: 20, memory_mb: 256, priority: 3}
      
      :documentation_generation ->
        %{cpu_percent: 15, memory_mb: 192, priority: 6}
      
      :test_generation ->
        %{cpu_percent: 30, memory_mb: 384, priority: 4}
      
      :dependency_analysis ->
        %{cpu_percent: 10, memory_mb: 128, priority: 7}
      
      _ ->
        %{cpu_percent: 20, memory_mb: 256, priority: 8}
    end
    
    # Adjust based on job scope
    scope_multiplier = case Map.get(job_spec, :scope, :medium) do
      :small -> 0.5
      :medium -> 1.0
      :large -> 2.0
      :xlarge -> 4.0
    end
    
    %{base_requirements |
      cpu_percent: round(base_requirements.cpu_percent * scope_multiplier),
      memory_mb: round(base_requirements.memory_mb * scope_multiplier)
    }
  end

  defp can_allocate_real_time?(required, state) do
    current = state.current_usage.real_time
    limits = state.real_time_limits
    
    (current.cpu_percent + required.cpu_percent) <= limits.max_cpu_percent and
    (current.memory_mb + required.memory_mb) <= limits.max_memory_mb and
    (current.active_operations + 1) <= limits.max_concurrent_ops
  end

  defp can_allocate_batch?(required, state) do
    current = state.current_usage.batch
    limits = state.batch_limits
    
    # Also ensure we don't interfere with real-time guarantees
    real_time_current = state.current_usage.real_time
    total_cpu_after_allocation = real_time_current.cpu_percent + current.cpu_percent + required.cpu_percent
    
    (current.cpu_percent + required.cpu_percent) <= limits.max_cpu_percent and
    (current.memory_mb + required.memory_mb) <= limits.max_memory_mb and
    (current.active_jobs + 1) <= limits.max_concurrent_jobs and
    total_cpu_after_allocation <= 80  # Leave 20% CPU headroom for system
  end

  defp perform_real_time_allocation(required, state) do
    allocation_id = generate_allocation_id()
    
    allocation = %{
      id: allocation_id,
      type: :real_time,
      resources: required,
      allocated_at: System.monotonic_time(:millisecond),
      process_pid: self()
    }
    
    # Update resource pools
    new_real_time_pool = Map.put(state.resource_pools.real_time, allocation_id, allocation)
    new_resource_pools = %{state.resource_pools | real_time: new_real_time_pool}
    
    # Update current usage
    current_rt = state.current_usage.real_time
    new_real_time_usage = %{current_rt |
      cpu_percent: current_rt.cpu_percent + required.cpu_percent,
      memory_mb: current_rt.memory_mb + required.memory_mb,
      active_operations: current_rt.active_operations + 1
    }
    
    new_current_usage = %{state.current_usage | real_time: new_real_time_usage}
    
    new_state = %{state |
      resource_pools: new_resource_pools,
      current_usage: new_current_usage
    }
    
    # Set process priority for real-time operation
    set_process_priority(self(), @real_time_priority_class)
    
    {allocation_id, new_state}
  end

  defp perform_batch_allocation(required, state) do
    allocation_id = generate_allocation_id()
    
    allocation = %{
      id: allocation_id,
      type: :batch,
      resources: required,
      allocated_at: System.monotonic_time(:millisecond),
      process_pid: self()
    }
    
    # Update resource pools
    new_batch_pool = Map.put(state.resource_pools.batch, allocation_id, allocation)
    new_resource_pools = %{state.resource_pools | batch: new_batch_pool}
    
    # Update current usage
    current_batch = state.current_usage.batch
    new_batch_usage = %{current_batch |
      cpu_percent: current_batch.cpu_percent + required.cpu_percent,
      memory_mb: current_batch.memory_mb + required.memory_mb,
      active_jobs: current_batch.active_jobs + 1
    }
    
    new_current_usage = %{state.current_usage | batch: new_batch_usage}
    
    new_state = %{state |
      resource_pools: new_resource_pools,
      current_usage: new_current_usage
    }
    
    # Set process priority for batch operation
    set_process_priority(self(), @batch_priority_class)
    
    {allocation_id, new_state}
  end

  defp release_allocation(allocation_id, state) do
    # Find allocation in either pool
    case find_allocation(allocation_id, state) do
      {:real_time, allocation} ->
        release_real_time_allocation(allocation_id, allocation, state)
      
      {:batch, allocation} ->
        release_batch_allocation(allocation_id, allocation, state)
      
      :not_found ->
        Logger.warning("Attempted to release unknown allocation: #{allocation_id}")
        state
    end
  end

  defp find_allocation(allocation_id, state) do
    cond do
      Map.has_key?(state.resource_pools.real_time, allocation_id) ->
        {:real_time, Map.get(state.resource_pools.real_time, allocation_id)}
      
      Map.has_key?(state.resource_pools.batch, allocation_id) ->
        {:batch, Map.get(state.resource_pools.batch, allocation_id)}
      
      true ->
        :not_found
    end
  end

  defp release_real_time_allocation(allocation_id, allocation, state) do
    # Remove from pool
    new_real_time_pool = Map.delete(state.resource_pools.real_time, allocation_id)
    new_resource_pools = %{state.resource_pools | real_time: new_real_time_pool}
    
    # Update usage
    current_rt = state.current_usage.real_time
    required = allocation.resources
    
    new_real_time_usage = %{current_rt |
      cpu_percent: current_rt.cpu_percent - required.cpu_percent,
      memory_mb: current_rt.memory_mb - required.memory_mb,
      active_operations: current_rt.active_operations - 1
    }
    
    new_current_usage = %{state.current_usage | real_time: new_real_time_usage}
    
    %{state |
      resource_pools: new_resource_pools,
      current_usage: new_current_usage
    }
  end

  defp release_batch_allocation(allocation_id, allocation, state) do
    # Remove from pool
    new_batch_pool = Map.delete(state.resource_pools.batch, allocation_id)
    new_resource_pools = %{state.resource_pools | batch: new_batch_pool}
    
    # Update usage
    current_batch = state.current_usage.batch
    required = allocation.resources
    
    new_batch_usage = %{current_batch |
      cpu_percent: current_batch.cpu_percent - required.cpu_percent,
      memory_mb: current_batch.memory_mb - required.memory_mb,
      active_jobs: current_batch.active_jobs - 1
    }
    
    new_current_usage = %{state.current_usage | batch: new_batch_usage}
    
    %{state |
      resource_pools: new_resource_pools,
      current_usage: new_current_usage
    }
  end

  defp monitor_and_adjust_resources(state) do
    system_resources = get_system_resources()
    
    # Check if real-time operations are being starved
    if real_time_performance_degraded?(system_resources, state) do
      Logger.warning("Real-time performance degradation detected, throttling batch operations")
      throttle_batch_operations(state)
    else
      state
    end
  end

  defp real_time_performance_degraded?(system_resources, state) do
    # Simple heuristics for performance degradation
    high_cpu_usage = system_resources.cpu_percent > 85
    high_memory_usage = system_resources.memory_percent > 90
    many_real_time_ops = state.current_usage.real_time.active_operations > 30
    
    high_cpu_usage or high_memory_usage or many_real_time_ops
  end

  defp throttle_batch_operations(state) do
    # Reduce batch resource limits temporarily
    reduced_limits = %{state.batch_limits |
      max_cpu_percent: div(state.batch_limits.max_cpu_percent, 2),
      max_memory_mb: div(state.batch_limits.max_memory_mb, 2)
    }
    
    %{state | batch_limits: reduced_limits}
  end

  defp get_system_resources do
    # Get actual system resource usage
    # In a real implementation, this would query system metrics
    %{
      cpu_percent: :rand.uniform(100),
      memory_percent: :rand.uniform(100),
      available_memory_mb: 4096 - :rand.uniform(2048)
    }
  end

  defp set_process_priority(_pid, _priority_class) do
    # In a real implementation, this would set OS-level process priority
    # For now, just log the intent
    :ok
  end

  defp generate_allocation_id do
    "alloc_" <> (:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower))
  end
end
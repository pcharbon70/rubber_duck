defmodule RubberDuck.Registry.ModelRegistry do
  @moduledoc """
  Specialized registry for AI model process management across the distributed cluster.
  Handles model lifecycle, load balancing, health monitoring, and automatic failover
  for LLM and AI model processes with sophisticated routing capabilities.
  """
  require Logger

  alias RubberDuck.Registry.{GlobalRegistry, ProcessMonitor}
  alias RubberDuck.LLM.{Coordinator, TaskRouter}

  @model_prefix "model"
  @health_check_interval 60_000  # 1 minute
  @load_balancing_threshold 0.8

  @doc """
  Registers an AI model process globally with metadata.
  """
  def register_model(model_id, model_config, pid \\ self()) do
    model_name = build_model_name(model_id)
    
    metadata = %{
      model_id: model_id,
      model_config: model_config,
      type: :ai_model,
      registered_at: System.monotonic_time(:millisecond),
      node: node(pid),
      status: :available,
      load: 0,
      request_count: 0,
      success_rate: 1.0,
      avg_response_time: 0,
      capabilities: Map.get(model_config, :capabilities, []),
      provider: Map.get(model_config, :provider, :unknown),
      cost_per_token: Map.get(model_config, :cost_per_token, 0.0),
      max_context_length: Map.get(model_config, :max_context_length, 4096),
      health_status: :healthy,
      last_health_check: System.monotonic_time(:millisecond),
      recovery_module: __MODULE__
    }
    
    case GlobalRegistry.register_persistent(model_name, pid, metadata) do
      :ok ->
        # Configure auto-recovery
        recovery_config = %{
          module: __MODULE__,
          function: :recover_process,
          args: [model_config],
          metadata: metadata
        }
        
        ProcessMonitor.configure_auto_recovery(model_name, recovery_config)
        
        Logger.info("Registered AI model #{model_id} on node #{node(pid)}")
        {:ok, model_name}
      
      error ->
        error
    end
  end

  @doc """
  Finds the best available model for a specific task.
  """
  def find_optimal_model(task_requirements \\ %{}) do
    available_models = list_available_models()
    
    case available_models do
      [] ->
        {:error, :no_models_available}
      
      models ->
        optimal_model = select_optimal_model(models, task_requirements)
        
        case optimal_model do
          nil ->
            {:error, :no_suitable_model}
          
          {model_name, pid, metadata} ->
            # Update load information
            update_model_load(model_name, 1)
            {:ok, {model_name, pid, metadata}}
        end
    end
  end

  @doc """
  Finds models by capability requirements.
  """
  def find_models_by_capabilities(required_capabilities) do
    GlobalRegistry.find_by_metadata(%{type: :ai_model})
    |> Enum.filter(fn {_name, _pid, metadata} ->
      model_capabilities = Map.get(metadata, :capabilities, [])
      Enum.all?(required_capabilities, &(&1 in model_capabilities))
    end)
    |> Enum.filter(fn {_name, pid, metadata} ->
      Process.alive?(pid) and Map.get(metadata, :status) == :available
    end)
  end

  @doc """
  Updates model performance metrics after task completion.
  """
  def update_model_metrics(model_id, metrics) do
    model_name = build_model_name(model_id)
    
    case GlobalRegistry.get_metadata(model_name) do
      {:ok, metadata} ->
        updated_metadata = calculate_updated_metrics(metadata, metrics)
        GlobalRegistry.update_metadata(model_name, updated_metadata)
      
      error ->
        error
    end
  end

  @doc """
  Sets model status (available, busy, maintenance, error).
  """
  def set_model_status(model_id, status) when status in [:available, :busy, :maintenance, :error] do
    model_name = build_model_name(model_id)
    
    case GlobalRegistry.get_metadata(model_name) do
      {:ok, metadata} ->
        updated_metadata = %{metadata | 
          status: status,
          status_updated_at: System.monotonic_time(:millisecond)
        }
        
        GlobalRegistry.update_metadata(model_name, updated_metadata)
        
        Logger.debug("Updated model #{model_id} status to #{status}")
        :ok
      
      error ->
        error
    end
  end

  @doc """
  Performs health check on all registered models.
  """
  def perform_health_checks do
    models = list_all_models()
    
    health_results = Enum.map(models, fn {model_name, pid, metadata} ->
      health_status = check_model_health(pid, metadata)
      
      # Update health status in metadata
      updated_metadata = %{metadata |
        health_status: health_status,
        last_health_check: System.monotonic_time(:millisecond)
      }
      
      GlobalRegistry.update_metadata(model_name, updated_metadata)
      
      {model_name, health_status}
    end)
    
    unhealthy_count = Enum.count(health_results, fn {_name, status} -> status != :healthy end)
    
    if unhealthy_count > 0 do
      Logger.warn("Health check found #{unhealthy_count} unhealthy models")
    end
    
    {:ok, health_results}
  end

  @doc """
  Triggers load balancing across model instances.
  """
  def balance_model_load do
    all_models = Registry.select(RubberDuck.Registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    models_by_type = group_models_by_type(all_models)
    
    rebalancing_actions = Enum.flat_map(models_by_type, fn {model_type, models} ->
      analyze_and_rebalance_model_group(model_type, models)
    end)
    
    if length(rebalancing_actions) > 0 do
      Logger.info("Executing #{length(rebalancing_actions)} load balancing actions")
      execute_rebalancing_actions(rebalancing_actions)
    end
    
    {:ok, rebalancing_actions}
  end

  @doc """
  Gets comprehensive model statistics across the cluster.
  """
  def get_model_stats do
    models = list_all_models()
    
    stats_by_provider = group_models_by_provider(models)
    stats_by_status = group_models_by_status(models)
    stats_by_node = group_models_by_node(models)
    
    %{
      total_models: length(models),
      models_by_provider: stats_by_provider,
      models_by_status: stats_by_status,
      models_by_node: stats_by_node,
      cluster_load: calculate_cluster_load(models),
      avg_response_time: calculate_avg_response_time(models),
      overall_success_rate: calculate_overall_success_rate(models),
      health_summary: calculate_health_summary(models)
    }
  end

  @doc """
  Unregisters a model from the global registry.
  """
  def unregister_model(model_id) do
    model_name = build_model_name(model_id)
    
    case GlobalRegistry.whereis(model_name) do
      nil ->
        {:error, :model_not_found}
      
      _pid ->
        GlobalRegistry.unregister(model_name)
        ProcessMonitor.remove_monitoring(model_name)
        
        Logger.info("Unregistered model #{model_id}")
        :ok
    end
  end

  @doc """
  Recovery function called by ProcessMonitor for failed models.
  """
  def recover_process(model_name, metadata, model_config) do
    model_id = Map.get(metadata, :model_id)
    
    Logger.info("Attempting to recover model: #{model_id}")
    
    # Try to restart the model process
    case start_model_process(model_id, model_config) do
      {:ok, pid} ->
        Logger.info("Successfully recovered model #{model_id}")
        {:ok, pid}
      
      error ->
        Logger.error("Failed to recover model #{model_id}: #{inspect(error)}")
        error
    end
  end

  # Private functions

  defp build_model_name(model_id) do
    String.to_atom("#{@model_prefix}_#{model_id}")
  end

  defp extract_model_id(model_name) when is_atom(model_name) do
    model_name
    |> Atom.to_string()
    |> String.replace_prefix("#{@model_prefix}_", "")
  end

  defp list_available_models do
    GlobalRegistry.find_by_metadata(%{type: :ai_model, status: :available})
    |> Enum.filter(fn {_name, pid, _metadata} ->
      Process.alive?(pid)
    end)
  end

  defp list_all_models do
    GlobalRegistry.find_by_metadata(%{type: :ai_model})
    |> Enum.filter(fn {_name, pid, _metadata} ->
      Process.alive?(pid)
    end)
  end

  defp select_optimal_model(models, task_requirements) do
    # Score models based on various factors
    scored_models = Enum.map(models, fn {name, pid, metadata} ->
      score = calculate_model_score(metadata, task_requirements)
      {name, pid, metadata, score}
    end)
    
    # Select model with highest score
    case Enum.max_by(scored_models, fn {_name, _pid, _metadata, score} -> score end, fn -> nil end) do
      nil -> nil
      {name, pid, metadata, _score} -> {name, pid, metadata}
    end
  end

  defp calculate_model_score(metadata, task_requirements) do
    # Base score factors
    load_score = calculate_load_score(metadata)
    performance_score = calculate_performance_score(metadata)
    health_score = calculate_health_score(metadata)
    capability_score = calculate_capability_score(metadata, task_requirements)
    cost_score = calculate_cost_score(metadata, task_requirements)
    
    # Weighted combination
    load_score * 0.3 +
    performance_score * 0.25 +
    health_score * 0.2 +
    capability_score * 0.15 +
    cost_score * 0.1
  end

  defp calculate_load_score(metadata) do
    current_load = Map.get(metadata, :load, 0)
    # Higher load = lower score
    max(0.0, 1.0 - (current_load / 10.0))
  end

  defp calculate_performance_score(metadata) do
    success_rate = Map.get(metadata, :success_rate, 0.0)
    avg_response_time = Map.get(metadata, :avg_response_time, 5000)
    
    # Normalize response time (lower is better)
    response_time_score = max(0.0, 1.0 - (avg_response_time / 10000))
    
    (success_rate + response_time_score) / 2
  end

  defp calculate_health_score(metadata) do
    case Map.get(metadata, :health_status, :unknown) do
      :healthy -> 1.0
      :degraded -> 0.5
      :unhealthy -> 0.1
      _ -> 0.5
    end
  end

  defp calculate_capability_score(metadata, task_requirements) do
    model_capabilities = Map.get(metadata, :capabilities, [])
    required_capabilities = Map.get(task_requirements, :capabilities, [])
    
    if length(required_capabilities) == 0 do
      1.0
    else
      matching_capabilities = Enum.count(required_capabilities, &(&1 in model_capabilities))
      matching_capabilities / length(required_capabilities)
    end
  end

  defp calculate_cost_score(metadata, task_requirements) do
    cost_per_token = Map.get(metadata, :cost_per_token, 0.0)
    max_cost = Map.get(task_requirements, :max_cost_per_token, 1.0)
    
    if cost_per_token <= max_cost do
      1.0 - (cost_per_token / max_cost)
    else
      0.0
    end
  end

  defp update_model_load(model_name, delta) do
    case GlobalRegistry.get_metadata(model_name) do
      {:ok, metadata} ->
        current_load = Map.get(metadata, :load, 0)
        new_load = max(0, current_load + delta)
        
        updated_metadata = %{metadata | load: new_load}
        GlobalRegistry.update_metadata(model_name, updated_metadata)
      
      error ->
        error
    end
  end

  defp calculate_updated_metrics(metadata, new_metrics) do
    current_count = Map.get(metadata, :request_count, 0)
    new_count = current_count + 1
    
    # Update success rate (exponential moving average)
    current_success_rate = Map.get(metadata, :success_rate, 1.0)
    success = if Map.get(new_metrics, :success, true), do: 1.0, else: 0.0
    new_success_rate = (current_success_rate * 0.9) + (success * 0.1)
    
    # Update average response time (exponential moving average)
    current_avg_time = Map.get(metadata, :avg_response_time, 0)
    new_response_time = Map.get(new_metrics, :response_time, current_avg_time)
    new_avg_time = (current_avg_time * 0.9) + (new_response_time * 0.1)
    
    %{metadata |
      request_count: new_count,
      success_rate: new_success_rate,
      avg_response_time: new_avg_time,
      last_request_at: System.monotonic_time(:millisecond)
    }
  end

  defp check_model_health(pid, metadata) do
    try do
      # Perform basic health check
      case GenServer.call(pid, :health_check, 5000) do
        :ok -> :healthy
        {:ok, :healthy} -> :healthy
        {:ok, :degraded} -> :degraded
        _ -> :unhealthy
      end
    catch
      :exit, {:timeout, _} -> :unhealthy
      :exit, {:noproc, _} -> :unhealthy
      _ -> :unhealthy
    end
  end

  defp group_models_by_type(models) do
    Enum.group_by(models, fn {_name, _pid, metadata} ->
      Map.get(metadata, :model_id, :unknown)
    end)
  end

  defp group_models_by_provider(models) do
    Enum.group_by(models, fn {_name, _pid, metadata} ->
      Map.get(metadata, :provider, :unknown)
    end)
    |> Enum.map(fn {provider, models} -> {provider, length(models)} end)
    |> Enum.into(%{})
  end

  defp group_models_by_status(models) do
    Enum.group_by(models, fn {_name, _pid, metadata} ->
      Map.get(metadata, :status, :unknown)
    end)
    |> Enum.map(fn {status, models} -> {status, length(models)} end)
    |> Enum.into(%{})
  end

  defp group_models_by_node(models) do
    Enum.group_by(models, fn {_name, pid, _metadata} ->
      node(pid)
    end)
    |> Enum.map(fn {node, models} -> {node, length(models)} end)
    |> Enum.into(%{})
  end

  defp analyze_and_rebalance_model_group(_model_type, models) do
    # Simple load balancing: find overloaded nodes
    models_by_node = Enum.group_by(models, fn {_name, pid, _metadata} -> node(pid) end)
    
    Enum.flat_map(models_by_node, fn {node, node_models} ->
      avg_load = calculate_avg_load(node_models)
      
      if avg_load > @load_balancing_threshold do
        suggest_rebalancing_actions(node, node_models)
      else
        []
      end
    end)
  end

  defp calculate_avg_load(models) do
    if length(models) == 0 do
      0.0
    else
      total_load = Enum.reduce(models, 0, fn {_name, _pid, metadata}, acc ->
        acc + Map.get(metadata, :load, 0)
      end)
      
      total_load / length(models)
    end
  end

  defp suggest_rebalancing_actions(overloaded_node, models) do
    # Suggest moving some models to less loaded nodes
    cluster_stats = GlobalRegistry.get_cluster_stats()
    
    case find_least_loaded_node(cluster_stats, overloaded_node) do
      nil -> []
      target_node ->
        # Select models to move (prefer least active ones)
        models_to_move = models
        |> Enum.sort_by(fn {_name, _pid, metadata} -> Map.get(metadata, :load, 0) end)
        |> Enum.take(div(length(models), 2))
        
        Enum.map(models_to_move, fn {name, _pid, metadata} ->
          %{
            action: :migrate_model,
            model_name: name,
            from_node: overloaded_node,
            to_node: target_node,
            reason: :load_balancing
          }
        end)
    end
  end

  defp find_least_loaded_node(cluster_stats, exclude_node) do
    case Map.get(cluster_stats, :processes_by_node, %{}) do
      node_loads when map_size(node_loads) > 1 ->
        node_loads
        |> Enum.reject(fn {node, _load} -> node == exclude_node end)
        |> Enum.min_by(fn {_node, load} -> load end, fn -> nil end)
        |> case do
          nil -> nil
          {node, _load} -> node
        end
      
      _ -> nil
    end
  end

  defp execute_rebalancing_actions(actions) do
    Enum.each(actions, fn action ->
      case action.action do
        :migrate_model ->
          Logger.info("Migrating model #{action.model_name} from #{action.from_node} to #{action.to_node}")
          # In a real implementation, this would trigger model migration
        
        _ ->
          Logger.debug("Unknown rebalancing action: #{inspect(action)}")
      end
    end)
  end

  defp calculate_cluster_load(models) do
    if length(models) == 0 do
      0.0
    else
      total_load = Enum.reduce(models, 0, fn {_name, _pid, metadata}, acc ->
        acc + Map.get(metadata, :load, 0)
      end)
      
      total_load / length(models)
    end
  end

  defp calculate_avg_response_time(models) do
    if length(models) == 0 do
      0.0
    else
      total_time = Enum.reduce(models, 0, fn {_name, _pid, metadata}, acc ->
        acc + Map.get(metadata, :avg_response_time, 0)
      end)
      
      total_time / length(models)
    end
  end

  defp calculate_overall_success_rate(models) do
    if length(models) == 0 do
      0.0
    else
      total_rate = Enum.reduce(models, 0, fn {_name, _pid, metadata}, acc ->
        acc + Map.get(metadata, :success_rate, 0)
      end)
      
      total_rate / length(models)
    end
  end

  defp calculate_health_summary(models) do
    health_counts = Enum.reduce(models, %{healthy: 0, degraded: 0, unhealthy: 0}, fn {_name, _pid, metadata}, acc ->
      health_status = Map.get(metadata, :health_status, :unknown)
      Map.update(acc, health_status, 1, &(&1 + 1))
    end)
    
    total = length(models)
    
    Map.merge(health_counts, %{
      total: total,
      health_ratio: (if total > 0, do: health_counts.healthy / total, else: 0.0)
    })
  end

  defp start_model_process(model_id, model_config) do
    # This would start the actual model process
    # For now, return a placeholder
    {:ok, spawn(fn -> 
      Process.sleep(:infinity)
    end)}
  end
end
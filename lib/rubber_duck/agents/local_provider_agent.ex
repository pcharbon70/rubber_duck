defmodule RubberDuck.Agents.LocalProviderAgent do
  @moduledoc """
  Local model provider agent handling Ollama and other local LLM requests.
  
  This agent manages:
  - Local resource monitoring (CPU, GPU, memory)
  - Model loading and unloading
  - Request queuing for resource management
  - Performance optimization
  - Multi-model support
  
  ## Signals
  
  Inherits all signals from ProviderAgent plus:
  - `load_model`: Load a model into memory
  - `unload_model`: Unload a model from memory
  - `get_resource_status`: Get current resource usage
  - `list_available_models`: List models available locally
  """
  
  use RubberDuck.Agents.ProviderAgent,
    name: "local_provider",
    description: "Local LLM models provider agent (Ollama, llama.cpp, etc.)"
  
  alias RubberDuck.LLM.Providers.Ollama
  alias RubberDuck.LLM.{ProviderConfig, ConfigLoader}
  
  @impl true
  def mount(_params, initial_state) do
    # Load local provider configuration
    config = build_local_config()
    
    # Set local-specific defaults
    state = initial_state
    |> Map.put(:provider_module, Ollama)
    |> Map.put(:provider_config, config)
    |> Map.put(:capabilities, [
      :chat, :code, :offline, :privacy, :customizable,
      :streaming, :embeddings
    ])
    |> Map.update(:rate_limiter, %{}, fn limiter ->
      # Local models have resource-based limits, not API limits
      %{limiter |
        limit: get_concurrent_limit(),
        window: nil  # No time window, just concurrent limit
      }
    end)
    |> Map.update(:circuit_breaker, %{}, fn breaker ->
      %{breaker |
        failure_threshold: 3,  # Lower threshold for local
        timeout: 10_000  # 10 seconds
      }
    end)
    |> Map.put(:loaded_models, %{})  # model_name => load_time
    |> Map.put(:resource_monitor, %{
      cpu_usage: 0.0,
      memory_usage: 0.0,
      gpu_usage: 0.0,
      gpu_memory: 0.0,
      last_check: nil
    })
    |> Map.put(:model_performance, %{})  # model => {avg_tokens_per_sec, requests}
    
    # Start resource monitoring
    schedule_resource_check(state)
    
    {:ok, state}
  end
  
  @impl true
  def handle_signal(agent, %{"type" => "load_model"} = signal) do
    %{"data" => %{"model" => model_name}} = signal
    
    if Map.has_key?(agent.state.loaded_models, model_name) do
      emit_signal("model_loaded", %{
        "model" => model_name,
        "status" => "already_loaded",
        "provider" => "local"
      })
      {:ok, agent}
    else
      # Check resources before loading
      if has_sufficient_resources?(agent, model_name) do
        Task.start(fn ->
          load_model_async(agent.id, model_name)
        end)
        
        {:ok, agent}
      else
        emit_signal("model_load_failed", %{
          "model" => model_name,
          "error" => "Insufficient resources",
          "provider" => "local"
        })
        {:ok, agent}
      end
    end
  end
  
  def handle_signal(agent, %{"type" => "unload_model"} = signal) do
    %{"data" => %{"model" => model_name}} = signal
    
    if Map.has_key?(agent.state.loaded_models, model_name) do
      Task.start(fn ->
        unload_model_async(agent.id, model_name)
      end)
      
      # Remove from loaded models
      agent = update_in(agent.state.loaded_models, &Map.delete(&1, model_name))
      
      {:ok, agent}
    else
      emit_signal("model_unloaded", %{
        "model" => model_name,
        "status" => "not_loaded",
        "provider" => "local"
      })
      {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "get_resource_status"} = _signal) do
    resources = Map.merge(agent.state.resource_monitor, %{
      "loaded_models" => Map.keys(agent.state.loaded_models),
      "model_count" => map_size(agent.state.loaded_models),
      "active_requests" => map_size(agent.state.active_requests),
      "provider" => "local"
    })
    
    emit_signal("resource_status", resources)
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "list_available_models"} = _signal) do
    # Get available models from Ollama or local directory
    models = list_local_models()
    
    emit_signal("available_models", %{
      "models" => models,
      "loaded" => Map.keys(agent.state.loaded_models),
      "provider" => "local"
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "provider_request"} = signal) do
    %{"data" => %{"model" => model}} = signal
    
    # Ensure model is loaded before processing
    if Map.has_key?(agent.state.loaded_models, model) do
      # Check resource availability
      if can_handle_request?(agent) do
        super(agent, signal)
      else
        %{"data" => %{"request_id" => request_id}} = signal
        emit_signal("provider_error", %{
          "request_id" => request_id,
          "error_type" => "resource_constrained",
          "error" => "Local resources are constrained, please retry later"
        })
        {:ok, agent}
      end
    else
      %{"data" => %{"request_id" => request_id}} = signal
      emit_signal("provider_error", %{
        "request_id" => request_id,
        "error_type" => "model_not_loaded",
        "error" => "Model #{model} is not loaded. Please load it first."
      })
      {:ok, agent}
    end
  end
  
  # Delegate other signals to base implementation
  def handle_signal(agent, signal) do
    super(agent, signal)
  end
  
  # GenServer callbacks
  
  @impl true
  def handle_info(:check_resources, agent) do
    # Monitor system resources
    resources = get_system_resources()
    
    agent = put_in(agent.state.resource_monitor, Map.merge(resources, %{
      last_check: System.monotonic_time(:millisecond)
    }))
    
    # Schedule next check
    schedule_resource_check(agent)
    
    # Emit warning if resources are low
    if resources.cpu_usage > 90.0 or resources.memory_usage > 90.0 do
      emit_signal("resource_warning", %{
        "provider" => "local",
        "cpu_usage" => resources.cpu_usage,
        "memory_usage" => resources.memory_usage,
        "severity" => "high"
      })
    end
    
    {:noreply, agent}
  end
  
  def handle_info({:model_performance, model, tokens_per_sec}, agent) do
    # Update model performance metrics
    agent = update_in(agent.state.model_performance[model], fn
      nil -> {tokens_per_sec, 1}
      {avg, count} -> 
        # Running average
        new_avg = (avg * count + tokens_per_sec) / (count + 1)
        {new_avg, count + 1}
    end)
    
    {:noreply, agent}
  end
  
  # Private functions
  
  defp build_local_config do
    base_config = %ProviderConfig{
      name: :ollama,
      adapter: Ollama,
      api_key: nil,  # No API key needed for local
      base_url: System.get_env("OLLAMA_BASE_URL") || "http://localhost:11434",
      models: [],  # Will be populated dynamically
      priority: 3,  # Lower priority than cloud providers
      rate_limit: nil,  # No rate limit, resource-based
      max_retries: 2,  # Fewer retries for local
      timeout: 300_000,  # 5 minutes for large models
      headers: %{},
      options: [
        num_gpu: System.get_env("OLLAMA_NUM_GPU") || "1",
        num_thread: System.get_env("OLLAMA_NUM_THREAD") || "4"
      ]
    }
    
    # Apply any runtime overrides
    ConfigLoader.load_provider_config(:ollama)
    |> case do
      nil -> base_config
      config -> struct(ProviderConfig, config)
    end
  end
  
  defp get_concurrent_limit do
    # Base on available resources
    cpu_count = System.schedulers_online()
    memory_gb = get_available_memory_gb()
    
    # Simple heuristic: 1 concurrent request per 4 CPU cores or 8GB RAM
    min(
      div(cpu_count, 4),
      div(memory_gb, 8)
    ) |> max(1)
  end
  
  defp schedule_resource_check(_state) do
    Process.send_after(self(), :check_resources, 5_000)  # Every 5 seconds
  end
  
  defp has_sufficient_resources?(_agent, model_name) do
    # Check if we have enough resources to load the model
    model_size = estimate_model_size(model_name)
    available_memory = get_available_memory_gb()
    
    # Need at least 2x model size in available memory
    available_memory > model_size * 2
  end
  
  defp can_handle_request?(agent) do
    # Check current resource usage
    resources = agent.state.resource_monitor
    
    resources.cpu_usage < 80.0 && 
    resources.memory_usage < 85.0 &&
    map_size(agent.state.active_requests) < agent.state.max_concurrent_requests
  end
  
  defp load_model_async(agent_id, model_name) do
    start_time = System.monotonic_time(:millisecond)
    
    # TODO: Implement RubberDuck.LLM.Providers.Ollama.load_model/1
    # This function should handle loading models into Ollama
    case Ollama.load_model(model_name) do
      :ok ->
        load_time = System.monotonic_time(:millisecond) - start_time
        
        # Update agent state
        GenServer.cast(agent_id, {:model_loaded, model_name, load_time})
        
        emit_signal("model_loaded", %{
          "model" => model_name,
          "status" => "success",
          "load_time_ms" => load_time,
          "provider" => "local"
        })
        
      {:error, reason} ->
        emit_signal("model_load_failed", %{
          "model" => model_name,
          "error" => inspect(reason),
          "provider" => "local"
        })
    end
  end
  
  defp unload_model_async(_agent_id, model_name) do
    # TODO: Implement RubberDuck.LLM.Providers.Ollama.unload_model/1
    # This function should handle unloading models from Ollama
    case Ollama.unload_model(model_name) do
      :ok ->
        emit_signal("model_unloaded", %{
          "model" => model_name,
          "status" => "success",
          "provider" => "local"
        })
        
      {:error, reason} ->
        emit_signal("model_unload_failed", %{
          "model" => model_name,
          "error" => inspect(reason),
          "provider" => "local"
        })
    end
  end
  
  defp list_local_models do
    # TODO: Implement RubberDuck.LLM.Providers.Ollama.list_models/0
    # This function should return a list of available models in Ollama
    case Ollama.list_models() do
      {:ok, models} -> models
      {:error, _} -> []
    end
  end
  
  defp estimate_model_size(model_name) do
    # Rough estimates in GB
    cond do
      String.contains?(model_name, "70b") -> 40
      String.contains?(model_name, "34b") -> 20
      String.contains?(model_name, "13b") -> 8
      String.contains?(model_name, "7b") -> 4
      String.contains?(model_name, "3b") -> 2
      true -> 4  # Default 4GB
    end
  end
  
  defp get_system_resources do
    # In production, would use actual system monitoring
    %{
      cpu_usage: :rand.uniform() * 100,  # Mock CPU usage
      memory_usage: :rand.uniform() * 100,  # Mock memory usage
      gpu_usage: :rand.uniform() * 100,  # Mock GPU usage
      gpu_memory: :rand.uniform() * 100  # Mock GPU memory
    }
  end
  
  defp get_available_memory_gb do
    # In production, would check actual available memory
    16  # Mock 16GB available
  end
  
  # Note: Performance tracking is handled via the model_performance message in handle_info
  
  # Build status report with local-specific info
  def build_status_report(agent) do
    base_report = RubberDuck.Agents.ProviderAgent.build_status_report(agent)
    
    Map.merge(base_report, %{
      "loaded_models" => Map.keys(agent.state.loaded_models),
      "resource_monitor" => agent.state.resource_monitor,
      "model_performance" => format_performance_metrics(agent.state.model_performance),
      "concurrent_limit" => agent.state.max_concurrent_requests,
      "offline_capable" => true
    })
  end
  
  defp format_performance_metrics(perf_map) do
    Map.new(perf_map, fn {model, {avg_tps, count}} ->
      {model, %{
        "avg_tokens_per_sec" => Float.round(avg_tps, 2),
        "requests_processed" => count
      }}
    end)
  end
  
  # GenServer cast handlers
  
  def handle_cast({:model_loaded, model_name, load_time}, agent) do
    agent = update_in(agent.state.loaded_models, &Map.put(&1, model_name, %{
      loaded_at: System.monotonic_time(:millisecond),
      load_time_ms: load_time
    }))
    
    # Update available models in config
    models = Map.keys(agent.state.loaded_models)
    agent = put_in(agent.state.provider_config.models, models)
    
    {:noreply, agent}
  end
end
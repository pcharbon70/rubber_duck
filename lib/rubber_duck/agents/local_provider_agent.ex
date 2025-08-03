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
    description: "Local LLM models provider agent (Ollama, llama.cpp, etc.)",
    actions: [
      RubberDuck.Jido.Actions.Provider.Local.LoadModelAction,
      RubberDuck.Jido.Actions.Provider.Local.UnloadModelAction,
      RubberDuck.Jido.Actions.Provider.Local.GetResourceStatusAction,
      RubberDuck.Jido.Actions.Provider.Local.ListAvailableModelsAction,
      RubberDuck.Jido.Actions.Provider.Local.ModelSwitchingAction,
      RubberDuck.Jido.Actions.Provider.Local.PerformanceOptimizationAction
    ]
  
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
    
    # Resource monitoring is now handled through Actions
    {:ok, state}
  end
  
  # Local provider specific validation
  @impl true
  def on_before_run(agent) do
    # This could be used for pre-run validation if needed
    {:ok, agent}
  end
  
  # Resource monitoring is now handled through Actions and periodic agent runs
  # Model performance tracking is handled through Actions
  # Model loading is handled through LoadModelAction
  
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
  
  
  
  defp can_handle_request?(agent) do
    # Check current resource usage
    resources = agent.state.resource_monitor
    
    resources.cpu_usage < 80.0 && 
    resources.memory_usage < 85.0 &&
    map_size(agent.state.active_requests) < agent.state.max_concurrent_requests
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
  
end
defmodule RubberDuck.LLMAbstraction.ProviderRegistry do
  @moduledoc """
  Registry for managing LLM providers.
  
  This GenServer maintains a registry of available providers, their configurations,
  health status, and capabilities. It supports dynamic provider registration,
  capability-based lookup, and health monitoring.
  """

  use GenServer
  require Logger

  alias RubberDuck.LLMAbstraction.{Provider, Capability, CapabilityMatcher}

  defstruct providers: %{}, health_checks: %{}, metadata_cache: %{}

  @type provider_info :: %{
    module: module(),
    config: map(),
    state: term(),
    capabilities: [Capability.t()],
    health: :healthy | :degraded | :unhealthy,
    last_health_check: DateTime.t() | nil,
    metadata: map()
  }

  @health_check_interval :timer.minutes(1)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new provider with the registry.
  """
  def register_provider(name, module, config) when is_atom(name) and is_atom(module) do
    GenServer.call(__MODULE__, {:register_provider, name, module, config})
  end

  @doc """
  Unregister a provider from the registry.
  """
  def unregister_provider(name) do
    GenServer.call(__MODULE__, {:unregister_provider, name})
  end

  @doc """
  Get information about a specific provider.
  """
  def get_provider(name) do
    GenServer.call(__MODULE__, {:get_provider, name})
  end

  @doc """
  List all registered providers.
  """
  def list_providers do
    GenServer.call(__MODULE__, :list_providers)
  end

  @doc """
  Find providers that satisfy the given requirements.
  """
  def find_providers(requirements) do
    GenServer.call(__MODULE__, {:find_providers, requirements})
  end

  @doc """
  Execute a chat completion with a specific provider.
  """
  def chat(provider_name, messages, opts \\ []) do
    GenServer.call(__MODULE__, {:chat, provider_name, messages, opts}, :infinity)
  end

  @doc """
  Execute a text completion with a specific provider.
  """
  def complete(provider_name, prompt, opts \\ []) do
    GenServer.call(__MODULE__, {:complete, provider_name, prompt, opts}, :infinity)
  end

  @doc """
  Generate embeddings with a specific provider.
  """
  def embed(provider_name, input, opts \\ []) do
    GenServer.call(__MODULE__, {:embed, provider_name, input, opts}, :infinity)
  end

  @doc """
  Get the health status of a provider.
  """
  def health_status(provider_name) do
    GenServer.call(__MODULE__, {:health_status, provider_name})
  end

  @doc """
  Manually trigger a health check for a provider.
  """
  def check_health(provider_name) do
    GenServer.cast(__MODULE__, {:check_health, provider_name})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic health checks
    schedule_health_checks()
    
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:register_provider, name, module, config}, _from, state) do
    case validate_and_init_provider(module, config) do
      {:ok, provider_state, capabilities, metadata} ->
        provider_info = %{
          module: module,
          config: config,
          state: provider_state,
          capabilities: capabilities,
          health: :healthy,
          last_health_check: DateTime.utc_now(),
          metadata: metadata
        }
        
        new_providers = Map.put(state.providers, name, provider_info)
        new_state = %{state | providers: new_providers}
        
        Logger.info("Registered provider #{name} with module #{module}")
        {:reply, :ok, new_state}
        
      {:error, reason} = error ->
        Logger.error("Failed to register provider #{name}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:unregister_provider, name}, _from, state) do
    case Map.get(state.providers, name) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      provider_info ->
        # Clean up provider
        try do
          provider_info.module.terminate(provider_info.state)
        rescue
          error ->
            Logger.warning("Error terminating provider #{name}: #{inspect(error)}")
        end
        
        new_providers = Map.delete(state.providers, name)
        new_state = %{state | providers: new_providers}
        
        Logger.info("Unregistered provider #{name}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:get_provider, name}, _from, state) do
    case Map.get(state.providers, name) do
      nil -> {:reply, {:error, :not_found}, state}
      info -> {:reply, {:ok, sanitize_provider_info(info)}, state}
    end
  end

  @impl true
  def handle_call(:list_providers, _from, state) do
    providers = state.providers
    |> Enum.map(fn {name, info} -> 
      {name, sanitize_provider_info(info)}
    end)
    |> Map.new()
    
    {:reply, providers, state}
  end

  @impl true
  def handle_call({:find_providers, requirements}, _from, state) do
    provider_capabilities = state.providers
    |> Enum.map(fn {name, info} -> 
      {name, info.capabilities}
    end)
    
    matching_providers = CapabilityMatcher.find_matching_providers(
      requirements, 
      provider_capabilities
    )
    
    {:reply, matching_providers, state}
  end

  @impl true
  def handle_call({:chat, provider_name, messages, opts}, _from, state) do
    case Map.get(state.providers, provider_name) do
      nil ->
        {:reply, {:error, :provider_not_found}, state}
        
      %{health: :unhealthy} ->
        {:reply, {:error, :provider_unhealthy}, state}
        
      provider_info ->
        start_time = System.monotonic_time(:millisecond)
        
        result = provider_info.module.chat(
          messages, 
          provider_info.state, 
          opts
        )
        
        latency = System.monotonic_time(:millisecond) - start_time
        
        case result do
          {:ok, response, new_provider_state} ->
            # Update provider state
            new_info = %{provider_info | state: new_provider_state}
            new_providers = Map.put(state.providers, provider_name, new_info)
            new_state = %{state | providers: new_providers}
            
            # Add latency to response
            enhanced_response = Map.put(response, :latency_ms, latency)
            
            {:reply, {:ok, enhanced_response}, new_state}
            
          {:error, reason, new_provider_state} ->
            # Update provider state even on error
            new_info = %{provider_info | state: new_provider_state}
            new_providers = Map.put(state.providers, provider_name, new_info)
            new_state = %{state | providers: new_providers}
            
            {:reply, {:error, reason}, new_state}
        end
    end
  end

  @impl true
  def handle_call({:complete, provider_name, prompt, opts}, _from, state) do
    case Map.get(state.providers, provider_name) do
      nil ->
        {:reply, {:error, :provider_not_found}, state}
        
      %{health: :unhealthy} ->
        {:reply, {:error, :provider_unhealthy}, state}
        
      provider_info ->
        result = provider_info.module.complete(
          prompt, 
          provider_info.state, 
          opts
        )
        
        case result do
          {:ok, response, new_provider_state} ->
            new_info = %{provider_info | state: new_provider_state}
            new_providers = Map.put(state.providers, provider_name, new_info)
            new_state = %{state | providers: new_providers}
            
            {:reply, {:ok, response}, new_state}
            
          {:error, reason, new_provider_state} ->
            new_info = %{provider_info | state: new_provider_state}
            new_providers = Map.put(state.providers, provider_name, new_info)
            new_state = %{state | providers: new_providers}
            
            {:reply, {:error, reason}, new_state}
        end
    end
  end

  @impl true
  def handle_call({:embed, provider_name, input, opts}, _from, state) do
    case Map.get(state.providers, provider_name) do
      nil ->
        {:reply, {:error, :provider_not_found}, state}
        
      %{health: :unhealthy} ->
        {:reply, {:error, :provider_unhealthy}, state}
        
      provider_info ->
        if function_exported?(provider_info.module, :embed, 3) do
          result = provider_info.module.embed(
            input, 
            provider_info.state, 
            opts
          )
          
          case result do
            {:ok, embeddings, new_provider_state} ->
              new_info = %{provider_info | state: new_provider_state}
              new_providers = Map.put(state.providers, provider_name, new_info)
              new_state = %{state | providers: new_providers}
              
              {:reply, {:ok, embeddings}, new_state}
              
            {:error, reason, new_provider_state} ->
              new_info = %{provider_info | state: new_provider_state}
              new_providers = Map.put(state.providers, provider_name, new_info)
              new_state = %{state | providers: new_providers}
              
              {:reply, {:error, reason}, new_state}
          end
        else
          {:reply, {:error, :not_supported}, state}
        end
    end
  end

  @impl true
  def handle_call({:health_status, provider_name}, _from, state) do
    case Map.get(state.providers, provider_name) do
      nil -> {:reply, {:error, :not_found}, state}
      info -> {:reply, {:ok, info.health}, state}
    end
  end

  @impl true
  def handle_cast({:check_health, provider_name}, state) do
    case Map.get(state.providers, provider_name) do
      nil ->
        {:noreply, state}
        
      provider_info ->
        new_health = perform_health_check(provider_info)
        
        new_info = %{provider_info | 
          health: new_health,
          last_health_check: DateTime.utc_now()
        }
        
        new_providers = Map.put(state.providers, provider_name, new_info)
        new_state = %{state | providers: new_providers}
        
        if new_health != provider_info.health do
          Logger.info("Provider #{provider_name} health changed: #{provider_info.health} -> #{new_health}")
        end
        
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:perform_health_checks, state) do
    # Check health of all providers
    Enum.each(state.providers, fn {name, _} ->
      GenServer.cast(self(), {:check_health, name})
    end)
    
    # Schedule next check
    schedule_health_checks()
    
    {:noreply, state}
  end

  # Private Functions

  defp validate_and_init_provider(module, config) do
    with :ok <- ensure_provider_behaviour(module),
         :ok <- module.validate_config(config),
         {:ok, state} <- module.init(config) do
      
      capabilities = module.capabilities(state)
      metadata = module.metadata()
      
      {:ok, state, capabilities, metadata}
    end
  end

  defp ensure_provider_behaviour(module) do
    if provider_module?(module) do
      :ok
    else
      {:error, :invalid_provider_module}
    end
  end

  defp provider_module?(module) do
    # Check if module implements the Provider behaviour
    behaviours = module.module_info(:attributes)
    |> Keyword.get(:behaviour, [])
    
    Provider in behaviours
  end

  defp sanitize_provider_info(info) do
    # Remove internal state from external responses
    Map.drop(info, [:state])
  end

  defp perform_health_check(provider_info) do
    try do
      provider_info.module.health_check(provider_info.state)
    rescue
      _ -> :unhealthy
    end
  end

  defp schedule_health_checks do
    Process.send_after(self(), :perform_health_checks, @health_check_interval)
  end
end
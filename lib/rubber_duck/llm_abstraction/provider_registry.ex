defmodule RubberDuck.LLMAbstraction.ProviderRegistry do
  @moduledoc """
  Comprehensive provider registry for LLM provider discovery and management.
  
  This registry manages the lifecycle of LLM providers, including registration,
  discovery, health monitoring, and capability-based routing. It provides a
  centralized location to manage all available LLM providers in the system.
  
  ## Features
  
  - Provider registration and unregistration
  - Capability-based provider discovery
  - Health monitoring and status tracking
  - Load balancing support
  - Provider metadata management
  - Automatic provider initialization
  
  ## Usage
  
      # Register a provider
      :ok = ProviderRegistry.register_provider(:openai, OpenAIProvider, config)
      
      # Find providers by capability
      providers = ProviderRegistry.find_providers_by_capability(:chat_completion)
      
      # Get provider for request
      {:ok, provider_pid} = ProviderRegistry.get_provider(:openai)
  """

  use GenServer
  require Logger

  alias RubberDuck.LLMAbstraction.{Config, Capability, CapabilityMatcher}

  @registry_name __MODULE__
  @provider_supervisor RubberDuck.LLMAbstraction.ProviderSupervisor

  # Provider registry state
  defstruct [
    providers: %{},
    provider_pids: %{},
    health_status: %{},
    capabilities: %{},
    statistics: %{},
    config: %{}
  ]

  @type provider_id :: atom()
  @type provider_module :: module()
  @type provider_info :: %{
    id: provider_id(),
    module: provider_module(),
    pid: pid() | nil,
    config: Config.t(),
    capabilities: [Capability.t()],
    health: :healthy | :degraded | :unhealthy | :unknown,
    statistics: map(),
    registered_at: DateTime.t(),
    last_health_check: DateTime.t() | nil
  }

  ## Public API

  @doc """
  Start the provider registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @registry_name)
  end

  @doc """
  Register a new LLM provider.
  
  ## Parameters
    - provider_id: Unique identifier for the provider
    - provider_module: Module implementing Provider behavior
    - config: Provider configuration
  """
  @spec register_provider(provider_id(), provider_module(), map()) :: :ok | {:error, term()}
  def register_provider(provider_id, provider_module, config) do
    GenServer.call(@registry_name, {:register_provider, provider_id, provider_module, config})
  end

  @doc """
  Unregister a provider.
  """
  @spec unregister_provider(provider_id()) :: :ok | {:error, term()}
  def unregister_provider(provider_id) do
    GenServer.call(@registry_name, {:unregister_provider, provider_id})
  end

  @doc """
  Get a specific provider by ID.
  """
  @spec get_provider(provider_id()) :: {:ok, pid()} | {:error, term()}
  def get_provider(provider_id) do
    GenServer.call(@registry_name, {:get_provider, provider_id})
  end

  @doc """
  List all registered providers.
  """
  @spec list_providers() :: [provider_info()]
  def list_providers do
    GenServer.call(@registry_name, :list_providers)
  end

  @doc """
  Find providers that support specific capabilities.
  """
  @spec find_providers_by_capability([Capability.t()] | Capability.t()) :: [provider_info()]
  def find_providers_by_capability(capabilities) when is_list(capabilities) do
    GenServer.call(@registry_name, {:find_providers_by_capability, capabilities})
  end

  def find_providers_by_capability(capability) do
    find_providers_by_capability([capability])
  end

  @doc """
  Find providers matching specific requirements.
  """
  @spec find_providers(map()) :: [provider_info()]
  def find_providers(requirements \\ %{}) do
    GenServer.call(@registry_name, {:find_providers, requirements})
  end

  @doc """
  Get the best provider for specific requirements.
  """
  @spec get_best_provider([Capability.t()], map()) :: {:ok, provider_info()} | {:error, term()}
  def get_best_provider(capabilities, criteria \\ %{}) do
    GenServer.call(@registry_name, {:get_best_provider, capabilities, criteria})
  end

  @doc """
  Check the health status of a provider.
  """
  @spec health_status(provider_id()) :: {:ok, atom()} | {:error, term()}
  def health_status(provider_id) do
    GenServer.call(@registry_name, {:health_status, provider_id})
  end

  @doc """
  Get registry statistics.
  """
  @spec get_statistics() :: map()
  def get_statistics do
    GenServer.call(@registry_name, :get_statistics)
  end

  @doc """
  Refresh provider capabilities and health status.
  """
  @spec refresh_provider(provider_id()) :: :ok | {:error, term()}
  def refresh_provider(provider_id) do
    GenServer.cast(@registry_name, {:refresh_provider, provider_id})
  end

  @doc """
  Initialize providers from configuration.
  """
  @spec load_providers_from_config(map()) :: :ok
  def load_providers_from_config(config) do
    GenServer.cast(@registry_name, {:load_providers_from_config, config})
  end

  ## GenServer Implementation

  @impl GenServer
  def init(opts) do
    # Schedule periodic health checks
    schedule_health_checks()
    
    state = %__MODULE__{
      config: Keyword.get(opts, :config, %{})
    }
    
    Logger.info("Provider registry started")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register_provider, provider_id, provider_module, config}, _from, state) do
    case register_provider_internal(provider_id, provider_module, config, state) do
      {:ok, new_state} ->
        Logger.info("Registered provider: #{provider_id}")
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        Logger.error("Failed to register provider #{provider_id}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:unregister_provider, provider_id}, _from, state) do
    case unregister_provider_internal(provider_id, state) do
      {:ok, new_state} ->
        Logger.info("Unregistered provider: #{provider_id}")
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_provider, provider_id}, _from, state) do
    case Map.get(state.provider_pids, provider_id) do
      nil -> {:reply, {:error, :provider_not_found}, state}
      pid when is_pid(pid) -> 
        if Process.alive?(pid) do
          {:reply, {:ok, pid}, state}
        else
          {:reply, {:error, :provider_dead}, state}
        end
    end
  end

  @impl GenServer
  def handle_call(:list_providers, _from, state) do
    providers = Map.values(state.providers)
    {:reply, providers, state}
  end

  @impl GenServer
  def handle_call({:find_providers_by_capability, capabilities}, _from, state) do
    matching_providers = find_providers_by_capability_internal(capabilities, state)
    {:reply, matching_providers, state}
  end

  @impl GenServer
  def handle_call({:find_providers, requirements}, _from, state) do
    matching_providers = find_providers_internal(requirements, state)
    {:reply, matching_providers, state}
  end

  @impl GenServer
  def handle_call({:get_best_provider, capabilities, criteria}, _from, state) do
    case get_best_provider_internal(capabilities, criteria, state) do
      {:ok, provider} -> {:reply, {:ok, provider}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:health_status, provider_id}, _from, state) do
    case Map.get(state.health_status, provider_id) do
      nil -> {:reply, {:error, :provider_not_found}, state}
      status -> {:reply, {:ok, status}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_statistics, _from, state) do
    stats = %{
      total_providers: map_size(state.providers),
      active_providers: count_active_providers(state),
      healthy_providers: count_healthy_providers(state),
      provider_statistics: state.statistics
    }
    {:reply, stats, state}
  end

  @impl GenServer
  def handle_cast({:refresh_provider, provider_id}, state) do
    new_state = refresh_provider_internal(provider_id, state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:load_providers_from_config, config}, state) do
    new_state = load_providers_from_config_internal(config, state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:perform_health_checks, state) do
    new_state = perform_health_checks(state)
    schedule_health_checks()
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.warning("Provider process died: #{inspect(pid)}, reason: #{inspect(reason)}")
    new_state = handle_provider_death(pid, state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal Implementation

  defp register_provider_internal(provider_id, provider_module, config, state) do
    with :ok <- validate_provider_module(provider_module),
         {:ok, validated_config} <- validate_provider_config(provider_module, config),
         {:ok, pid} <- start_provider(provider_module, validated_config),
         {:ok, capabilities} <- get_provider_capabilities(pid),
         :ok <- check_provider_health(pid) do
      
      # Monitor the provider process
      Process.monitor(pid)
      
      provider_info = %{
        id: provider_id,
        module: provider_module,
        pid: pid,
        config: validated_config,
        capabilities: capabilities,
        health: :healthy,
        statistics: %{},
        registered_at: DateTime.utc_now(),
        last_health_check: DateTime.utc_now()
      }
      
      new_state = state
      |> put_in([Access.key(:providers), provider_id], provider_info)
      |> put_in([Access.key(:provider_pids), provider_id], pid)
      |> put_in([Access.key(:health_status), provider_id], :healthy)
      |> put_in([Access.key(:capabilities), provider_id], capabilities)
      |> put_in([Access.key(:statistics), provider_id], %{})
      
      {:ok, new_state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp unregister_provider_internal(provider_id, state) do
    case Map.get(state.providers, provider_id) do
      nil ->
        {:error, :provider_not_found}
      
      provider_info ->
        # Terminate the provider if it's running
        if provider_info.pid && Process.alive?(provider_info.pid) do
          GenServer.call(provider_info.pid, :terminate)
        end
        
        new_state = state
        |> update_in([Access.key(:providers)], &Map.delete(&1, provider_id))
        |> update_in([Access.key(:provider_pids)], &Map.delete(&1, provider_id))
        |> update_in([Access.key(:health_status)], &Map.delete(&1, provider_id))
        |> update_in([Access.key(:capabilities)], &Map.delete(&1, provider_id))
        |> update_in([Access.key(:statistics)], &Map.delete(&1, provider_id))
        
        {:ok, new_state}
    end
  end

  defp find_providers_by_capability_internal(capabilities, state) do
    provider_capabilities = state.capabilities
    
    CapabilityMatcher.find_matching_providers(capabilities, provider_capabilities)
    |> Enum.map(fn provider_id -> Map.get(state.providers, provider_id) end)
    |> Enum.filter(&(&1 != nil))
  end

  defp find_providers_internal(requirements, state) do
    health_filter = Map.get(requirements, :health, [:healthy, :degraded])
    capability_requirements = Map.get(requirements, :capabilities, [])
    
    state.providers
    |> Map.values()
    |> Enum.filter(fn provider ->
      provider.health in health_filter and
      matches_capability_requirements?(provider.capabilities, capability_requirements)
    end)
  end

  defp get_best_provider_internal(capabilities, criteria, state) do
    candidates = find_providers_by_capability_internal(capabilities, state)
    
    case candidates do
      [] ->
        {:error, :no_providers_available}
      
      providers ->
        strategy = Map.get(criteria, :strategy, :health_weighted)
        best_provider = select_best_provider(providers, strategy)
        {:ok, best_provider}
    end
  end

  defp refresh_provider_internal(provider_id, state) do
    case Map.get(state.providers, provider_id) do
      nil ->
        state
      
      provider_info ->
        case provider_info.pid do
          nil ->
            state
          
          pid when is_pid(pid) ->
            if Process.alive?(pid) do
              # Refresh capabilities and health
              capabilities = get_provider_capabilities(pid) |> elem(1)
              health = check_provider_health(pid) |> health_to_status()
              
              updated_provider = %{provider_info |
                capabilities: capabilities,
                health: health,
                last_health_check: DateTime.utc_now()
              }
              
              state
              |> put_in([Access.key(:providers), provider_id], updated_provider)
              |> put_in([Access.key(:health_status), provider_id], health)
              |> put_in([Access.key(:capabilities), provider_id], capabilities)
            else
              state
            end
        end
    end
  end

  defp load_providers_from_config_internal(config, state) do
    Enum.reduce(config, state, fn {provider_id, provider_config}, acc_state ->
      provider_type = Map.get(provider_config, :provider_type)
      provider_module = get_provider_module(provider_type)
      
      if provider_module do
        case register_provider_internal(provider_id, provider_module, provider_config, acc_state) do
          {:ok, new_state} -> new_state
          {:error, reason} ->
            Logger.error("Failed to load provider #{provider_id} from config: #{inspect(reason)}")
            acc_state
        end
      else
        Logger.error("Unknown provider type: #{provider_type}")
        acc_state
      end
    end)
  end

  defp perform_health_checks(state) do
    Enum.reduce(state.providers, state, fn {provider_id, _provider_info}, acc_state ->
      refresh_provider_internal(provider_id, acc_state)
    end)
  end

  defp handle_provider_death(pid, state) do
    # Find the provider by PID
    case Enum.find(state.provider_pids, fn {_id, provider_pid} -> provider_pid == pid end) do
      {provider_id, _pid} ->
        Logger.warning("Provider #{provider_id} died, marking as unhealthy")
        
        state
        |> put_in([Access.key(:health_status), provider_id], :unhealthy)
        |> put_in([Access.key(:provider_pids), provider_id], nil)
        |> update_in([Access.key(:providers), provider_id], fn provider ->
          %{provider | pid: nil, health: :unhealthy}
        end)
      
      nil ->
        state
    end
  end

  # Helper Functions

  defp validate_provider_module(module) do
    if function_exported?(module, :behaviour_info, 1) do
      behaviours = module.behaviour_info(:callbacks)
      required_callbacks = RubberDuck.LLMAbstraction.Provider.behaviour_info(:callbacks)
      
      if Enum.all?(required_callbacks, &(&1 in behaviours)) do
        :ok
      else
        {:error, :invalid_provider_module}
      end
    else
      {:error, :invalid_provider_module}
    end
  end

  defp validate_provider_config(provider_module, config) do
    case provider_module.validate_config(config) do
      :ok -> {:ok, config}
      {:error, reason} -> {:error, {:config_validation_failed, reason}}
    end
  end

  defp start_provider(provider_module, config) do
    case provider_module.init(config) do
      {:ok, state} ->
        # Start the provider under the supervisor
        pid = spawn_link(fn -> provider_loop(provider_module, state) end)
        {:ok, pid}
      
      {:error, reason} ->
        {:error, {:provider_start_failed, reason}}
    end
  end

  defp provider_loop(module, state) do
    receive do
      {:call, from, message} ->
        try do
          case handle_provider_call(module, message, state) do
            {:reply, reply, new_state} ->
              send(from, {:reply, reply})
              provider_loop(module, new_state)
            
            {:stop, reason} ->
              module.terminate(state)
              exit(reason)
          end
        rescue
          error ->
            send(from, {:error, error})
            provider_loop(module, state)
        end
      
      :terminate ->
        module.terminate(state)
        exit(:normal)
      
      _ ->
        provider_loop(module, state)
    end
  end

  defp handle_provider_call(module, :capabilities, state) do
    capabilities = module.capabilities(state)
    {:reply, capabilities, state}
  end

  defp handle_provider_call(module, :health_status, state) do
    health = module.health_check(state)
    {:reply, health, state}
  end

  defp handle_provider_call(module, :statistics, state) do
    # Extract statistics from state if available
    statistics = Map.get(state, :statistics, %{})
    {:reply, statistics, state}
  end

  defp handle_provider_call(module, :terminate, state) do
    module.terminate(state)
    {:stop, :normal}
  end

  defp handle_provider_call(_module, message, state) do
    {:reply, {:error, {:unknown_message, message}}, state}
  end

  defp get_provider_capabilities(pid) do
    try do
      send(pid, {:call, self(), :capabilities})
      receive do
        {:reply, capabilities} -> {:ok, capabilities}
      after
        5000 -> {:error, :timeout}
      end
    catch
      _ -> {:error, :communication_failed}
    end
  end

  defp check_provider_health(pid) do
    try do
      send(pid, {:call, self(), :health_status})
      receive do
        {:reply, health} -> health
      after
        5000 -> :unknown
      end
    catch
      _ -> :unknown
    end
  end

  defp health_to_status(:healthy), do: :healthy
  defp health_to_status(:degraded), do: :degraded
  defp health_to_status(:unhealthy), do: :unhealthy
  defp health_to_status(_), do: :unknown

  defp matches_capability_requirements?(provider_capabilities, requirements) do
    Enum.all?(requirements, fn requirement ->
      Enum.any?(provider_capabilities, fn capability ->
        Capability.matches?(capability, requirement)
      end)
    end)
  end

  defp select_best_provider(providers, :health_weighted) do
    # Prefer healthy providers, then degraded, avoid unhealthy
    healthy = Enum.filter(providers, &(&1.health == :healthy))
    if not Enum.empty?(healthy) do
      Enum.random(healthy)
    else
      degraded = Enum.filter(providers, &(&1.health == :degraded))
      if not Enum.empty?(degraded) do
        Enum.random(degraded)
      else
        Enum.random(providers)
      end
    end
  end

  defp select_best_provider(providers, :round_robin) do
    # Simple round-robin selection
    Enum.random(providers)
  end

  defp select_best_provider(providers, _strategy) do
    # Default to random selection
    Enum.random(providers)
  end

  defp count_active_providers(state) do
    state.provider_pids
    |> Map.values()
    |> Enum.count(&(is_pid(&1) and Process.alive?(&1)))
  end

  defp count_healthy_providers(state) do
    state.health_status
    |> Map.values()
    |> Enum.count(&(&1 == :healthy))
  end

  defp get_provider_module(:openai), do: RubberDuck.LLMAbstraction.Providers.OpenAIProvider
  defp get_provider_module(:anthropic), do: RubberDuck.LLMAbstraction.Providers.AnthropicProvider
  defp get_provider_module(:local), do: RubberDuck.LLMAbstraction.Providers.LocalProvider
  defp get_provider_module(_), do: nil

  defp schedule_health_checks do
    Process.send_after(self(), :perform_health_checks, 30_000)  # Every 30 seconds
  end
end
defmodule RubberDuck.Jido.SignalRouter.Config do
  @moduledoc """
  Configuration management for the SignalRouter.
  
  This module handles:
  - Dynamic route registration and management
  - Route priority and conflict resolution
  - Configuration persistence
  - Runtime route updates
  
  Routes map CloudEvent types to actions with optional parameter extractors.
  """
  
  use GenServer
  require Logger
  
  @table_name :rubber_duck_signal_routes
  
  @type route :: {
    priority :: integer(),
    action_module :: module(),
    param_extractor :: (map() -> map()),
    metadata :: map()
  }
  
  @type route_pattern :: String.t()
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a route mapping a signal type pattern to an action.
  
  ## Options
  - `:priority` - Higher priority routes are evaluated first (default: 50)
  - `:param_extractor` - Function to extract action params from CloudEvent
  - `:metadata` - Additional metadata for the route
  - `:override` - Allow overriding existing exact match (default: false)
  
  ## Examples
  
      register_route("com.example.user.created", UserCreatedAction,
        priority: 100,
        param_extractor: &extract_user_params/1
      )
      
      # Pattern matching with wildcards
      register_route("com.example.*.deleted", GenericDeleteAction)
  """
  @spec register_route(route_pattern(), module(), keyword()) :: :ok | {:error, term()}
  def register_route(pattern, action_module, opts \\ []) do
    GenServer.call(__MODULE__, {:register_route, pattern, action_module, opts})
  end
  
  @doc """
  Unregisters a route for a specific pattern.
  """
  @spec unregister_route(route_pattern()) :: :ok | {:error, :not_found}
  def unregister_route(pattern) do
    GenServer.call(__MODULE__, {:unregister_route, pattern})
  end
  
  @doc """
  Finds the best matching route for a signal type.
  
  Returns the action module and parameter extractor function.
  """
  @spec find_route(String.t()) :: {:ok, module(), (map() -> map())} | {:error, :no_route}
  def find_route(signal_type) do
    GenServer.call(__MODULE__, {:find_route, signal_type})
  end
  
  @doc """
  Lists all registered routes ordered by priority.
  """
  @spec list_routes() :: [{route_pattern(), module(), keyword()}]
  def list_routes do
    GenServer.call(__MODULE__, :list_routes)
  end
  
  @doc """
  Clears all routes. Use with caution!
  """
  @spec clear_routes() :: :ok
  def clear_routes do
    GenServer.call(__MODULE__, :clear_routes)
  end
  
  @doc """
  Loads routes from configuration.
  """
  @spec load_from_config() :: :ok
  def load_from_config do
    GenServer.call(__MODULE__, :load_from_config)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table for fast route lookups
    :ets.new(@table_name, [
      :named_table,
      :ordered_set,
      :public,
      read_concurrency: true
    ])
    
    # Load initial routes
    load_default_routes()
    
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:register_route, pattern, action_module, opts}, _from, state) do
    priority = Keyword.get(opts, :priority, 50)
    param_extractor = Keyword.get(opts, :param_extractor, &default_param_extractor/1)
    metadata = Keyword.get(opts, :metadata, %{})
    override = Keyword.get(opts, :override, false)
    
    # Check if pattern already exists
    case :ets.lookup(@table_name, pattern) do
      [{^pattern, _route}] when not override ->
        {:reply, {:error, :route_exists}, state}
        
      _ ->
        # Validate action module
        if Code.ensure_loaded?(action_module) and function_exported?(action_module, :run, 2) do
          route = {priority, action_module, param_extractor, metadata}
          :ets.insert(@table_name, {pattern, route})
          
          Logger.info("Registered route: #{pattern} -> #{inspect(action_module)} (priority: #{priority})")
          
          {:reply, :ok, state}
        else
          {:reply, {:error, :invalid_action_module}, state}
        end
    end
  end
  
  @impl true
  def handle_call({:unregister_route, pattern}, _from, state) do
    case :ets.take(@table_name, pattern) do
      [] -> {:reply, {:error, :not_found}, state}
      _ -> 
        Logger.info("Unregistered route: #{pattern}")
        {:reply, :ok, state}
    end
  end
  
  @impl true
  def handle_call({:find_route, signal_type}, _from, state) do
    # First, try exact match
    case :ets.lookup(@table_name, signal_type) do
      [{^signal_type, {_priority, action_module, param_extractor, _metadata}}] ->
        {:reply, {:ok, action_module, param_extractor}, state}
        
      [] ->
        # Try pattern matching
        case find_pattern_match(signal_type) do
          {:ok, action_module, param_extractor} ->
            {:reply, {:ok, action_module, param_extractor}, state}
            
          :error ->
            {:reply, {:error, :no_route}, state}
        end
    end
  end
  
  @impl true
  def handle_call(:list_routes, _from, state) do
    routes = 
      :ets.tab2list(@table_name)
      |> Enum.map(fn {pattern, {priority, action_module, _extractor, metadata}} ->
        {pattern, action_module, [priority: priority, metadata: metadata]}
      end)
      |> Enum.sort_by(fn {_pattern, _module, opts} -> -Keyword.get(opts, :priority) end)
    
    {:reply, routes, state}
  end
  
  @impl true
  def handle_call(:clear_routes, _from, state) do
    :ets.delete_all_objects(@table_name)
    Logger.warning("All signal routes cleared")
    # Reload default routes
    load_default_routes()
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call(:load_from_config, _from, state) do
    load_configured_routes()
    {:reply, :ok, state}
  end
  
  # Private functions
  
  defp load_default_routes do
    # Load built-in routes
    default_routes = [
      {"increment", RubberDuck.Jido.Actions.Increment, &extract_increment_params/1, 50},
      {"add_message", RubberDuck.Jido.Actions.AddMessage, &extract_message_params/1, 50},
      {"update_status", RubberDuck.Jido.Actions.UpdateStatus, &extract_status_params/1, 50}
    ]
    
    Enum.each(default_routes, fn {pattern, action, extractor, priority} ->
      route = {priority, action, extractor, %{source: :default}}
      :ets.insert(@table_name, {pattern, route})
    end)
    
    # Load from configuration
    load_configured_routes()
  end
  
  defp load_configured_routes do
    # Load routes from application configuration
    routes = Application.get_env(:rubber_duck, :signal_routes, [])
    
    Enum.each(routes, fn route_config ->
      pattern = Keyword.fetch!(route_config, :pattern)
      action = Keyword.fetch!(route_config, :action)
      priority = Keyword.get(route_config, :priority, 50)
      
      # Try to find extractor function
      extractor = case Keyword.get(route_config, :extractor) do
        nil -> &default_param_extractor/1
        {module, function} -> &apply(module, function, [&1])
        fun when is_function(fun, 1) -> fun
      end
      
      route = {priority, action, extractor, %{source: :config}}
      :ets.insert(@table_name, {pattern, route})
    end)
  end
  
  defp find_pattern_match(signal_type) do
    # Get all routes sorted by priority (descending)
    matches = 
      :ets.tab2list(@table_name)
      |> Enum.filter(fn {pattern, _route} ->
        String.contains?(pattern, "*") and pattern_matches?(signal_type, pattern)
      end)
      |> Enum.sort_by(fn {_pattern, {priority, _, _, _}} -> -priority end)
    
    case matches do
      [{_pattern, {_priority, action_module, param_extractor, _metadata}} | _] ->
        {:ok, action_module, param_extractor}
        
      [] ->
        :error
    end
  end
  
  defp pattern_matches?(signal_type, pattern) do
    regex = 
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("*", ".*")
      |> Regex.compile!()
    
    Regex.match?(regex, signal_type)
  end
  
  # Default parameter extractors
  
  defp default_param_extractor(%{"data" => data}) when is_map(data), do: data
  defp default_param_extractor(_), do: %{}
  
  defp extract_increment_params(event) do
    data = event["data"] || %{}
    %{amount: data["amount"] || 1}
  end
  
  defp extract_message_params(event) do
    data = event["data"] || %{}
    %{
      message: data["message"] || "",
      timestamp: data["timestamp"] != false
    }
  end
  
  defp extract_status_params(event) do
    data = event["data"] || %{}
    %{
      status: String.to_atom(data["status"] || "idle"),
      reason: data["reason"]
    }
  end
end
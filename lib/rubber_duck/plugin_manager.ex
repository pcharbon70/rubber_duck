defmodule RubberDuck.PluginManager do
  @moduledoc """
  Manages the lifecycle of plugins in the RubberDuck system.
  
  The PluginManager is responsible for:
  - Registering and unregistering plugins
  - Managing plugin lifecycle (init, start, stop)
  - Resolving plugin dependencies
  - Handling plugin discovery
  - Providing plugin lookup and query capabilities
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Plugin
  
  @type plugin_ref :: atom() | pid()
  @type plugin_info :: %{
    module: module(),
    name: atom(),
    version: String.t(),
    state: any(),
    status: :loaded | :started | :stopped,
    pid: pid() | nil,
    config: keyword()
  }
  
  # Client API
  
  @doc """
  Starts the PluginManager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a plugin module with the manager.
  """
  def register_plugin(module, config \\ []) when is_atom(module) do
    GenServer.call(__MODULE__, {:register_plugin, module, config})
  end
  
  @doc """
  Unregisters a plugin.
  """
  def unregister_plugin(plugin_name) when is_atom(plugin_name) do
    GenServer.call(__MODULE__, {:unregister_plugin, plugin_name})
  end
  
  @doc """
  Starts a registered plugin.
  """
  def start_plugin(plugin_name) when is_atom(plugin_name) do
    GenServer.call(__MODULE__, {:start_plugin, plugin_name})
  end
  
  @doc """
  Stops a running plugin.
  """
  def stop_plugin(plugin_name) when is_atom(plugin_name) do
    GenServer.call(__MODULE__, {:stop_plugin, plugin_name})
  end
  
  @doc """
  Lists all registered plugins.
  """
  def list_plugins do
    GenServer.call(__MODULE__, :list_plugins)
  end
  
  @doc """
  Gets information about a specific plugin.
  """
  def get_plugin(plugin_name) when is_atom(plugin_name) do
    GenServer.call(__MODULE__, {:get_plugin, plugin_name})
  end
  
  @doc """
  Finds plugins that support specific data types.
  """
  def find_plugins_by_type(type) when is_atom(type) do
    GenServer.call(__MODULE__, {:find_by_type, type})
  end
  
  @doc """
  Executes a plugin with the given input.
  """
  def execute(plugin_name, input) when is_atom(plugin_name) do
    GenServer.call(__MODULE__, {:execute, plugin_name, input})
  end
  
  @doc """
  Discovers and loads plugins from configured paths.
  """
  def discover_plugins do
    GenServer.call(__MODULE__, :discover_plugins)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    state = %{
      plugins: %{},
      config: Keyword.get(opts, :config, []),
      discovery_paths: Keyword.get(opts, :discovery_paths, [])
    }
    
    # Optionally auto-discover plugins on startup
    if Keyword.get(opts, :auto_discover, false) do
      send(self(), :discover_plugins)
    end
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register_plugin, module, config}, _from, state) do
    case validate_and_register_plugin(module, config, state) do
      {:ok, plugin_info, new_state} ->
        Logger.info("Registered plugin #{plugin_info.name} v#{plugin_info.version}")
        {:reply, {:ok, plugin_info.name}, new_state}
        
      {:error, reason} = error ->
        Logger.error("Failed to register plugin #{inspect(module)}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:unregister_plugin, plugin_name}, _from, state) do
    case Map.get(state.plugins, plugin_name) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      plugin_info ->
        # Stop plugin if running
        if plugin_info.status == :started do
          stop_plugin_process(plugin_info)
        end
        
        new_plugins = Map.delete(state.plugins, plugin_name)
        Logger.info("Unregistered plugin #{plugin_name}")
        {:reply, :ok, %{state | plugins: new_plugins}}
    end
  end
  
  @impl true
  def handle_call({:start_plugin, plugin_name}, _from, state) do
    case Map.get(state.plugins, plugin_name) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      %{status: :started} ->
        {:reply, {:error, :already_started}, state}
        
      plugin_info ->
        case start_plugin_process(plugin_info) do
          {:ok, updated_info} ->
            new_plugins = Map.put(state.plugins, plugin_name, updated_info)
            {:reply, :ok, %{state | plugins: new_plugins}}
            
          {:error, reason} = error ->
            Logger.error("Failed to start plugin #{plugin_name}: #{inspect(reason)}")
            {:reply, error, state}
        end
    end
  end
  
  @impl true
  def handle_call({:stop_plugin, plugin_name}, _from, state) do
    case Map.get(state.plugins, plugin_name) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      %{status: :stopped} ->
        {:reply, {:error, :not_started}, state}
        
      plugin_info ->
        updated_info = stop_plugin_process(plugin_info)
        new_plugins = Map.put(state.plugins, plugin_name, updated_info)
        {:reply, :ok, %{state | plugins: new_plugins}}
    end
  end
  
  @impl true
  def handle_call(:list_plugins, _from, state) do
    plugins = Enum.map(state.plugins, fn {_name, info} ->
      %{
        name: info.name,
        version: info.version,
        status: info.status,
        module: info.module
      }
    end)
    {:reply, plugins, state}
  end
  
  @impl true
  def handle_call({:get_plugin, plugin_name}, _from, state) do
    case Map.get(state.plugins, plugin_name) do
      nil -> {:reply, {:error, :not_found}, state}
      info -> {:reply, {:ok, info}, state}
    end
  end
  
  @impl true
  def handle_call({:find_by_type, type}, _from, state) do
    plugins = state.plugins
    |> Enum.filter(fn {_name, info} ->
      types = apply(info.module, :supported_types, [])
      type in types or :any in types
    end)
    |> Enum.map(fn {name, _info} -> name end)
    
    {:reply, plugins, state}
  end
  
  @impl true
  def handle_call({:execute, plugin_name, input}, _from, state) do
    case Map.get(state.plugins, plugin_name) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      %{status: :stopped} ->
        {:reply, {:error, :not_started}, state}
        
      plugin_info ->
        result = execute_plugin(plugin_info, input)
        
        # Update state if execution changed it
        new_state = case result do
          {:ok, _output, new_plugin_state} ->
            updated_info = %{plugin_info | state: new_plugin_state}
            new_plugins = Map.put(state.plugins, plugin_name, updated_info)
            %{state | plugins: new_plugins}
            
          _ ->
            state
        end
        
        {:reply, result, new_state}
    end
  end
  
  @impl true
  def handle_call(:discover_plugins, _from, state) do
    discovered = discover_plugins_in_paths(state.discovery_paths)
    
    # Register discovered plugins
    {registered, new_state} = Enum.reduce(discovered, {[], state}, fn module, {acc, st} ->
      case validate_and_register_plugin(module, [], st) do
        {:ok, info, new_st} ->
          {[info.name | acc], new_st}
        _ ->
          {acc, st}
      end
    end)
    
    Logger.info("Discovered and registered #{length(registered)} plugins")
    {:reply, {:ok, registered}, new_state}
  end
  
  @impl true
  def handle_info(:discover_plugins, state) do
    {:reply, {:ok, _}, new_state} = handle_call(:discover_plugins, nil, state)
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp validate_and_register_plugin(module, config, state) do
    with :ok <- Plugin.validate_plugin(module),
         name <- apply(module, :name, []),
         false <- Map.has_key?(state.plugins, name),
         version <- apply(module, :version, []),
         {:ok, plugin_state} <- apply(module, :init, [config]) do
      
      plugin_info = %{
        module: module,
        name: name,
        version: version,
        state: plugin_state,
        status: :loaded,
        pid: nil,
        config: config
      }
      
      new_plugins = Map.put(state.plugins, name, plugin_info)
      {:ok, plugin_info, %{state | plugins: new_plugins}}
    else
      true -> {:error, :already_registered}
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end
  
  defp start_plugin_process(plugin_info) do
    # For now, we'll run plugins in the same process
    # In the future, we can spawn dedicated processes for isolation
    %{plugin_info | status: :started, pid: self()}
    |> wrap_ok()
  end
  
  defp stop_plugin_process(plugin_info) do
    # Call terminate callback
    apply(plugin_info.module, :terminate, [:normal, plugin_info.state])
    %{plugin_info | status: :stopped, pid: nil}
  end
  
  defp execute_plugin(plugin_info, input) do
    try do
      # Optionally validate input
      case function_exported?(plugin_info.module, :validate_input, 1) do
        true ->
          case apply(plugin_info.module, :validate_input, [input]) do
            :ok -> :ok
            {:error, _} = error -> throw(error)
          end
        false ->
          :ok
      end
      
      # Execute plugin
      case apply(plugin_info.module, :execute, [input, plugin_info.state]) do
        {:ok, output, new_state} -> {:ok, output, new_state}
        {:error, reason, state} -> {:error, reason, state}
        other -> {:error, {:invalid_return, other}, plugin_info.state}
      end
    rescue
      e -> {:error, {:execution_failed, e}, plugin_info.state}
    catch
      {:error, _} = error -> error
    end
  end
  
  defp discover_plugins_in_paths(paths) do
    paths
    |> Enum.flat_map(&discover_in_path/1)
    |> Enum.filter(&Plugin.is_plugin?/1)
    |> Enum.uniq()
  end
  
  defp discover_in_path(_path) do
    # For now, return empty list
    # This would scan directories for plugin modules
    []
  end
  
  defp wrap_ok(value), do: {:ok, value}
end
defmodule RubberDuck.Tool.Registry do
  @moduledoc """
  ETS-backed registry for managing tool definitions.
  
  Provides high-performance storage and retrieval of tool definitions,
  supporting multiple versions, categories, and tags.
  """
  
  use GenServer
  require Logger
  
  @table_name :rubber_duck_tool_registry
  @registry_name __MODULE__
  
  # Client API
  
  @doc """
  Starts the tool registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @registry_name)
  end
  
  @doc """
  Registers a tool module with the registry.
  
  The module must use RubberDuck.Tool and define a valid tool.
  """
  @spec register(module()) :: :ok | {:error, :invalid_tool | term()}
  def register(module) do
    GenServer.call(@registry_name, {:register, module})
  end
  
  @doc """
  Gets a tool by name, optionally specifying a version.
  
  If no version is specified, returns the latest version.
  """
  @spec get(atom(), String.t() | nil) :: {:ok, map()} | {:error, :not_found}
  def get(name, version \\ nil) do
    GenServer.call(@registry_name, {:get, name, version})
  end
  
  @doc """
  Lists all registered tools (all versions).
  """
  @spec list_all() :: [map()]
  def list_all do
    GenServer.call(@registry_name, :list_all)
  end
  
  @doc """
  Lists the latest version of each registered tool.
  """
  @spec list() :: [map()]
  def list do
    GenServer.call(@registry_name, :list)
  end
  
  @doc """
  Lists tools by category.
  """
  @spec list_by_category(atom()) :: [map()]
  def list_by_category(category) do
    GenServer.call(@registry_name, {:list_by_category, category})
  end
  
  @doc """
  Lists tools by tag.
  """
  @spec list_by_tag(atom()) :: [map()]
  def list_by_tag(tag) do
    GenServer.call(@registry_name, {:list_by_tag, tag})
  end
  
  @doc """
  Lists all versions of a specific tool.
  """
  @spec list_versions(atom()) :: [String.t()]
  def list_versions(name) do
    GenServer.call(@registry_name, {:list_versions, name})
  end
  
  @doc """
  Unregisters a tool, optionally specifying a version.
  
  If no version is specified, unregisters all versions.
  """
  @spec unregister(atom(), String.t() | nil) :: :ok
  def unregister(name, version \\ nil) do
    GenServer.call(@registry_name, {:unregister, name, version})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table with ordered_set for version sorting
    table = :ets.new(@table_name, [:named_table, :ordered_set, :protected, read_concurrency: true])
    {:ok, %{table: table}}
  end
  
  @impl true
  def handle_call({:register, module}, _from, state) do
    case validate_and_extract_tool(module) do
      {:ok, tool_info} ->
        # Store with composite key {name, version}
        key = {tool_info.name, tool_info.version}
        :ets.insert(@table_name, {key, tool_info})
        {:reply, :ok, state}
        
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:get, name, nil}, _from, state) do
    # Get latest version
    case get_latest_version(name) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      tool_info ->
        {:reply, {:ok, tool_info}, state}
    end
  end
  
  @impl true
  def handle_call({:get, name, version}, _from, state) do
    case :ets.lookup(@table_name, {name, version}) do
      [{_key, tool_info}] ->
        {:reply, {:ok, tool_info}, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call(:list_all, _from, state) do
    tools = :ets.tab2list(@table_name)
            |> Enum.map(fn {_key, tool_info} -> tool_info end)
    {:reply, tools, state}
  end
  
  @impl true
  def handle_call(:list, _from, state) do
    # Group by name and get latest version of each
    tools = :ets.tab2list(@table_name)
            |> Enum.map(fn {_key, tool_info} -> tool_info end)
            |> Enum.group_by(& &1.name)
            |> Enum.map(fn {_name, versions} ->
              Enum.max_by(versions, & &1.version, &compare_versions/2)
            end)
    
    {:reply, tools, state}
  end
  
  @impl true
  def handle_call({:list_by_category, category}, _from, state) do
    tools = :ets.tab2list(@table_name)
            |> Enum.map(fn {_key, tool_info} -> tool_info end)
            |> Enum.filter(& &1.category == category)
    
    {:reply, tools, state}
  end
  
  @impl true
  def handle_call({:list_by_tag, tag}, _from, state) do
    tools = :ets.tab2list(@table_name)
            |> Enum.map(fn {_key, tool_info} -> tool_info end)
            |> Enum.filter(& tag in (&1.tags || []))
    
    {:reply, tools, state}
  end
  
  @impl true
  def handle_call({:list_versions, name}, _from, state) do
    versions = :ets.match(@table_name, {{name, :"$1"}, :_})
               |> Enum.map(&List.first/1)
               |> Enum.sort(&compare_versions/2)
    
    {:reply, versions, state}
  end
  
  @impl true
  def handle_call({:unregister, name, nil}, _from, state) do
    # Delete all versions
    :ets.match_delete(@table_name, {{name, :_}, :_})
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:unregister, name, version}, _from, state) do
    :ets.delete(@table_name, {name, version})
    {:reply, :ok, state}
  end
  
  # Private functions
  
  defp validate_and_extract_tool(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, :invalid_tool}
        
      not RubberDuck.Tool.is_tool?(module) ->
        {:error, :invalid_tool}
        
      true ->
        tool_info = RubberDuck.Tool.metadata(module)
        tool_info = Map.put(tool_info, :module, module)
        {:ok, tool_info}
    end
  end
  
  defp get_latest_version(name) do
    # Use ETS match to find all versions for this name
    matches = :ets.match_object(@table_name, {{name, :_}, :_})
    
    case matches do
      [] ->
        nil
        
      tools ->
        # Sort by version and get the latest
        tools
        |> Enum.map(fn {_key, tool_info} -> tool_info end)
        |> Enum.max_by(& &1.version, &compare_versions/2)
    end
  end
  
  defp compare_versions(v1, v2) do
    # Simple semantic version comparison
    # For now, using string comparison which works for most cases
    # Could be enhanced with proper semver parsing
    v1 >= v2
  end
end
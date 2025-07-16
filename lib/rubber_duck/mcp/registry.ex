defmodule RubberDuck.MCP.Registry do
  @moduledoc """
  A comprehensive registry system for managing MCP tools with capability-based discovery.
  
  This module provides:
  - Tool registration and cataloging
  - Capability-based discovery
  - Tool composition patterns
  - Quality metrics tracking
  - Tool recommendations
  
  The registry uses ETS for performance and supports both internal tools
  and external tool discovery.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.MCP.Registry.{Metadata, Metrics, Capabilities}
  
  @table_name :mcp_tool_registry
  @metrics_table :mcp_tool_metrics
  @capabilities_table :mcp_tool_capabilities
  
  # Client API
  
  @doc """
  Starts the registry process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a tool with the registry.
  
  ## Options
  - `:module` - The tool module (required)
  - `:metadata` - Additional metadata map
  - `:capabilities` - List of capability atoms
  - `:version` - Tool version string
  """
  def register_tool(module, opts \\ []) do
    GenServer.call(__MODULE__, {:register_tool, module, opts})
  end
  
  @doc """
  Unregisters a tool from the registry.
  """
  def unregister_tool(module) do
    GenServer.call(__MODULE__, {:unregister_tool, module})
  end
  
  @doc """
  Lists all registered tools with optional filtering.
  
  ## Options
  - `:category` - Filter by category
  - `:tags` - Filter by tags (list)
  - `:capabilities` - Filter by capabilities
  """
  def list_tools(opts \\ []) do
    GenServer.call(__MODULE__, {:list_tools, opts})
  end
  
  @doc """
  Gets detailed information about a specific tool.
  """
  def get_tool(module) do
    GenServer.call(__MODULE__, {:get_tool, module})
  end
  
  @doc """
  Searches for tools by query string.
  """
  def search_tools(query, opts \\ []) do
    GenServer.call(__MODULE__, {:search_tools, query, opts})
  end
  
  @doc """
  Gets tool recommendations based on context.
  """
  def recommend_tools(context, opts \\ []) do
    GenServer.call(__MODULE__, {:recommend_tools, context, opts})
  end
  
  @doc """
  Records a tool execution metric.
  """
  def record_metric(module, metric_type, value) do
    GenServer.cast(__MODULE__, {:record_metric, module, metric_type, value})
  end
  
  @doc """
  Gets metrics for a tool.
  """
  def get_metrics(module) do
    GenServer.call(__MODULE__, {:get_metrics, module})
  end
  
  @doc """
  Discovers tools by capability.
  """
  def discover_by_capability(capability, opts \\ []) do
    GenServer.call(__MODULE__, {:discover_by_capability, capability, opts})
  end
  
  @doc """
  Composes multiple tools into a workflow.
  """
  def compose_tools(tool_specs, opts \\ []) do
    GenServer.call(__MODULE__, {:compose_tools, tool_specs, opts})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Create ETS tables
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@metrics_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@capabilities_table, [:named_table, :bag, :public, read_concurrency: true])
    
    # Schedule periodic tasks
    schedule_discovery()
    schedule_metrics_aggregation()
    
    # Initialize state
    state = %{
      discovery_interval: opts[:discovery_interval] || :timer.minutes(5),
      metrics_interval: opts[:metrics_interval] || :timer.minutes(1),
      external_sources: opts[:external_sources] || [],
      tool_versions: %{},
      compositions: %{}
    }
    
    # Auto-discover internal tools
    discover_internal_tools()
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register_tool, module, opts}, _from, state) do
    case do_register_tool(module, opts) do
      :ok ->
        {:reply, :ok, state}
      {:error, reason} = error ->
        {:reply, error, state}
    end
  end
  
  def handle_call({:unregister_tool, module}, _from, state) do
    :ets.delete(@table_name, module)
    :ets.delete(@metrics_table, module)
    :ets.match_delete(@capabilities_table, {:'_', module})
    
    {:reply, :ok, state}
  end
  
  def handle_call({:list_tools, opts}, _from, state) do
    tools = do_list_tools(opts)
    {:reply, {:ok, tools}, state}
  end
  
  def handle_call({:get_tool, module}, _from, state) do
    case :ets.lookup(@table_name, module) do
      [{^module, metadata}] ->
        {:reply, {:ok, metadata}, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  def handle_call({:search_tools, query, opts}, _from, state) do
    results = do_search_tools(query, opts)
    {:reply, {:ok, results}, state}
  end
  
  def handle_call({:recommend_tools, context, opts}, _from, state) do
    recommendations = do_recommend_tools(context, opts)
    {:reply, {:ok, recommendations}, state}
  end
  
  def handle_call({:get_metrics, module}, _from, state) do
    case :ets.lookup(@metrics_table, module) do
      [{^module, metrics}] ->
        {:reply, {:ok, metrics}, state}
      [] ->
        {:reply, {:ok, Metrics.new()}, state}
    end
  end
  
  def handle_call({:discover_by_capability, capability, opts}, _from, state) do
    tools = do_discover_by_capability(capability, opts)
    {:reply, {:ok, tools}, state}
  end
  
  def handle_call({:compose_tools, tool_specs, opts}, _from, state) do
    case do_compose_tools(tool_specs, opts, state) do
      {:ok, composition} = result ->
        # Store composition for future reference
        composition_id = generate_composition_id()
        state = put_in(state.compositions[composition_id], composition)
        {:reply, result, state}
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_cast({:record_metric, module, metric_type, value}, state) do
    do_record_metric(module, metric_type, value)
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:discover_tools, state) do
    discover_external_tools(state.external_sources)
    schedule_discovery()
    {:noreply, state}
  end
  
  def handle_info(:aggregate_metrics, state) do
    aggregate_all_metrics()
    schedule_metrics_aggregation()
    {:noreply, state}
  end
  
  # Private functions
  
  defp do_register_tool(module, opts) do
    try do
      # Extract metadata from module
      metadata = Metadata.extract_from_module(module, opts)
      
      # Validate the tool
      case validate_tool(module, metadata) do
        :ok ->
          # Store in registry
          :ets.insert(@table_name, {module, metadata})
          
          # Index capabilities
          Enum.each(metadata.capabilities, fn capability ->
            :ets.insert(@capabilities_table, {capability, module})
          end)
          
          # Initialize metrics
          :ets.insert(@metrics_table, {module, Metrics.new()})
          
          Logger.info("Registered MCP tool: #{inspect(module)}")
          :ok
          
        {:error, reason} = error ->
          Logger.error("Failed to register tool #{inspect(module)}: #{reason}")
          error
      end
    rescue
      e ->
        Logger.error("Error registering tool #{inspect(module)}: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end
  
  defp do_list_tools(opts) do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {_module, metadata} -> metadata end)
    |> filter_tools(opts)
    |> Enum.sort_by(& &1.name)
  end
  
  defp filter_tools(tools, opts) do
    tools
    |> filter_by_category(opts[:category])
    |> filter_by_tags(opts[:tags])
    |> filter_by_capabilities(opts[:capabilities])
  end
  
  defp filter_by_category(tools, nil), do: tools
  defp filter_by_category(tools, category) do
    Enum.filter(tools, fn tool ->
      tool.category == category
    end)
  end
  
  defp filter_by_tags(tools, nil), do: tools
  defp filter_by_tags(tools, tags) when is_list(tags) do
    Enum.filter(tools, fn tool ->
      Enum.any?(tags, fn tag -> tag in tool.tags end)
    end)
  end
  
  defp filter_by_capabilities(tools, nil), do: tools
  defp filter_by_capabilities(tools, capabilities) when is_list(capabilities) do
    Enum.filter(tools, fn tool ->
      Enum.all?(capabilities, fn cap -> cap in tool.capabilities end)
    end)
  end
  
  defp do_search_tools(query, opts) do
    query_lower = String.downcase(query)
    
    :ets.tab2list(@table_name)
    |> Enum.map(fn {_module, metadata} -> metadata end)
    |> Enum.filter(fn tool ->
      search_match?(tool, query_lower)
    end)
    |> Enum.sort_by(fn tool ->
      search_score(tool, query_lower)
    end, :desc)
    |> Enum.take(opts[:limit] || 10)
  end
  
  defp search_match?(tool, query) do
    String.contains?(String.downcase(tool.name), query) or
    String.contains?(String.downcase(tool.description), query) or
    Enum.any?(tool.tags, fn tag -> 
      String.contains?(String.downcase(to_string(tag)), query)
    end)
  end
  
  defp search_score(tool, query) do
    name_score = if String.contains?(String.downcase(tool.name), query), do: 10, else: 0
    desc_score = if String.contains?(String.downcase(tool.description), query), do: 5, else: 0
    tag_score = Enum.count(tool.tags, fn tag ->
      String.contains?(String.downcase(to_string(tag)), query)
    end) * 3
    
    name_score + desc_score + tag_score
  end
  
  defp do_recommend_tools(context, opts) do
    # Get all tools
    all_tools = :ets.tab2list(@table_name)
    |> Enum.map(fn {module, metadata} -> {module, metadata} end)
    
    # Score tools based on context
    scored_tools = Enum.map(all_tools, fn {module, metadata} ->
      score = calculate_recommendation_score(module, metadata, context)
      {score, metadata}
    end)
    
    # Sort by score and take top N
    scored_tools
    |> Enum.sort_by(fn {score, _} -> score end, :desc)
    |> Enum.take(opts[:limit] || 5)
    |> Enum.map(fn {_score, metadata} -> metadata end)
  end
  
  defp calculate_recommendation_score(module, metadata, context) do
    # Base score from tool quality metrics
    metrics_score = case :ets.lookup(@metrics_table, module) do
      [{^module, metrics}] -> Metrics.quality_score(metrics)
      [] -> 50.0
    end
    
    # Context matching score
    context_score = calculate_context_score(metadata, context)
    
    # Combined score
    metrics_score * 0.4 + context_score * 0.6
  end
  
  defp calculate_context_score(metadata, context) do
    # Score based on matching tags, capabilities, etc.
    tag_matches = Enum.count(metadata.tags, fn tag ->
      tag in Map.get(context, :tags, [])
    end)
    
    capability_matches = Enum.count(metadata.capabilities, fn cap ->
      cap in Map.get(context, :required_capabilities, [])
    end)
    
    category_match = if metadata.category == Map.get(context, :category), do: 20, else: 0
    
    tag_matches * 10 + capability_matches * 15 + category_match
  end
  
  defp do_discover_by_capability(capability, opts) do
    case :ets.lookup(@capabilities_table, capability) do
      [] -> []
      matches ->
        modules = Enum.map(matches, fn {_cap, module} -> module end)
        
        # Get metadata for each module
        Enum.map(modules, fn module ->
          case :ets.lookup(@table_name, module) do
            [{^module, metadata}] -> metadata
            [] -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(fn metadata ->
          # Sort by quality score
          case :ets.lookup(@metrics_table, metadata.module) do
            [{_module, metrics}] -> Metrics.quality_score(metrics)
            [] -> 0.0
          end
        end, :desc)
    end
  end
  
  defp do_compose_tools(tool_specs, opts, state) do
    # Validate all tools exist
    with {:ok, tools} <- validate_tool_specs(tool_specs),
         {:ok, composition} <- build_composition(tools, opts) do
      {:ok, composition}
    end
  end
  
  defp validate_tool_specs(tool_specs) do
    results = Enum.map(tool_specs, fn spec ->
      module = spec[:module] || spec["module"]
      case :ets.lookup(@table_name, module) do
        [{^module, metadata}] -> {:ok, {spec, metadata}}
        [] -> {:error, {:tool_not_found, module}}
      end
    end)
    
    case Enum.find(results, fn
      {:error, _} -> true
      _ -> false
    end) do
      nil -> {:ok, Enum.map(results, fn {:ok, result} -> result end)}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp build_composition(tools, opts) do
    composition = %{
      id: generate_composition_id(),
      tools: tools,
      type: opts[:type] || :sequential,
      created_at: DateTime.utc_now(),
      metadata: opts[:metadata] || %{}
    }
    
    {:ok, composition}
  end
  
  defp do_record_metric(module, metric_type, value) do
    metrics = case :ets.lookup(@metrics_table, module) do
      [{^module, existing}] -> existing
      [] -> Metrics.new()
    end
    
    updated = Metrics.record(metrics, metric_type, value)
    :ets.insert(@metrics_table, {module, updated})
  end
  
  defp validate_tool(module, metadata) do
    cond do
      not is_atom(module) ->
        {:error, "Module must be an atom"}
        
      not Code.ensure_loaded?(module) ->
        {:error, "Module not loaded"}
        
      not function_exported?(module, :execute, 2) ->
        {:error, "Tool must implement execute/2"}
        
      true ->
        :ok
    end
  end
  
  defp discover_internal_tools do
    # Auto-discover tools in the MCP.Server.Tools namespace
    Logger.info("Discovering internal MCP tools...")
    
    {:ok, modules} = :application.get_key(:rubber_duck, :modules)
    
    modules
    |> Enum.filter(fn module ->
      module_str = to_string(module)
      String.starts_with?(module_str, "Elixir.RubberDuck.MCP.Server.Tools.")
    end)
    |> Enum.each(fn module ->
      register_tool(module, source: :internal)
    end)
  end
  
  defp discover_external_tools(sources) do
    # TODO: Implement external tool discovery
    # This would scan external sources for available tools
    Logger.debug("External tool discovery not yet implemented")
  end
  
  defp aggregate_all_metrics do
    # Aggregate metrics for all tools
    :ets.tab2list(@metrics_table)
    |> Enum.each(fn {module, metrics} ->
      aggregated = Metrics.aggregate(metrics)
      :ets.insert(@metrics_table, {module, aggregated})
    end)
  end
  
  defp generate_composition_id do
    "comp_#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}"
  end
  
  defp schedule_discovery do
    Process.send_after(self(), :discover_tools, :timer.minutes(5))
  end
  
  defp schedule_metrics_aggregation do
    Process.send_after(self(), :aggregate_metrics, :timer.minutes(1))
  end
end
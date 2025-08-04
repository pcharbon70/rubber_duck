defmodule RubberDuck.Jido.Signals.SignalRouter do
  @moduledoc """
  Pattern-based signal routing with priority handling and load balancing.
  
  This module provides intelligent routing of signals to appropriate handlers
  based on pattern matching, priority, and load balancing strategies. It uses
  ETS for fast pattern matching and maintains routing tables in memory.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Jido.Signals.SignalCategory
  
  @ets_routes :signal_routes
  @ets_handlers :signal_handlers
  
  @type route :: %{
    pattern: String.t() | Regex.t(),
    handler: module() | pid(),
    priority: SignalCategory.priority(),
    category: SignalCategory.category(),
    options: map()
  }
  
  @type routing_strategy :: :round_robin | :random | :least_loaded | :sticky
  
  # Client API
  
  @doc """
  Starts the signal router.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a route for signal patterns.
  
  ## Examples
  
      register_route("analysis.*", AnalysisHandler, category: :request)
      register_route(~r/^user\\..*/, UserHandler, priority: :high)
  """
  @spec register_route(String.t() | Regex.t(), module() | pid(), keyword()) :: :ok | {:error, term()}
  def register_route(pattern, handler, opts \\ []) do
    GenServer.call(__MODULE__, {:register_route, pattern, handler, opts})
  end
  
  @doc """
  Unregisters a route.
  """
  @spec unregister_route(String.t() | Regex.t()) :: :ok
  def unregister_route(pattern) do
    GenServer.call(__MODULE__, {:unregister_route, pattern})
  end
  
  @doc """
  Routes a signal to appropriate handlers.
  """
  @spec route_signal(map()) :: {:ok, [pid()]} | {:error, term()}
  def route_signal(signal) do
    GenServer.call(__MODULE__, {:route_signal, signal})
  end
  
  @doc """
  Lists all registered routes.
  """
  @spec list_routes() :: [route()]
  def list_routes do
    GenServer.call(__MODULE__, :list_routes)
  end
  
  @doc """
  Returns routing metrics.
  """
  @spec get_metrics() :: map()
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Create ETS tables for fast lookups
    :ets.new(@ets_routes, [:set, :protected, :named_table])
    :ets.new(@ets_handlers, [:bag, :protected, :named_table])
    
    state = %{
      routing_strategy: Keyword.get(opts, :routing_strategy, :round_robin),
      max_handlers_per_pattern: Keyword.get(opts, :max_handlers_per_pattern, 10),
      metrics: %{
        routed_count: 0,
        failed_count: 0,
        no_route_count: 0,
        by_category: %{}
      },
      handler_indices: %{},  # For round-robin
      handler_loads: %{}     # For least-loaded
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register_route, pattern, handler, opts}, _from, state) do
    route = build_route(pattern, handler, opts)
    
    # Validate the route
    case validate_route(route) do
      :ok ->
        # Store in ETS
        pattern_key = pattern_to_key(pattern)
        :ets.insert(@ets_routes, {pattern_key, route})
        :ets.insert(@ets_handlers, {pattern_key, handler})
        
        Logger.info("Registered route: #{inspect(pattern)} -> #{inspect(handler)}")
        {:reply, :ok, state}
        
      {:error, reason} = error ->
        Logger.error("Failed to register route: #{inspect(reason)}")
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:unregister_route, pattern}, _from, state) do
    pattern_key = pattern_to_key(pattern)
    :ets.delete(@ets_routes, pattern_key)
    :ets.delete(@ets_handlers, pattern_key)
    
    Logger.info("Unregistered route: #{inspect(pattern)}")
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:route_signal, signal}, _from, state) do
    signal_type = Map.get(signal, :type, Map.get(signal, "type"))
    
    # Find matching routes
    matching_routes = find_matching_routes(signal_type)
    
    if Enum.empty?(matching_routes) do
      new_state = update_metrics(state, :no_route, signal_type)
      {:reply, {:error, :no_matching_routes}, new_state}
    else
      # Sort by priority
      sorted_routes = Enum.sort_by(matching_routes, fn route ->
        priority_to_number(route.priority)
      end, :desc)
      
      # Select handlers based on routing strategy
      selected_handlers = select_handlers(sorted_routes, state)
      
      # Update metrics
      category = infer_signal_category(signal_type)
      new_state = update_metrics(state, :routed, signal_type, category)
      
      {:reply, {:ok, selected_handlers}, new_state}
    end
  end
  
  @impl true
  def handle_call(:list_routes, _from, state) do
    routes = :ets.tab2list(@ets_routes)
      |> Enum.map(fn {_key, route} -> route end)
    
    {:reply, routes, state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end
  
  # Private functions
  
  defp build_route(pattern, handler, opts) do
    category = case Keyword.get(opts, :category) do
      nil -> infer_category_from_pattern(pattern)
      cat -> cat
    end
    
    %{
      pattern: pattern,
      handler: handler,
      priority: Keyword.get(opts, :priority, SignalCategory.default_priority(category)),
      category: category,
      options: Keyword.get(opts, :options, %{})
    }
  end
  
  defp validate_route(route) do
    with :ok <- validate_handler(route.handler),
         :ok <- validate_pattern(route.pattern),
         true <- SignalCategory.valid_category?(route.category) do
      :ok
    else
      false -> {:error, {:invalid_category, route.category}}
      error -> error
    end
  end
  
  defp validate_handler(handler) when is_atom(handler) do
    if Code.ensure_loaded?(handler) do
      :ok
    else
      {:error, {:invalid_handler, handler}}
    end
  end
  defp validate_handler(handler) when is_pid(handler), do: :ok
  defp validate_handler(handler), do: {:error, {:invalid_handler, handler}}
  
  defp validate_pattern(pattern) when is_binary(pattern), do: :ok
  defp validate_pattern(%Regex{} = _pattern), do: :ok
  defp validate_pattern(pattern), do: {:error, {:invalid_pattern, pattern}}
  
  defp pattern_to_key(pattern) when is_binary(pattern), do: {:string, pattern}
  defp pattern_to_key(%Regex{source: source}), do: {:regex, source}
  
  defp find_matching_routes(signal_type) do
    :ets.tab2list(@ets_routes)
    |> Enum.filter(fn {_key, route} ->
      matches_pattern?(signal_type, route.pattern)
    end)
    |> Enum.map(fn {_key, route} -> route end)
  end
  
  defp matches_pattern?(signal_type, pattern) when is_binary(pattern) do
    # Convert wildcard pattern to regex
    regex = pattern
      |> String.replace(".", "\\.")
      |> String.replace("*", ".*")
      |> Regex.compile!()
    
    Regex.match?(regex, signal_type)
  end
  
  defp matches_pattern?(signal_type, %Regex{} = pattern) do
    Regex.match?(pattern, signal_type)
  end
  
  defp select_handlers(routes, state) do
    case state.routing_strategy do
      :round_robin -> select_round_robin(routes, state)
      :random -> select_random(routes)
      :least_loaded -> select_least_loaded(routes, state)
      :sticky -> select_sticky(routes, state)
    end
  end
  
  defp select_round_robin(routes, state) do
    Enum.map(routes, fn route ->
      pattern_key = pattern_to_key(route.pattern)
      handlers = :ets.lookup(@ets_handlers, pattern_key)
        |> Enum.map(fn {_key, handler} -> handler end)
      
      if Enum.empty?(handlers) do
        route.handler
      else
        # Get current index for this pattern
        current_index = Map.get(state.handler_indices, pattern_key, 0)
        selected = Enum.at(handlers, rem(current_index, length(handlers)))
        
        # Update index for next selection
        Process.put({:handler_index, pattern_key}, current_index + 1)
        
        selected
      end
    end)
  end
  
  defp select_random(routes) do
    Enum.map(routes, fn route ->
      pattern_key = pattern_to_key(route.pattern)
      handlers = :ets.lookup(@ets_handlers, pattern_key)
        |> Enum.map(fn {_key, handler} -> handler end)
      
      if Enum.empty?(handlers) do
        route.handler
      else
        Enum.random(handlers)
      end
    end)
  end
  
  defp select_least_loaded(routes, state) do
    Enum.map(routes, fn route ->
      pattern_key = pattern_to_key(route.pattern)
      handlers = :ets.lookup(@ets_handlers, pattern_key)
        |> Enum.map(fn {_key, handler} -> handler end)
      
      if Enum.empty?(handlers) do
        route.handler
      else
        # Select handler with lowest load
        Enum.min_by(handlers, fn handler ->
          Map.get(state.handler_loads, handler, 0)
        end)
      end
    end)
  end
  
  defp select_sticky(routes, _state) do
    # For sticky routing, always use the first handler
    Enum.map(routes, fn route -> route.handler end)
  end
  
  defp priority_to_number(:critical), do: 4
  defp priority_to_number(:high), do: 3
  defp priority_to_number(:normal), do: 2
  defp priority_to_number(:low), do: 1
  
  defp infer_category_from_pattern(pattern) when is_binary(pattern) do
    case SignalCategory.infer_category(pattern) do
      {:ok, category} -> category
      {:error, _} -> :event  # Default to event
    end
  end
  defp infer_category_from_pattern(_), do: :event
  
  defp infer_signal_category(signal_type) do
    case SignalCategory.infer_category(signal_type) do
      {:ok, category} -> category
      {:error, _} -> :event
    end
  end
  
  defp update_metrics(state, :routed, _signal_type, category) do
    metrics = state.metrics
      |> Map.update!(:routed_count, &(&1 + 1))
      |> Map.update!(:by_category, fn by_cat ->
        Map.update(by_cat, category, 1, &(&1 + 1))
      end)
    
    %{state | metrics: metrics}
  end
  
  defp update_metrics(state, :no_route, _signal_type) do
    metrics = Map.update!(state.metrics, :no_route_count, &(&1 + 1))
    %{state | metrics: metrics}
  end
  
  defp update_metrics(state, :failed, _signal_type) do
    metrics = Map.update!(state.metrics, :failed_count, &(&1 + 1))
    %{state | metrics: metrics}
  end
end
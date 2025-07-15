defmodule RubberDuck.CoT.ChainRegistry do
  @moduledoc """
  Registry for Chain-of-Thought reasoning chains.
  
  Provides automatic chain selection based on content analysis and
  dynamic chain discovery. Maintains a registry of available chains
  with their capabilities and usage patterns.
  """
  
  use GenServer
  require Logger
  
  # Client API
  
  @doc """
  Starts the chain registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a chain module with its capabilities.
  """
  def register_chain(chain_module, capabilities \\ %{}) do
    GenServer.call(__MODULE__, {:register_chain, chain_module, capabilities})
  end
  
  @doc """
  Selects the most appropriate chain for given content and context.
  """
  def select_chain(content, context \\ %{}) do
    GenServer.call(__MODULE__, {:select_chain, content, context})
  end
  
  @doc """
  Lists all registered chains with their capabilities.
  """
  def list_chains do
    GenServer.call(__MODULE__, :list_chains)
  end
  
  @doc """
  Gets usage statistics for chains.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    state = %{
      chains: %{},
      usage_stats: %{},
      selection_history: []
    }
    
    # Auto-discover and register chains
    discover_chains()
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register_chain, chain_module, capabilities}, _from, state) do
    # Validate the chain module implements the behavior
    if valid_chain_module?(chain_module) do
      chain_info = build_chain_info(chain_module, capabilities)
      new_chains = Map.put(state.chains, chain_module, chain_info)
      
      Logger.info("[Chain Registry] Registered chain: #{inspect(chain_module)}")
      
      {:reply, :ok, %{state | chains: new_chains}}
    else
      {:reply, {:error, :invalid_chain_module}, state}
    end
  end
  
  @impl true
  def handle_call({:select_chain, content, context}, _from, state) do
    # Analyze content to determine best chain
    selected_chain = select_best_chain(content, context, state.chains)
    
    # Update usage stats
    new_stats = update_usage_stats(state.usage_stats, selected_chain)
    
    # Record selection history
    selection_record = %{
      chain: selected_chain,
      timestamp: DateTime.utc_now(),
      content_preview: String.slice(content, 0, 100)
    }
    
    new_history = [selection_record | Enum.take(state.selection_history, 99)]
    
    new_state = %{state | 
      usage_stats: new_stats,
      selection_history: new_history
    }
    
    {:reply, {:ok, selected_chain}, new_state}
  end
  
  @impl true
  def handle_call(:list_chains, _from, state) do
    chains_list = Enum.map(state.chains, fn {module, info} ->
      %{
        module: module,
        name: info.name,
        description: info.description,
        capabilities: info.capabilities,
        usage_count: Map.get(state.usage_stats, module, 0)
      }
    end)
    
    {:reply, chains_list, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_chains: map_size(state.chains),
      total_selections: Enum.sum(Map.values(state.usage_stats)),
      usage_by_chain: state.usage_stats,
      recent_selections: Enum.take(state.selection_history, 10)
    }
    
    {:reply, stats, state}
  end
  
  # Private functions
  
  defp discover_chains do
    # Auto-discover chain modules in the CoT.Chains namespace
    {:ok, modules} = :application.get_key(:rubber_duck, :modules)
    
    chain_modules = modules
    |> Enum.filter(&String.starts_with?(to_string(&1), "Elixir.RubberDuck.CoT.Chains."))
    |> Enum.filter(&valid_chain_module?/1)
    
    # Register discovered chains
    Enum.each(chain_modules, fn module ->
      GenServer.cast(__MODULE__, {:auto_register, module})
    end)
  end
  
  defp valid_chain_module?(module) do
    # Check if module implements the ChainBehaviour
    Code.ensure_loaded?(module) &&
    function_exported?(module, :config, 0) &&
    function_exported?(module, :steps, 0)
  end
  
  defp build_chain_info(chain_module, additional_capabilities) do
    config = chain_module.config()
    
    # Extract capabilities from the chain
    base_capabilities = %{
      max_steps: config[:max_steps],
      timeout: config[:timeout],
      template: config[:template],
      supports_streaming: Map.get(config, :supports_streaming, false)
    }
    
    # Analyze steps to infer capabilities
    steps = chain_module.steps()
    inferred_capabilities = infer_capabilities_from_steps(steps)
    
    %{
      name: config[:name],
      description: config[:description],
      capabilities: Map.merge(base_capabilities, Map.merge(inferred_capabilities, additional_capabilities)),
      steps: Enum.map(steps, & &1.name),
      validators: extract_validators(chain_module, steps)
    }
  end
  
  defp infer_capabilities_from_steps(steps) do
    step_names = Enum.map(steps, & &1.name)
    
    %{
      handles_code: Enum.any?(step_names, &String.contains?(to_string(&1), ["code", "generate", "implement"])),
      handles_analysis: Enum.any?(step_names, &String.contains?(to_string(&1), ["analyze", "review", "check"])),
      handles_conversation: Enum.any?(step_names, &String.contains?(to_string(&1), ["convers", "chat", "respond"])),
      handles_completion: Enum.any?(step_names, &String.contains?(to_string(&1), ["complet", "suggest", "finish"])),
      handles_problems: Enum.any?(step_names, &String.contains?(to_string(&1), ["solve", "fix", "debug"]))
    }
  end
  
  defp extract_validators(chain_module, steps) do
    steps
    |> Enum.flat_map(fn step ->
      Map.get(step, :validates, [])
    end)
    |> Enum.uniq()
    |> Enum.filter(fn validator ->
      function_exported?(chain_module, validator, 1)
    end)
  end
  
  defp select_best_chain(content, context, available_chains) do
    # Score each chain based on content analysis
    scored_chains = available_chains
    |> Enum.map(fn {module, info} ->
      score = calculate_chain_score(content, context, info)
      {module, score}
    end)
    |> Enum.sort_by(fn {_module, score} -> score end, :desc)
    
    # Return the highest scoring chain, or default to ConversationChain
    case scored_chains do
      [{best_module, _score} | _] -> best_module
      [] -> RubberDuck.CoT.Chains.ConversationChain
    end
  end
  
  defp calculate_chain_score(content, context, chain_info) do
    content_lower = String.downcase(content)
    base_score = 0.5
    
    # Calculate score based on content keywords
    keyword_score = cond do
      # Code generation keywords
      chain_info.capabilities.handles_code &&
      String.contains?(content_lower, ["generate", "create", "implement", "write code", "build"]) ->
        1.0
        
      # Analysis keywords  
      chain_info.capabilities.handles_analysis &&
      String.contains?(content_lower, ["analyze", "review", "check", "find issues", "examine"]) ->
        1.0
        
      # Problem solving keywords
      chain_info.capabilities.handles_problems &&
      String.contains?(content_lower, ["solve", "fix", "debug", "help me", "issue", "problem"]) ->
        1.0
        
      # Completion keywords
      chain_info.capabilities.handles_completion &&
      String.contains?(content_lower, ["complete", "finish", "suggest", "continue"]) ->
        1.0
        
      # General conversation
      chain_info.capabilities.handles_conversation ->
        0.7
        
      true ->
        base_score
    end
    
    # Boost score based on context hints
    context_boost = case Map.get(context, :preferred_chain_type) do
      type when type == chain_info.name -> 0.5
      _ -> 0.0
    end
    
    # Consider chain complexity vs content complexity
    complexity_match = if String.length(content) > 500 && chain_info.capabilities.max_steps > 5 do
      0.2
    else
      0.0
    end
    
    keyword_score + context_boost + complexity_match
  end
  
  defp update_usage_stats(stats, chain_module) do
    Map.update(stats, chain_module, 1, &(&1 + 1))
  end
  
  # Handle auto-registration from discovery
  @impl true
  def handle_cast({:auto_register, module}, state) do
    if valid_chain_module?(module) do
      chain_info = build_chain_info(module, %{})
      new_chains = Map.put(state.chains, module, chain_info)
      
      Logger.debug("[Chain Registry] Auto-registered chain: #{inspect(module)}")
      
      {:noreply, %{state | chains: new_chains}}
    else
      {:noreply, state}
    end
  end
end
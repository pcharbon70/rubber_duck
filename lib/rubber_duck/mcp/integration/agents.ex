defmodule RubberDuck.MCP.Integration.Agents do
  @moduledoc """
  Agent system integration for MCP.
  
  This module enhances RubberDuck's agent system with MCP capabilities,
  allowing agents to discover, use, and learn from MCP tools.
  """
  
  alias RubberDuck.Agents
  alias RubberDuck.MCP.{Client, Registry}
  alias RubberDuck.MCP.Integration.Context
  
  @doc """
  Enhances an agent with MCP capabilities.
  
  This function adds MCP tool discovery and usage capabilities to an agent.
  """
  def enhance_agent(agent, opts \\ []) do
    # Add MCP tool discovery
    agent = add_tool_discovery(agent, opts)
    
    # Add tool usage learning
    agent = add_tool_learning(agent, opts)
    
    # Add composition abilities
    agent = add_composition_abilities(agent, opts)
    
    # Add context awareness
    agent = add_context_awareness(agent, opts)
    
    agent
  end
  
  @doc """
  Enables an agent to discover available MCP tools.
  """
  def discover_tools_for_agent(agent, criteria \\ %{}) do
    # Get base tool list
    base_tools = case Registry.list_tools() do
      {:ok, tools} -> tools
      _ -> []
    end
    
    # Filter by agent preferences
    filtered_tools = filter_tools_for_agent(base_tools, agent, criteria)
    
    # Add tool recommendations
    recommended_tools = get_tool_recommendations(agent, filtered_tools)
    
    %{
      available_tools: filtered_tools,
      recommended_tools: recommended_tools,
      discovery_time: DateTime.utc_now()
    }
  end
  
  @doc """
  Executes an MCP tool on behalf of an agent.
  """
  def execute_tool_for_agent(agent, tool_name, params, opts \\ []) do
    # Build execution context
    context = Context.build_tool_context(tool_name, params, 
      user_context: opts[:user_context],
      conversation_context: opts[:conversation_context],
      agent_context: %{
        agent_id: agent.id,
        agent_name: agent.name,
        agent_capabilities: agent.capabilities
      }
    )
    
    # Execute the tool
    result = Registry.execute_tool(tool_name, params, context)
    
    # Record usage for learning
    record_tool_usage(agent, tool_name, params, result, opts)
    
    # Update agent context
    updated_context = Context.update_context_with_result(context, tool_name, result)
    
    {result, updated_context}
  end
  
  @doc """
  Creates a tool composition for an agent.
  """
  def create_composition_for_agent(agent, composition_spec, opts \\ []) do
    # Validate tools are available to agent
    case validate_tools_for_agent(agent, composition_spec.tools) do
      :ok ->
        # Create the composition
        composition = Registry.Composition.create(
          composition_spec.name,
          composition_spec.tools,
          Map.merge(composition_spec.opts || %{}, %{
            created_by: agent.id,
            agent_context: %{
              agent_name: agent.name,
              agent_capabilities: agent.capabilities
            }
          })
        )
        
        # Record composition creation
        record_composition_creation(agent, composition)
        
        composition
        
      {:error, unauthorized_tools} ->
        {:error, "Agent not authorized to use tools: #{inspect(unauthorized_tools)}"}
    end
  end
  
  @doc """
  Learns from tool usage patterns to improve agent performance.
  """
  def learn_from_usage(agent, opts \\ []) do
    # Get usage history
    usage_history = get_agent_usage_history(agent, opts)
    
    # Analyze patterns
    patterns = analyze_usage_patterns(usage_history)
    
    # Update agent preferences
    updated_preferences = update_agent_preferences(agent, patterns)
    
    # Update tool recommendations
    updated_recommendations = update_tool_recommendations(agent, patterns)
    
    %{
      usage_patterns: patterns,
      updated_preferences: updated_preferences,
      updated_recommendations: updated_recommendations,
      analysis_time: DateTime.utc_now()
    }
  end
  
  @doc """
  Gets personalized tool recommendations for an agent.
  """
  def get_personalized_recommendations(agent, context \\ %{}, opts \\ []) do
    # Get agent's usage history
    usage_history = get_agent_usage_history(agent, opts)
    
    # Get successful tool patterns
    successful_patterns = extract_successful_patterns(usage_history)
    
    # Build recommendation context
    recommendation_context = Map.merge(context, %{
      agent_id: agent.id,
      agent_capabilities: agent.capabilities,
      usage_patterns: successful_patterns,
      current_task: opts[:current_task]
    })
    
    # Get recommendations from registry
    case Registry.recommend_tools(recommendation_context, limit: opts[:limit] || 5) do
      {:ok, recommendations} ->
        # Enhance with agent-specific scoring
        enhanced_recommendations = Enum.map(recommendations, fn tool ->
          agent_score = calculate_agent_tool_score(agent, tool, usage_history)
          
          Map.merge(tool, %{
            agent_score: agent_score,
            recommendation_reason: get_recommendation_reason(agent, tool, usage_history)
          })
        end)
        |> Enum.sort_by(& &1.agent_score, :desc)
        
        {:ok, enhanced_recommendations}
        
      error -> error
    end
  end
  
  # Private functions
  
  defp add_tool_discovery(agent, opts) do
    # Add tool discovery capability to agent
    discovery_config = %{
      auto_discover: opts[:auto_discover] != false,
      discovery_interval: opts[:discovery_interval] || :timer.minutes(10),
      tool_filters: opts[:tool_filters] || []
    }
    
    put_in(agent.capabilities[:mcp_tool_discovery], discovery_config)
  end
  
  defp add_tool_learning(agent, opts) do
    # Add tool learning capability
    learning_config = %{
      learn_from_usage: opts[:learn_from_usage] != false,
      learning_window: opts[:learning_window] || :timer.hours(24),
      min_usage_threshold: opts[:min_usage_threshold] || 3
    }
    
    put_in(agent.capabilities[:mcp_tool_learning], learning_config)
  end
  
  defp add_composition_abilities(agent, opts) do
    # Add composition capability
    composition_config = %{
      can_create_compositions: opts[:can_create_compositions] != false,
      max_composition_size: opts[:max_composition_size] || 5,
      allowed_composition_types: opts[:allowed_composition_types] || [:sequential, :parallel]
    }
    
    put_in(agent.capabilities[:mcp_composition], composition_config)
  end
  
  defp add_context_awareness(agent, opts) do
    # Add context awareness
    context_config = %{
      context_aware: opts[:context_aware] != false,
      context_history_size: opts[:context_history_size] || 10,
      include_tool_states: opts[:include_tool_states] != false
    }
    
    put_in(agent.capabilities[:mcp_context_awareness], context_config)
  end
  
  defp filter_tools_for_agent(tools, agent, criteria) do
    tools
    |> filter_by_agent_capabilities(agent)
    |> filter_by_criteria(criteria)
    |> filter_by_agent_preferences(agent)
  end
  
  defp filter_by_agent_capabilities(tools, agent) do
    agent_capabilities = agent.capabilities[:required_tool_capabilities] || []
    
    if Enum.empty?(agent_capabilities) do
      tools
    else
      Enum.filter(tools, fn tool ->
        Enum.any?(agent_capabilities, fn capability ->
          capability in tool.capabilities
        end)
      end)
    end
  end
  
  defp filter_by_criteria(tools, criteria) do
    tools
    |> filter_by_category(criteria[:category])
    |> filter_by_tags(criteria[:tags])
    |> filter_by_quality_threshold(criteria[:min_quality_score])
  end
  
  defp filter_by_category(tools, nil), do: tools
  defp filter_by_category(tools, category) do
    Enum.filter(tools, fn tool -> tool.category == category end)
  end
  
  defp filter_by_tags(tools, nil), do: tools
  defp filter_by_tags(tools, tags) when is_list(tags) do
    Enum.filter(tools, fn tool ->
      Enum.any?(tags, fn tag -> tag in tool.tags end)
    end)
  end
  
  defp filter_by_quality_threshold(tools, nil), do: tools
  defp filter_by_quality_threshold(tools, threshold) do
    Enum.filter(tools, fn tool ->
      case Registry.get_metrics(tool.module) do
        {:ok, metrics} -> Registry.Metrics.quality_score(metrics) >= threshold
        _ -> false
      end
    end)
  end
  
  defp filter_by_agent_preferences(tools, agent) do
    preferences = agent.preferences[:tool_preferences] || %{}
    
    # Apply blacklist
    blacklisted = preferences[:blacklisted_tools] || []
    tools = Enum.reject(tools, fn tool -> tool.name in blacklisted end)
    
    # Apply whitelist if present
    whitelisted = preferences[:whitelisted_tools] || []
    if Enum.empty?(whitelisted) do
      tools
    else
      Enum.filter(tools, fn tool -> tool.name in whitelisted end)
    end
  end
  
  defp get_tool_recommendations(agent, tools) do
    # Get top tools based on agent's usage patterns
    usage_history = get_agent_usage_history(agent, limit: 100)
    
    # Find frequently used tools
    frequently_used = extract_frequently_used_tools(usage_history)
    
    # Find tools with high success rates
    high_success_tools = extract_high_success_tools(usage_history)
    
    # Find tools used in successful compositions
    composition_tools = extract_composition_tools(agent)
    
    # Combine and rank
    all_recommended = (frequently_used ++ high_success_tools ++ composition_tools)
    |> Enum.uniq_by(& &1.name)
    |> Enum.filter(fn tool -> tool.name in Enum.map(tools, & &1.name) end)
    |> Enum.take(5)
    
    all_recommended
  end
  
  defp validate_tools_for_agent(agent, tools) do
    # Check if agent is authorized to use all tools
    unauthorized = Enum.reject(tools, fn tool_spec ->
      tool_name = tool_spec[:tool] || tool_spec["tool"]
      is_tool_authorized_for_agent?(agent, tool_name)
    end)
    
    if Enum.empty?(unauthorized) do
      :ok
    else
      {:error, unauthorized}
    end
  end
  
  defp is_tool_authorized_for_agent?(agent, tool_name) do
    # Check agent's tool permissions
    permissions = agent.permissions[:tool_permissions] || %{}
    
    case permissions[:policy] do
      :allow_all -> true
      :allow_listed -> tool_name in (permissions[:allowed_tools] || [])
      :deny_listed -> tool_name not in (permissions[:denied_tools] || [])
      _ -> true  # Default to allow
    end
  end
  
  defp record_tool_usage(agent, tool_name, params, result, opts) do
    usage_record = %{
      agent_id: agent.id,
      tool_name: tool_name,
      params: params,
      result: result,
      success: not match?({:error, _}, result),
      timestamp: DateTime.utc_now(),
      context: opts[:context] || %{}
    }
    
    # Store in agent's usage history
    Agents.record_tool_usage(agent, usage_record)
    
    # Update global metrics
    metric_type = if usage_record.success do
      {:execution, :success, 100}  # Default latency
    else
      {:execution, :failure, extract_error_type(result)}
    end
    
    Registry.record_metric(tool_name, metric_type, nil)
  end
  
  defp record_composition_creation(agent, composition) do
    creation_record = %{
      agent_id: agent.id,
      composition_id: composition.id,
      composition_name: composition.name,
      tool_count: length(composition.tools),
      timestamp: DateTime.utc_now()
    }
    
    Agents.record_composition_creation(agent, creation_record)
  end
  
  defp get_agent_usage_history(agent, opts \\ []) do
    limit = opts[:limit] || 50
    time_window = opts[:time_window] || :timer.hours(24)
    
    Agents.get_tool_usage_history(agent, limit: limit, time_window: time_window)
  end
  
  defp analyze_usage_patterns(usage_history) do
    %{
      most_used_tools: extract_most_used_tools(usage_history),
      most_successful_tools: extract_most_successful_tools(usage_history),
      time_patterns: extract_time_patterns(usage_history),
      parameter_patterns: extract_parameter_patterns(usage_history)
    }
  end
  
  defp extract_most_used_tools(usage_history) do
    usage_history
    |> Enum.group_by(& &1.tool_name)
    |> Enum.map(fn {tool_name, usages} -> {tool_name, length(usages)} end)
    |> Enum.sort_by(fn {_tool, count} -> count end, :desc)
    |> Enum.take(5)
  end
  
  defp extract_most_successful_tools(usage_history) do
    usage_history
    |> Enum.group_by(& &1.tool_name)
    |> Enum.map(fn {tool_name, usages} ->
      success_rate = Enum.count(usages, & &1.success) / length(usages)
      {tool_name, success_rate}
    end)
    |> Enum.filter(fn {_tool, rate} -> rate > 0.8 end)
    |> Enum.sort_by(fn {_tool, rate} -> rate end, :desc)
    |> Enum.take(5)
  end
  
  defp extract_time_patterns(usage_history) do
    usage_history
    |> Enum.group_by(fn usage ->
      usage.timestamp
      |> DateTime.to_time()
      |> Time.to_string()
      |> String.slice(0..4)  # Hour:minute
    end)
    |> Enum.map(fn {time, usages} -> {time, length(usages)} end)
    |> Enum.sort_by(fn {_time, count} -> count end, :desc)
  end
  
  defp extract_parameter_patterns(usage_history) do
    usage_history
    |> Enum.group_by(& &1.tool_name)
    |> Enum.map(fn {tool_name, usages} ->
      common_params = usages
      |> Enum.map(& &1.params)
      |> find_common_parameters()
      
      {tool_name, common_params}
    end)
    |> Enum.into(%{})
  end
  
  defp find_common_parameters(param_lists) do
    # Find parameters that appear in most usages
    param_lists
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_key, count} -> count > length(param_lists) / 2 end)
    |> Enum.map(fn {key, _count} -> key end)
  end
  
  defp update_agent_preferences(agent, patterns) do
    # Update agent preferences based on usage patterns
    current_preferences = agent.preferences || %{}
    
    # Add preferred tools
    preferred_tools = patterns.most_used_tools
    |> Enum.take(3)
    |> Enum.map(fn {tool_name, _count} -> tool_name end)
    
    # Add successful tools
    successful_tools = patterns.most_successful_tools
    |> Enum.take(3)
    |> Enum.map(fn {tool_name, _rate} -> tool_name end)
    
    Map.merge(current_preferences, %{
      preferred_tools: preferred_tools,
      successful_tools: successful_tools,
      last_updated: DateTime.utc_now()
    })
  end
  
  defp update_tool_recommendations(agent, patterns) do
    # Create personalized recommendations based on patterns
    %{
      recommended_tools: patterns.most_successful_tools,
      recommended_times: patterns.time_patterns,
      recommended_parameters: patterns.parameter_patterns,
      last_updated: DateTime.utc_now()
    }
  end
  
  defp extract_successful_patterns(usage_history) do
    usage_history
    |> Enum.filter(& &1.success)
    |> Enum.group_by(& &1.tool_name)
    |> Enum.map(fn {tool_name, successful_usages} ->
      {tool_name, length(successful_usages)}
    end)
    |> Enum.into(%{})
  end
  
  defp calculate_agent_tool_score(agent, tool, usage_history) do
    # Calculate personalized score for agent-tool combination
    base_score = case Registry.get_metrics(tool.module) do
      {:ok, metrics} -> Registry.Metrics.quality_score(metrics)
      _ -> 50.0
    end
    
    # Adjust based on agent's usage history
    usage_adjustment = calculate_usage_adjustment(agent, tool, usage_history)
    
    # Adjust based on agent preferences
    preference_adjustment = calculate_preference_adjustment(agent, tool)
    
    # Combine scores
    final_score = base_score * 0.4 + usage_adjustment * 0.4 + preference_adjustment * 0.2
    
    Float.round(final_score, 2)
  end
  
  defp calculate_usage_adjustment(agent, tool, usage_history) do
    tool_usages = Enum.filter(usage_history, fn usage -> usage.tool_name == tool.name end)
    
    if Enum.empty?(tool_usages) do
      50.0  # Neutral score for unused tools
    else
      success_rate = Enum.count(tool_usages, & &1.success) / length(tool_usages)
      usage_frequency = length(tool_usages)
      
      # Higher score for frequently used and successful tools
      (success_rate * 80) + min(usage_frequency * 5, 20)
    end
  end
  
  defp calculate_preference_adjustment(agent, tool) do
    preferences = agent.preferences || %{}
    
    cond do
      tool.name in (preferences[:preferred_tools] || []) -> 90.0
      tool.name in (preferences[:successful_tools] || []) -> 80.0
      tool.category in (preferences[:preferred_categories] || []) -> 70.0
      Enum.any?(tool.tags, fn tag -> tag in (preferences[:preferred_tags] || []) end) -> 60.0
      true -> 50.0
    end
  end
  
  defp get_recommendation_reason(agent, tool, usage_history) do
    cond do
      tool.name in (agent.preferences[:preferred_tools] || []) ->
        "Frequently used by you"
        
      tool.name in (agent.preferences[:successful_tools] || []) ->
        "High success rate in your past usage"
        
      Enum.any?(usage_history, fn usage -> usage.tool_name == tool.name and usage.success end) ->
        "Successfully used by you before"
        
      true ->
        "High quality tool recommended based on your preferences"
    end
  end
  
  defp extract_error_type({:error, reason}) when is_binary(reason), do: :string_error
  defp extract_error_type({:error, reason}) when is_atom(reason), do: reason
  defp extract_error_type({:error, %{code: code}}), do: String.to_atom(code)
  defp extract_error_type(_), do: :unknown_error
  
  defp extract_frequently_used_tools(usage_history) do
    usage_history
    |> Enum.group_by(& &1.tool_name)
    |> Enum.filter(fn {_tool, usages} -> length(usages) >= 3 end)
    |> Enum.map(fn {tool_name, _usages} ->
      case Registry.get_tool(tool_name) do
        {:ok, tool} -> tool
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
  
  defp extract_high_success_tools(usage_history) do
    usage_history
    |> Enum.group_by(& &1.tool_name)
    |> Enum.filter(fn {_tool, usages} ->
      success_rate = Enum.count(usages, & &1.success) / length(usages)
      success_rate >= 0.8 and length(usages) >= 2
    end)
    |> Enum.map(fn {tool_name, _usages} ->
      case Registry.get_tool(tool_name) do
        {:ok, tool} -> tool
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
  
  defp extract_composition_tools(agent) do
    # Get tools from successful compositions
    Agents.get_composition_history(agent)
    |> Enum.flat_map(fn composition ->
      composition.tools
      |> Enum.map(fn tool_spec ->
        tool_name = tool_spec[:tool] || tool_spec["tool"]
        case Registry.get_tool(tool_name) do
          {:ok, tool} -> tool
          _ -> nil
        end
      end)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.name)
  end
end
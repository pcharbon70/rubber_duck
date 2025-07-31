defmodule RubberDuck.Agents.ConversationRouterAgent do
  @moduledoc """
  Autonomous agent that routes incoming conversations to appropriate engines.
  
  This agent:
  - Classifies incoming queries using QuestionClassifier
  - Routes conversations based on intent and complexity
  - Maintains routing metrics and circuit breakers
  - Emits routing decisions as signals
  - Supports dynamic routing rules
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "conversation_router",
    description: "Routes conversations to appropriate engines based on intent and complexity",
    schema: [
      # Routing configuration
      routing_table: [
        type: :map,
        default: %{
          simple: "simple_conversation",
          complex: "complex_conversation",
          analysis: "analysis_conversation",
          generation: "generation_conversation",
          problem_solver: "problem_solver",
          multi_step: "multi_step_conversation",
          planning: "planning_conversation"
        }
      ],
      
      # Routing rules - can be updated dynamically
      routing_rules: [
        type: {:list, :map},
        default: [
          %{
            keywords: ["plan", "planning", "roadmap", "strategy", "organize", "decompose", "task list", "project"],
            route: :planning,
            priority: 100
          },
          %{
            keywords: ["analyze", "review", "check", "inspect", "examine"],
            route: :analysis,
            priority: 90
          },
          %{
            keywords: ["generate", "create", "write", "build", "implement"],
            exclude: ["plan", "roadmap"],
            route: :generation,
            priority: 90
          },
          %{
            keywords: ["debug", "fix", "error", "issue", "problem", "troubleshoot"],
            route: :problem_solver,
            priority: 85
          }
        ]
      ],
      
      # Circuit breaker configuration
      circuit_breakers: [type: :map, default: %{}],
      circuit_breaker_config: [
        type: :map,
        default: %{
          failure_threshold: 5,
          reset_timeout: 60_000,
          half_open_requests: 3
        }
      ],
      
      # Metrics
      metrics: [
        type: :map,
        default: %{
          total_requests: 0,
          routes_used: %{},
          classification_times: [],
          routing_times: [],
          failures: %{}
        }
      ],
      
      # Context preservation
      context_cache: [type: :map, default: %{}],
      context_ttl: [type: :pos_integer, default: 300_000], # 5 minutes
      
      # Default route for unmatched queries
      default_route: [type: :atom, default: :complex]
    ]
  
  require Logger
  alias RubberDuck.CoT.QuestionClassifier
  
  @impl true
  def handle_signal(agent, %{"type" => "conversation_route_request"} = signal) do
    start_time = System.monotonic_time(:millisecond)
    
    with {:ok, data} <- validate_routing_request(signal["data"]),
         {:ok, classification} <- classify_query(data, agent),
         {:ok, route} <- determine_route(classification, data, agent),
         {:ok, agent} <- update_metrics(agent, route, start_time) do
      
      # Emit routing decision
      signal = Jido.Signal.new!(%{
        type: "conversation.route.response",
        source: "agent:#{agent.id}",
        data: %{
          request_id: data["request_id"],
          route: agent.state.routing_table[route],
          classification: %{
            complexity: classification.complexity,
            question_type: classification.question_type,
            intent: to_string(route),
            confidence: classification.confidence || 0.9,
            explanation: classification.explanation
          },
          context_id: generate_context_id(data),
          timestamp: DateTime.utc_now()
        }
      })
      emit_signal(agent, signal)
      {:ok, agent}
    else
      {:error, reason} ->
        handle_routing_error(agent, signal, reason)
    end
  end
  
  def handle_signal(agent, %{"type" => "update_routing_rules"} = signal) do
    case validate_routing_rules(signal["data"]["rules"]) do
      {:ok, rules} ->
        agent = update_state(agent, %{routing_rules: rules})
        Logger.info("Updated routing rules for agent #{agent.id}")
        {:ok, agent}
      {:error, reason} ->
        Logger.error("Invalid routing rules: #{inspect(reason)}")
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "get_routing_metrics"} = _signal) do
    signal = Jido.Signal.new!(%{
      type: "conversation.routing.metrics",
      source: "agent:#{agent.id}",
      data: Map.merge(agent.state.metrics, %{
        timestamp: DateTime.utc_now()
      })
    })
    emit_signal(agent, signal)
    {:ok, agent}
  end
  
  def handle_signal(agent, signal) do
    # Let parent handle unknown signals
    super(agent, signal)
  end
  
  # Private functions
  
  defp validate_routing_request(data) when is_map(data) do
    required_fields = ["query", "request_id"]
    
    missing_fields = Enum.filter(required_fields, &(not Map.has_key?(data, &1)))
    
    if Enum.empty?(missing_fields) do
      {:ok, data}
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end
  
  defp validate_routing_request(_), do: {:error, :invalid_request_data}
  
  defp classify_query(data, agent) do
    query = data["query"]
    context = Map.get(data, "context", %{})
    
    # Get cached context if available
    context_id = generate_context_id(data)
    cached_context = get_cached_context(agent, context_id)
    merged_context = Map.merge(cached_context, context)
    
    # Use QuestionClassifier
    complexity = QuestionClassifier.classify(query, merged_context)
    question_type = QuestionClassifier.determine_question_type(query, merged_context)
    explanation = QuestionClassifier.explain_classification(query, merged_context)
    
    # Calculate confidence based on keyword matches
    confidence = calculate_confidence(query, agent.state.routing_rules)
    
    {:ok, %{
      complexity: complexity,
      question_type: question_type,
      explanation: explanation,
      confidence: confidence
    }}
  end
  
  defp determine_route(classification, data, agent) do
    query_lower = String.downcase(data["query"])
    rules = agent.state.routing_rules
    
    # Find best matching rule
    matched_rule = rules
      |> Enum.filter(&rule_matches?(query_lower, &1))
      |> Enum.max_by(& &1.priority, fn -> nil end)
    
    route = if matched_rule do
      matched_rule.route
    else
      # Fallback to classification-based routing
      case classification.question_type do
        :multi_step -> :multi_step
        :factual -> :simple
        :basic_code -> :simple
        :straightforward -> :simple
        :complex_problem -> :complex
        _ -> agent.state.default_route
      end
    end
    
    # Check circuit breaker
    case check_circuit_breaker(agent, route) do
      :open ->
        Logger.warning("Circuit breaker open for route: #{route}")
        {:ok, agent.state.default_route}
      _ ->
        {:ok, route}
    end
  end
  
  defp rule_matches?(query, rule) do
    keywords_match = if rule[:keywords] do
      Enum.any?(rule.keywords, &String.contains?(query, &1))
    else
      true
    end
    
    exclude_match = if rule[:exclude] do
      not Enum.any?(rule.exclude, &String.contains?(query, &1))
    else
      true
    end
    
    keywords_match and exclude_match
  end
  
  defp calculate_confidence(query, rules) do
    query_lower = String.downcase(query)
    
    matched_rules = Enum.filter(rules, &rule_matches?(query_lower, &1))
    
    if length(matched_rules) > 0 do
      # Higher confidence with more specific matches
      max_priority = matched_rules |> Enum.map(& &1.priority) |> Enum.max()
      min(0.7 + (max_priority / 300), 0.99)
    else
      0.6 # Base confidence for classification-only routing
    end
  end
  
  defp update_metrics(agent, route, start_time) do
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    metrics = agent.state.metrics
    
    updated_metrics = %{
      metrics |
      total_requests: metrics.total_requests + 1,
      routes_used: Map.update(metrics.routes_used, to_string(route), 1, &(&1 + 1)),
      routing_times: [duration | Enum.take(metrics.routing_times, 99)]
    }
    
    {:ok, update_state(agent, %{metrics: updated_metrics})}
  end
  
  defp handle_routing_error(agent, signal, reason) do
    Logger.error("Routing error: #{inspect(reason)}")
    
    signal = Jido.Signal.new!(%{
      type: "conversation.route.error",
      source: "agent:#{agent.id}",
      data: %{
        request_id: get_in(signal, ["data", "request_id"]),
        error: inspect(reason),
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    # Update failure metrics
    failure_key = inspect(reason)
    updated_metrics = %{
      agent.state.metrics | 
      failures: Map.update(agent.state.metrics.failures, failure_key, 1, &(&1 + 1))
    }
    {:ok, update_state(agent, %{metrics: updated_metrics})}
  end
  
  defp check_circuit_breaker(agent, route) do
    breaker = Map.get(agent.state.circuit_breakers, route, %{state: :closed, failures: 0})
    breaker.state
  end
  
  defp generate_context_id(data) do
    # Generate context ID from user_id or session_id
    user_id = Map.get(data, "user_id", "anonymous")
    session_id = Map.get(data, "session_id", "default")
    "#{user_id}:#{session_id}"
  end
  
  defp get_cached_context(agent, context_id) do
    Map.get(agent.state.context_cache, context_id, %{})
  end
  
  defp validate_routing_rules(rules) when is_list(rules) do
    if Enum.all?(rules, &valid_rule?/1) do
      {:ok, rules}
    else
      {:error, :invalid_rule_format}
    end
  end
  
  defp validate_routing_rules(_), do: {:error, :rules_must_be_list}
  
  defp valid_rule?(rule) when is_map(rule) do
    Map.has_key?(rule, :route) and
    Map.has_key?(rule, :priority) and
    (Map.has_key?(rule, :keywords) or Map.has_key?(rule, :patterns))
  end
  
  defp valid_rule?(_), do: false
end
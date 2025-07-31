defmodule RubberDuck.Jido.Actions.Conversation.Router.ConversationRouteRequestAction do
  @moduledoc """
  Action for handling conversation routing requests.
  
  This action manages conversation routing by:
  - Classifying incoming queries using QuestionClassifier
  - Applying routing rules and circuit breaker logic
  - Determining appropriate conversation engine
  - Emitting routing decisions and maintaining metrics
  """
  
  use Jido.Action,
    name: "conversation_route_request",
    description: "Routes conversations to appropriate engines based on classification and rules",
    schema: [
      query: [type: :string, required: true, doc: "Query to classify and route"],
      request_id: [type: :string, required: true, doc: "Unique request identifier"],
      context: [type: :map, default: %{}, doc: "Additional context for classification"],
      user_id: [type: :string, default: nil, doc: "User identifier for context caching"],
      session_id: [type: :string, default: nil, doc: "Session identifier for context caching"]
    ]

  require Logger
  
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  alias RubberDuck.CoT.QuestionClassifier

  @impl true
  def run(params, context) do
    agent = context.agent
    start_time = System.monotonic_time(:millisecond)
    
    with {:ok, classification} <- classify_query(params, agent),
         {:ok, route} <- determine_route(classification, params, agent),
         {:ok, updated_agent} <- update_metrics(agent, route, start_time),
         {:ok, _} <- emit_routing_response(updated_agent, params, classification, route) do
      
      {:ok, %{
        routed: true,
        route: agent.state.routing_table[route],
        classification: %{
          complexity: classification.complexity,
          question_type: classification.question_type,
          intent: to_string(route),
          confidence: classification.confidence
        }
      }, %{agent: updated_agent}}
    else
      {:error, reason} ->
        handle_routing_error(agent, params, reason)
    end
  end

  # Private functions

  defp classify_query(params, agent) do
    # Get cached context if available
    context_id = generate_context_id(params)
    cached_context = get_cached_context(agent, context_id)
    merged_context = Map.merge(cached_context, params.context)
    
    # Use QuestionClassifier
    complexity = QuestionClassifier.classify(params.query, merged_context)
    question_type = QuestionClassifier.determine_question_type(params.query, merged_context)
    explanation = QuestionClassifier.explain_classification(params.query, merged_context)
    
    # Calculate confidence based on keyword matches
    confidence = calculate_confidence(params.query, agent.state.routing_rules)
    
    {:ok, %{
      complexity: complexity,
      question_type: question_type,
      explanation: explanation,
      confidence: confidence
    }}
  end

  defp determine_route(classification, params, agent) do
    query_lower = String.downcase(params.query)
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
    
    updated_metrics = %{
      agent.state.metrics |
      total_requests: agent.state.metrics.total_requests + 1,
      routes_used: Map.update(agent.state.metrics.routes_used, to_string(route), 1, &(&1 + 1)),
      routing_times: [duration | Enum.take(agent.state.metrics.routing_times, 99)]
    }
    
    state_updates = %{metrics: updated_metrics}
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
      {:error, reason} -> {:error, reason}
    end
  end

  defp emit_routing_response(agent, params, classification, route) do
    signal_params = %{
      signal_type: "conversation.route.response",
      data: %{
        request_id: params.request_id,
        route: agent.state.routing_table[route],
        classification: %{
          complexity: classification.complexity,
          question_type: classification.question_type,
          intent: to_string(route),
          confidence: classification.confidence,
          explanation: classification.explanation
        },
        context_id: generate_context_id(params),
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp handle_routing_error(agent, params, reason) do
    Logger.error("Routing error: #{inspect(reason)}")
    
    # Update failure metrics
    failure_key = inspect(reason)
    updated_metrics = %{
      agent.state.metrics | 
      failures: Map.update(agent.state.metrics.failures, failure_key, 1, &(&1 + 1))
    }
    
    state_updates = %{metrics: updated_metrics}
    
    with {:ok, _, %{agent: updated_agent}} <- UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}),
         {:ok, _} <- emit_error_signal(updated_agent, params, reason) do
      {:error, reason}
    else
      {:error, update_error} ->
        Logger.error("Failed to update metrics after routing error: #{inspect(update_error)}")
        {:error, reason}
    end
  end

  defp emit_error_signal(agent, params, reason) do
    signal_params = %{
      signal_type: "conversation.route.error",
      data: %{
        request_id: params.request_id,
        error: inspect(reason),
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp check_circuit_breaker(agent, route) do
    breaker = Map.get(agent.state.circuit_breakers, route, %{state: :closed, failures: 0})
    breaker.state
  end

  defp generate_context_id(params) do
    user_id = params.user_id || "anonymous"
    session_id = params.session_id || "default"
    "#{user_id}:#{session_id}"
  end

  defp get_cached_context(agent, context_id) do
    Map.get(agent.state.context_cache, context_id, %{})
  end
end
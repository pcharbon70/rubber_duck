defmodule RubberDuck.Jido.Adapters.SignalAdapter do
  @moduledoc """
  Adapter for routing CloudEvents signals to Jido actions.
  
  This adapter provides a comprehensive signal-to-action mapping system
  with support for:
  - Pattern-based routing
  - Parameter extraction and transformation
  - Action composition
  - Error handling and fallbacks
  - Signal filtering and preprocessing
  """
  
  alias RubberDuck.Jido.Actions.Base.ComposeAction
  
  require Logger
  
  @type signal_handler :: (Jido.Signal.t() -> {:ok, map()} | {:error, term()})
  @type action_mapping :: {module(), atom() | function()}
  @type routing_rule :: %{
    pattern: String.t() | Regex.t(),
    action: module() | [module()],
    extractor: atom() | function() | nil,
    filter: function() | nil,
    priority: integer()
  }
  
  # Module attributes for performance
  @default_priority 50
  
  @doc """
  Creates a new signal adapter with routing rules.
  """
  def new(opts \\ []) do
    %{
      routing_rules: opts[:routing_rules] || [],
      preprocessors: opts[:preprocessors] || [],
      error_handler: opts[:error_handler] || &default_error_handler/2,
      telemetry_enabled: opts[:telemetry_enabled] != false
    }
  end
  
  @doc """
  Routes a signal to the appropriate action(s).
  """
  def route_signal(adapter, agent_id, signal) do
    start_time = System.monotonic_time()
    
    # Get agent
    with {:ok, agent} <- get_agent(agent_id),
         # Preprocess signal
         {:ok, processed_signal} <- preprocess_signal(adapter, signal),
         # Find matching rules
         rules <- find_matching_rules(adapter, processed_signal),
         # Execute actions
         {:ok, result} <- execute_routing_rules(adapter, agent, processed_signal, rules) do
      
      # Emit telemetry
      if adapter.telemetry_enabled do
        emit_routing_telemetry(start_time, agent_id, signal, :success)
      end
      
      {:ok, result}
    else
      {:error, reason} = error ->
        # Handle error
        adapter.error_handler.(signal, reason)
        
        if adapter.telemetry_enabled do
          emit_routing_telemetry(start_time, agent_id, signal, :error)
        end
        
        error
    end
  end
  
  @doc """
  Adds a routing rule to the adapter.
  """
  def add_rule(adapter, rule) do
    validated_rule = validate_rule(rule)
    %{adapter | routing_rules: insert_by_priority(adapter.routing_rules, validated_rule)}
  end
  
  @doc """
  Creates a routing rule.
  """
  def rule(pattern, action, opts \\ []) do
    %{
      pattern: compile_pattern(pattern),
      action: action,
      extractor: opts[:extractor],
      filter: opts[:filter],
      priority: opts[:priority] || @default_priority,
      name: opts[:name] || generate_rule_name(pattern, action)
    }
  end
  
  @doc """
  Creates a parameter extractor function from a mapping.
  """
  def param_extractor(mapping) when is_map(mapping) do
    fn signal ->
      data = signal["data"] || %{}
      
      Enum.reduce(mapping, %{}, fn {param_key, data_path}, acc ->
        value = get_in_signal(data, data_path)
        if value != nil do
          Map.put(acc, param_key, value)
        else
          acc
        end
      end)
    end
  end
  
  @doc """
  Creates a signal filter function.
  """
  def filter(conditions) when is_list(conditions) do
    fn signal ->
      Enum.all?(conditions, fn
        {:field, path, expected} ->
          get_in_signal(signal, path) == expected
          
        {:match, path, pattern} ->
          value = get_in_signal(signal, path)
          pattern_matches?(value, pattern)
          
        fun when is_function(fun, 1) ->
          fun.(signal)
      end)
    end
  end
  
  # Private functions
  
  defp get_agent(agent_id) do
    case RubberDuck.Jido.Proper.Core.get_agent(agent_id) do
      {:ok, agent} -> {:ok, agent}
      {:error, _} -> {:error, :agent_not_found}
    end
  end
  
  defp preprocess_signal(adapter, signal) do
    Enum.reduce_while(adapter.preprocessors, {:ok, signal}, fn preprocessor, {:ok, sig} ->
      case preprocessor.(sig) do
        {:ok, processed} -> {:cont, {:ok, processed}}
        {:error, _} = error -> {:halt, error}
        processed -> {:cont, {:ok, processed}}
      end
    end)
  end
  
  defp find_matching_rules(adapter, signal) do
    signal_type = signal["type"] || signal[:type]
    
    adapter.routing_rules
    |> Enum.filter(fn rule ->
      pattern_matches?(signal_type, rule.pattern) &&
        (rule.filter == nil || rule.filter.(signal))
    end)
    |> case do
      [] -> []
      rules -> rules
    end
  end
  
  defp execute_routing_rules(adapter, agent, signal, rules) do
    case rules do
      [] ->
        {:error, :no_matching_rules}
        
      [single_rule] ->
        # Single matching rule
        execute_rule(adapter, agent, signal, single_rule)
        
      multiple_rules ->
        # Multiple rules - compose actions
        compose_multiple_rules(adapter, agent, signal, multiple_rules)
    end
  end
  
  defp execute_rule(_adapter, agent, signal, rule) do
    case rule.action do
      action when is_atom(action) ->
        # Single action
        params = extract_params(rule.extractor, signal)
        execute_single_action(action, params, agent)
        
      actions when is_list(actions) ->
        # Multiple actions in sequence
        action_defs = Enum.map(actions, fn action ->
          %{
            action: action,
            params: extract_params(rule.extractor, signal)
          }
        end)
        
        ComposeAction.run(
          %{actions: action_defs},
          %{agent: agent, signal: signal}
        )
    end
  end
  
  defp compose_multiple_rules(_adapter, agent, signal, rules) do
    # Convert rules to action definitions
    action_defs = Enum.flat_map(rules, fn rule ->
      params = extract_params(rule.extractor, signal)
      
      case rule.action do
        action when is_atom(action) ->
          [%{action: action, params: params}]
          
        actions when is_list(actions) ->
          Enum.map(actions, &%{action: &1, params: params})
      end
    end)
    
    # Execute composed actions
    ComposeAction.run(
      %{actions: action_defs, stop_on_error: false},
      %{agent: agent, signal: signal}
    )
  end
  
  defp execute_single_action(action_module, params, agent) do
    context = %{
      agent: agent,
      timestamp: DateTime.utc_now()
    }
    
    case action_module.run(params, context) do
      {:ok, result, %{agent: updated_agent}} ->
        {:ok, %{agent: updated_agent, results: [result]}}
        
      {:error, _} = error ->
        error
    end
  end
  
  defp extract_params(nil, signal), do: signal["data"] || %{}
  
  defp extract_params(extractor, signal) when is_atom(extractor) do
    # Assume it's a function name on the signal's agent module
    apply(RubberDuck.Agents, extractor, [signal])
  rescue
    _ -> signal["data"] || %{}
  end
  
  defp extract_params(extractor, signal) when is_function(extractor, 1) do
    extractor.(signal)
  end
  
  defp compile_pattern(pattern) when is_binary(pattern) do
    if String.contains?(pattern, "*") do
      # Convert wildcard to regex
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("*", ".*")
      |> then(&"^#{&1}$")
      |> Regex.compile!()
    else
      # Exact match
      pattern
    end
  end
  
  defp compile_pattern(%Regex{} = pattern), do: pattern
  
  defp pattern_matches?(value, pattern) when is_binary(pattern) and is_binary(value) do
    value == pattern
  end
  
  defp pattern_matches?(value, %Regex{} = pattern) when is_binary(value) do
    Regex.match?(pattern, value)
  end
  
  defp pattern_matches?(_value, _pattern), do: false
  
  defp validate_rule(rule) do
    unless Map.has_key?(rule, :pattern) && Map.has_key?(rule, :action) do
      raise ArgumentError, "Rule must have :pattern and :action"
    end
    
    Map.put_new(rule, :priority, @default_priority)
  end
  
  defp insert_by_priority(rules, new_rule) do
    {before, after_} = Enum.split_while(rules, fn rule ->
      rule.priority >= new_rule.priority
    end)
    
    before ++ [new_rule] ++ after_
  end
  
  defp generate_rule_name(pattern, action) do
    action_name = case action do
      module when is_atom(module) -> 
        module |> Module.split() |> List.last()
      list when is_list(list) ->
        "Composite"
    end
    
    pattern_str = case pattern do
      %Regex{source: source} -> source
      str when is_binary(str) -> str
    end
    
    "#{pattern_str}_to_#{action_name}"
  end
  
  defp get_in_signal(signal, path) when is_list(path) do
    get_in(signal, path)
  end
  
  defp get_in_signal(signal, path) when is_binary(path) do
    keys = String.split(path, ".")
    get_in(signal, keys)
  end
  
  defp default_error_handler(signal, reason) do
    Logger.error("""
    Signal routing failed
    Signal: #{inspect(signal["type"])}
    Reason: #{inspect(reason)}
    """)
  end
  
  defp emit_routing_telemetry(start_time, agent_id, signal, status) do
    duration = System.monotonic_time() - start_time
    
    :telemetry.execute(
      [:rubber_duck, :signal, :routing],
      %{duration: duration},
      %{
        agent_id: agent_id,
        signal_type: signal["type"] || signal[:type],
        status: status
      }
    )
  end
end
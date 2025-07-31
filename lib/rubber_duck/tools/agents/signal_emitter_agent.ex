defmodule RubberDuck.Tools.Agents.SignalEmitterAgent do
  @moduledoc """
  Agent for the SignalEmitter tool.
  
  Manages signal emission, routing, and orchestration throughout the RubberDuck system.
  Handles signal broadcasting, filtering, transformation, and delivery confirmation.
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :signal_emitter,
    name: "signal_emitter_agent",
    description: "Manages signal emission, routing, and orchestration in the system",
    schema: [
      # Signal tracking and management
      active_signals: [type: :map, default: %{}],
      signal_queue: [type: {:list, :map}, default: []],
      emission_history: [type: {:list, :map}, default: []],
      max_history: [type: :integer, default: 200],
      
      # Routing and filtering
      signal_routes: [type: :map, default: %{}],
      filters: [type: {:list, :map}, default: []],
      transformations: [type: :map, default: %{}],
      
      # Delivery tracking
      delivery_confirmations: [type: :map, default: %{}],
      failed_deliveries: [type: {:list, :map}, default: []],
      retry_config: [type: :map, default: %{
        max_retries: 3,
        retry_delay: 1000,
        backoff_multiplier: 2
      }],
      
      # Signal patterns and templates
      signal_templates: [type: :map, default: %{
        notification: %{
          type: "system.notification",
          source: "system",
          data: %{message: "", priority: :normal}
        },
        event: %{
          type: "system.event",
          source: "system", 
          data: %{event_type: "", payload: %{}}
        },
        command: %{
          type: "system.command",
          source: "system",
          data: %{command: "", parameters: %{}}
        }
      }]
    ]
  
  # Define additional actions for this agent
  @impl true
  def additional_actions do
    [
      __MODULE__.BroadcastSignalAction,
      __MODULE__.RouteSignalAction,
      __MODULE__.FilterSignalsAction,
      __MODULE__.TransformSignalAction,
      __MODULE__.ConfirmDeliveryAction,
      __MODULE__.ManageSignalTemplatesAction
    ]
  end
  
  # Action modules
  defmodule BroadcastSignalAction do
    @moduledoc false
    use Jido.Action,
      name: "broadcast_signal",
      description: "Broadcast signal to multiple recipients",
      schema: [
        signal: [type: :map, required: true],
        recipients: [
          type: {:list, :string},  
          required: true,
          doc: "List of recipient addresses or patterns"
        ],
        broadcast_type: [
          type: :atom,
          values: [:fanout, :round_robin, :priority],
          default: :fanout
        ],
        delivery_confirmation: [type: :boolean, default: false],
        timeout: [type: :integer, default: 5000]
      ]
    
    alias RubberDuck.ToolSystem.Executor
    
    @impl true
    def run(params, context) do
      signal = params.signal
      recipients = params.recipients
      broadcast_type = params.broadcast_type
      
      # Validate signal format
      case validate_signal_format(signal) do
        {:ok, validated_signal} ->
          # Execute broadcast based on type
          case broadcast_type do
            :fanout -> broadcast_fanout(validated_signal, recipients, params, context)
            :round_robin -> broadcast_round_robin(validated_signal, recipients, params, context)
            :priority -> broadcast_priority(validated_signal, recipients, params, context)
          end
          
        {:error, reason} ->
          {:error, {:invalid_signal, reason}}
      end
    end
    
    defp validate_signal_format(signal) do
      required_fields = [:type, :source]
      
      missing_fields = required_fields -- Map.keys(signal)
      
      if length(missing_fields) == 0 do
        {:ok, ensure_signal_id(signal)}
      else
        {:error, "Missing required fields: #{inspect(missing_fields)}"}
      end
    end
    
    defp ensure_signal_id(signal) do
      if signal[:id] do
        signal
      else
        Map.put(signal, :id, generate_signal_id())
      end
    end
    
    defp generate_signal_id do
      "signal_#{System.unique_integer([:positive, :monotonic])}_#{System.system_time(:millisecond)}"
    end
    
    defp broadcast_fanout(signal, recipients, params, context) do
      # Send to all recipients simultaneously
      tasks = Enum.map(recipients, fn recipient ->
        Task.async(fn ->
          deliver_signal(signal, recipient, params, context)
        end)
      end)
      
      results = Task.await_many(tasks, params.timeout)
      
      successful = Enum.count(results, &match?({:ok, _}, &1))
      failed = Enum.count(results, &match?({:error, _}, &1))
      
      {:ok, %{
        broadcast_type: :fanout,
        signal_id: signal.id,
        recipients_targeted: length(recipients),
        successful_deliveries: successful,
        failed_deliveries: failed,
        delivery_results: Enum.zip(recipients, results) |> Map.new()
      }}
    end
    
    defp broadcast_round_robin(signal, recipients, params, context) do
      # Send to recipients in round-robin fashion
      if length(recipients) == 0 do
        {:error, "No recipients available"}
      else
        # For round-robin, we'll just pick the first available recipient
        # In a real implementation, this would maintain state for rotation
        recipient = hd(recipients)
        
        case deliver_signal(signal, recipient, params, context) do
          {:ok, result} ->
            {:ok, %{
              broadcast_type: :round_robin,
              signal_id: signal.id,
              selected_recipient: recipient,
              delivery_result: result
            }}
            
          {:error, reason} ->
            # Try next recipient if available
            remaining = tl(recipients)
            if length(remaining) > 0 do
              broadcast_round_robin(signal, remaining, params, context)
            else
              {:error, {:all_recipients_failed, reason}}
            end
        end
      end
    end
    
    defp broadcast_priority(signal, recipients, params, context) do
      # Send to recipients in priority order (first successful wins)
      case try_recipients_in_order(signal, recipients, params, context) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
    
    defp try_recipients_in_order(_signal, [], _params, _context) do
      {:error, "No recipients available"}
    end
    
    defp try_recipients_in_order(signal, [recipient | remaining], params, context) do
      case deliver_signal(signal, recipient, params, context) do
        {:ok, result} ->
          {:ok, %{
            broadcast_type: :priority,
            signal_id: signal.id,
            successful_recipient: recipient,
            delivery_result: result
          }}
          
        {:error, _reason} ->
          try_recipients_in_order(signal, remaining, params, context)
      end
    end
    
    defp deliver_signal(signal, recipient, params, _context) do
      # In real implementation, this would use the actual signal delivery mechanism
      # For now, we simulate delivery
      
      try do
        # Simulate signal delivery via Executor
        delivery_params = %{
          signal: signal,
          recipient: recipient,
          delivery_confirmation: params.delivery_confirmation,
          timeout: params.timeout
        }
        
        case Executor.execute(:signal_emitter, delivery_params) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      rescue
        error -> {:error, Exception.message(error)}
      end
    end
  end
  
  defmodule RouteSignalAction do
    @moduledoc false
    use Jido.Action,
      name: "route_signal",
      description: "Route signal based on routing rules",
      schema: [
        signal: [type: :map, required: true],
        routing_rules: [
          type: {:list, :map},
          default: [],
          doc: "List of routing rule objects"
        ],
        default_route: [type: :string, required: false]
      ]
    
    @impl true
    def run(params, context) do
      signal = params.signal
      routing_rules = params.routing_rules ++ get_agent_routes(context.agent)
      default_route = params.default_route
      
      case find_matching_route(signal, routing_rules) do
        {:ok, route} ->
          {:ok, %{
            signal_id: signal[:id],
            matched_route: route,
            routing_decision: :rule_matched,
            destination: route.destination
          }}
          
        :no_match ->
          if default_route do
            {:ok, %{
              signal_id: signal[:id],
              matched_route: nil,
              routing_decision: :default_route,
              destination: default_route
            }}
          else
            {:error, "No matching route found and no default route specified"}
          end
      end
    end
    
    defp get_agent_routes(agent) do
      agent.state.signal_routes
      |> Map.values()
      |> List.flatten()
    end
    
    defp find_matching_route(signal, routing_rules) do
      Enum.find_value(routing_rules, :no_match, fn rule ->
        if matches_rule?(signal, rule) do
          {:ok, rule}
        else
          false
        end
      end)
    end
    
    defp matches_rule?(signal, rule) do
      checks = [
        check_signal_type(signal, rule),
        check_signal_source(signal, rule),
        check_signal_data(signal, rule)
      ]
      
      Enum.all?(checks, & &1)
    end
    
    defp check_signal_type(signal, rule) do
      if rule[:type_pattern] do
        signal_type = signal[:type] || ""
        match_pattern?(signal_type, rule.type_pattern)
      else
        true
      end
    end
    
    defp check_signal_source(signal, rule) do
      if rule[:source_pattern] do
        signal_source = signal[:source] || ""
        match_pattern?(signal_source, rule.source_pattern)
      else
        true
      end
    end
    
    defp check_signal_data(signal, rule) do
      if rule[:data_conditions] do
        signal_data = signal[:data] || %{}
        check_data_conditions(signal_data, rule.data_conditions)
      else
        true
      end
    end
    
    defp match_pattern?(value, pattern) when is_binary(pattern) do
      # Simple wildcard matching (* and ?)
      regex_pattern = pattern
      |> String.replace("*", ".*")
      |> String.replace("?", ".")
      
      Regex.match?(~r/^#{regex_pattern}$/, value)
    end
    
    defp match_pattern?(value, pattern) when is_list(pattern) do
      value in pattern
    end
    
    defp match_pattern?(value, pattern), do: value == pattern
    
    defp check_data_conditions(data, conditions) when is_map(conditions) do
      Enum.all?(conditions, fn {key, expected_value} ->
        actual_value = data[key] || data[to_string(key)]
        actual_value == expected_value
      end)
    end
    
    defp check_data_conditions(_data, _conditions), do: true
  end
  
  defmodule FilterSignalsAction do
    @moduledoc false
    use Jido.Action,
      name: "filter_signals",
      description: "Filter signals based on criteria",
      schema: [
        signals: [type: {:list, :map}, required: true],
        filter_criteria: [type: :map, required: true],
        filter_mode: [
          type: :atom,
          values: [:include, :exclude],
          default: :include
        ]
      ]
    
    @impl true
    def run(params, _context) do
      signals = params.signals
      criteria = params.filter_criteria
      mode = params.filter_mode
      
      filtered_signals = case mode do
        :include -> Enum.filter(signals, &matches_criteria?(&1, criteria))
        :exclude -> Enum.reject(signals, &matches_criteria?(&1, criteria))
      end
      
      {:ok, %{
        filter_mode: mode,
        original_count: length(signals),
        filtered_count: length(filtered_signals),
        signals: filtered_signals,
        filter_criteria: criteria
      }}
    end
    
    defp matches_criteria?(signal, criteria) do
      Enum.all?(criteria, fn {field, expected} ->
        check_field_criteria(signal, field, expected)
      end)
    end
    
    defp check_field_criteria(signal, :type, expected) do
      signal_type = signal[:type] || signal["type"] || ""
      match_criteria_value(signal_type, expected)
    end
    
    defp check_field_criteria(signal, :source, expected) do
      signal_source = signal[:source] || signal["source"] || ""
      match_criteria_value(signal_source, expected)
    end
    
    defp check_field_criteria(signal, :priority, expected) do  
      signal_priority = get_in(signal, [:data, :priority]) || 
                       get_in(signal, ["data", "priority"]) || 
                       :normal
      match_criteria_value(signal_priority, expected)
    end
    
    defp check_field_criteria(signal, field, expected) when is_atom(field) do
      value = signal[field] || signal[to_string(field)]
      match_criteria_value(value, expected)
    end
    
    defp check_field_criteria(_signal, _field, _expected), do: false
    
    defp match_criteria_value(value, expected) when is_list(expected) do
      value in expected
    end
    
    defp match_criteria_value(value, expected) when is_binary(expected) and is_binary(value) do
      String.contains?(value, expected) or value == expected
    end
    
    defp match_criteria_value(value, expected), do: value == expected
  end
  
  defmodule TransformSignalAction do
    @moduledoc false
    use Jido.Action,
      name: "transform_signal",
      description: "Transform signal data and structure",
      schema: [
        signal: [type: :map, required: true],
        transformations: [
          type: {:list, :map},
          required: true,
          doc: "List of transformation operations"
        ]
      ]
    
    @impl true
    def run(params, _context) do
      signal = params.signal
      transformations = params.transformations
      
      case apply_transformations(signal, transformations) do
        {:ok, transformed_signal} ->
          {:ok, %{
            original_signal: signal,
            transformed_signal: transformed_signal,
            transformations_applied: length(transformations)
          }}
          
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp apply_transformations(signal, transformations) do
      Enum.reduce_while(transformations, {:ok, signal}, fn transformation, {:ok, current_signal} ->
        case apply_single_transformation(current_signal, transformation) do
          {:ok, new_signal} -> {:cont, {:ok, new_signal}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
    
    defp apply_single_transformation(signal, %{type: :add_field, field: field, value: value}) do
      {:ok, Map.put(signal, field, value)}
    end
    
    defp apply_single_transformation(signal, %{type: :remove_field, field: field}) do
      {:ok, Map.delete(signal, field)}
    end
    
    defp apply_single_transformation(signal, %{type: :rename_field, from: from_field, to: to_field}) do
      if Map.has_key?(signal, from_field) do
        signal
        |> Map.put(to_field, signal[from_field])
        |> Map.delete(from_field)
        |> then(&{:ok, &1})
      else
        {:error, "Field #{from_field} not found"}
      end
    end
    
    defp apply_single_transformation(signal, %{type: :modify_data, path: path, value: value}) do
      {:ok, put_in(signal, path, value)}
    end
    
    defp apply_single_transformation(signal, %{type: :add_timestamp}) do
      {:ok, Map.put(signal, :timestamp, DateTime.utc_now())}
    end
    
    defp apply_single_transformation(signal, %{type: :add_correlation_id}) do
      correlation_id = "corr_#{System.unique_integer([:positive, :monotonic])}"
      {:ok, put_in(signal, [:data, :correlation_id], correlation_id)}
    end
    
    defp apply_single_transformation(_signal, transformation) do
      {:error, "Unknown transformation type: #{inspect(transformation)}"}
    end
  end
  
  defmodule ConfirmDeliveryAction do
    @moduledoc false
    use Jido.Action,
      name: "confirm_delivery",
      description: "Handle delivery confirmations and track status",
      schema: [
        signal_id: [type: :string, required: true],
        recipient: [type: :string, required: true],
        status: [
          type: :atom,
          values: [:delivered, :failed, :pending],
          required: true
        ],
        details: [type: :map, default: %{}]
      ]
    
    @impl true
    def run(params, context) do
      signal_id = params.signal_id
      recipient = params.recipient
      status = params.status
      details = params.details
      
      # Record delivery confirmation
      confirmation = %{
        signal_id: signal_id,
        recipient: recipient,
        status: status,
        details: details,
        confirmed_at: DateTime.utc_now()
      }
      
      # Check if signal requires retry
      retry_needed = status == :failed && should_retry?(signal_id, recipient, context.agent)
      
      {:ok, %{
        confirmation: confirmation,
        retry_needed: retry_needed,
        retry_count: get_retry_count(signal_id, recipient, context.agent)
      }}
    end
    
    defp should_retry?(signal_id, recipient, agent) do
      retry_config = agent.state.retry_config
      current_retries = get_retry_count(signal_id, recipient, agent)
      
      current_retries < retry_config.max_retries
    end
    
    defp get_retry_count(signal_id, recipient, agent) do
      key = "#{signal_id}:#{recipient}"
      failed_deliveries = agent.state.failed_deliveries
      
      failed_deliveries
      |> Enum.count(fn delivery ->
        delivery[:signal_id] == signal_id && delivery[:recipient] == recipient
      end)
    end
  end
  
  defmodule ManageSignalTemplatesAction do
    @moduledoc false
    use Jido.Action,
      name: "manage_signal_templates",
      description: "Manage signal templates for common patterns",
      schema: [
        operation: [
          type: :atom,
          values: [:create, :update, :delete, :list, :get],
          required: true
        ],
        template_name: [type: :string, required: false],
        template_data: [type: :map, required: false]
      ]
    
    @impl true
    def run(params, context) do
      operation = params.operation
      template_name = params.template_name
      template_data = params.template_data
      
      case operation do
        :create -> create_template(template_name, template_data, context)
        :update -> update_template(template_name, template_data, context)
        :delete -> delete_template(template_name, context)
        :list -> list_templates(context)
        :get -> get_template(template_name, context)
      end
    end
    
    defp create_template(nil, _template_data, _context) do
      {:error, "Template name is required for create operation"}
    end
    
    defp create_template(template_name, template_data, context) do
      templates = context.agent.state.signal_templates
      
      if Map.has_key?(templates, template_name) do
        {:error, "Template #{template_name} already exists"}
      else
        {:ok, %{
          operation: :create,
          template_name: template_name,
          template_data: template_data,
          created_at: DateTime.utc_now()
        }}
      end
    end
    
    defp update_template(nil, _template_data, _context) do
      {:error, "Template name is required for update operation"}
    end
    
    defp update_template(template_name, template_data, context) do
      templates = context.agent.state.signal_templates
      
      if Map.has_key?(templates, template_name) do
        {:ok, %{
          operation: :update,
          template_name: template_name,
          template_data: template_data,
          updated_at: DateTime.utc_now()
        }}
      else
        {:error, "Template #{template_name} does not exist"}
      end
    end
    
    defp delete_template(nil, _context) do
      {:error, "Template name is required for delete operation"}
    end
    
    defp delete_template(template_name, context) do
      templates = context.agent.state.signal_templates
      
      if Map.has_key?(templates, template_name) do
        {:ok, %{
          operation: :delete,
          template_name: template_name,
          deleted_at: DateTime.utc_now()
        }}
      else
        {:error, "Template #{template_name} does not exist"}
      end
    end
    
    defp list_templates(context) do
      templates = context.agent.state.signal_templates
      
      {:ok, %{
        operation: :list,
        templates: Map.keys(templates),
        template_count: map_size(templates)
      }}
    end
    
    defp get_template(nil, _context) do
      {:error, "Template name is required for get operation"}
    end
    
    defp get_template(template_name, context) do
      templates = context.agent.state.signal_templates
      
      case Map.get(templates, template_name) do
        nil -> {:error, "Template #{template_name} not found"}
        template -> {:ok, %{
          operation: :get,
          template_name: template_name,
          template_data: template
        }}
      end
    end
  end
  
  # Tool-specific signal handlers using the new action system
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "broadcast_signal"} = signal) do
    signal_data = get_in(signal, ["data", "signal"]) || %{}
    recipients = get_in(signal, ["data", "recipients"]) || []
    broadcast_type = get_in(signal, ["data", "broadcast_type"]) || :fanout
    delivery_confirmation = get_in(signal, ["data", "delivery_confirmation"]) || false
    timeout = get_in(signal, ["data", "timeout"]) || 5000
    
    # Execute broadcast action
    {:ok, _ref} = __MODULE__.cmd_async(agent, BroadcastSignalAction, %{
      signal: signal_data,
      recipients: recipients,
      broadcast_type: broadcast_type,
      delivery_confirmation: delivery_confirmation,
      timeout: timeout
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "route_signal"} = signal) do
    signal_data = get_in(signal, ["data", "signal"]) || %{}
    routing_rules = get_in(signal, ["data", "routing_rules"]) || []
    default_route = get_in(signal, ["data", "default_route"])
    
    # Execute route action
    {:ok, _ref} = __MODULE__.cmd_async(agent, RouteSignalAction, %{
      signal: signal_data,
      routing_rules: routing_rules,
      default_route: default_route
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "filter_signals"} = signal) do
    signals = get_in(signal, ["data", "signals"]) || []
    filter_criteria = get_in(signal, ["data", "filter_criteria"]) || %{}
    filter_mode = get_in(signal, ["data", "filter_mode"]) || :include
    
    # Execute filter action
    {:ok, _ref} = __MODULE__.cmd_async(agent, FilterSignalsAction, %{
      signals: signals,
      filter_criteria: filter_criteria,
      filter_mode: filter_mode
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "transform_signal"} = signal) do
    signal_data = get_in(signal, ["data", "signal"]) || %{}
    transformations = get_in(signal, ["data", "transformations"]) || []
    
    # Execute transform action
    {:ok, _ref} = __MODULE__.cmd_async(agent, TransformSignalAction, %{
      signal: signal_data,
      transformations: transformations
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "confirm_delivery"} = signal) do
    signal_id = get_in(signal, ["data", "signal_id"])
    recipient = get_in(signal, ["data", "recipient"])
    status = get_in(signal, ["data", "status"])
    details = get_in(signal, ["data", "details"]) || %{}
    
    # Execute delivery confirmation action
    {:ok, _ref} = __MODULE__.cmd_async(agent, ConfirmDeliveryAction, %{
      signal_id: signal_id,
      recipient: recipient,
      status: status,
      details: details
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "manage_templates"} = signal) do
    operation = get_in(signal, ["data", "operation"])
    template_name = get_in(signal, ["data", "template_name"])
    template_data = get_in(signal, ["data", "template_data"])
    
    # Execute template management action
    {:ok, _ref} = __MODULE__.cmd_async(agent, ManageSignalTemplatesAction, %{
      operation: String.to_atom(operation || "list"),
      template_name: template_name,
      template_data: template_data
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, _signal), do: super(agent, _signal)
  
  # Process signal emission results
  @impl true
  def process_result(result, _context) do
    # Add emission timestamp
    Map.put(result, :emitted_at, DateTime.utc_now())
  end
  
  # Override action result handler to update signal tracking
  @impl true
  def handle_action_result(agent, ExecuteToolAction, {:ok, result}, metadata) do
    # Let parent handle the standard processing
    {:ok, agent} = super(agent, ExecuteToolAction, {:ok, result}, metadata)
    
    # Update emission history if not from cache
    if result[:from_cache] == false && result[:result] do
      emission_entry = %{
        type: :signal_emission,
        signal_data: result[:result],
        emitted_at: DateTime.utc_now(),
        metadata: metadata
      }
      
      agent = update_in(agent.state.emission_history, fn history ->
        [emission_entry | history]
        |> Enum.take(agent.state.max_history)
      end)
      
      {:ok, agent}
    else
      {:ok, agent}
    end
  end
  
  def handle_action_result(agent, BroadcastSignalAction, {:ok, result}, _metadata) do
    # Track broadcast results
    if result[:failed_deliveries] > 0 do
      # Add failed deliveries to tracking
      failed_entries = Map.get(result, :delivery_results, %{})
      |> Enum.filter(fn {_recipient, result} -> match?({:error, _}, result) end)
      |> Enum.map(fn {recipient, {:error, reason}} ->
        %{
          signal_id: result.signal_id,
          recipient: recipient,
          reason: reason,
          failed_at: DateTime.utc_now()
        }
      end)
      
      agent = update_in(agent.state.failed_deliveries, fn failures ->
        failures ++ failed_entries
      end)
      
      {:ok, agent}
    else
      {:ok, agent}
    end
  end
  
  def handle_action_result(agent, ConfirmDeliveryAction, {:ok, result}, _metadata) do
    confirmation = result.confirmation
    
    # Update delivery confirmations
    key = "#{confirmation.signal_id}:#{confirmation.recipient}"
    agent = put_in(agent.state.delivery_confirmations[key], confirmation)
    
    # If it's a failure and retry is needed, add to failed deliveries
    if confirmation.status == :failed && result.retry_needed do
      failed_entry = %{
        signal_id: confirmation.signal_id,
        recipient: confirmation.recipient,
        reason: confirmation.details[:reason] || "Unknown failure",
        failed_at: confirmation.confirmed_at,
        retry_count: result.retry_count
      }
      
      agent = update_in(agent.state.failed_deliveries, fn failures ->
        [failed_entry | failures]
      end)
    end
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, ManageSignalTemplatesAction, {:ok, result}, _metadata) do
    case result.operation do
      :create ->
        agent = put_in(agent.state.signal_templates[result.template_name], result.template_data)
        {:ok, agent}
        
      :update ->
        agent = put_in(agent.state.signal_templates[result.template_name], result.template_data)
        {:ok, agent}
        
      :delete ->
        agent = update_in(agent.state.signal_templates, &Map.delete(&1, result.template_name))
        {:ok, agent}
        
      _ ->
        {:ok, agent}
    end
  end
  
  def handle_action_result(agent, action, result, metadata) do
    # Let parent handle other actions
    super(agent, action, result, metadata)
  end
end
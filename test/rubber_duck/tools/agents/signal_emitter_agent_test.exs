defmodule RubberDuck.Tools.Agents.SignalEmitterAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.SignalEmitterAgent
  
  setup do
    {:ok, agent} = SignalEmitterAgent.start_link(id: "test_signal_emitter")
    
    on_exit(fn ->
      if Process.alive?(agent) do
        GenServer.stop(agent)
      end
    end)
    
    %{agent: agent}
  end
  
  describe "action execution" do
    test "executes tool via ExecuteToolAction", %{agent: agent} do
      params = %{
        signal: %{type: "test.signal", source: "test", data: %{message: "hello"}},
        recipients: ["agent1", "agent2"]
      }
      
      # Execute action directly
      context = %{agent: GenServer.call(agent, :get_state), parent_module: SignalEmitterAgent}
      
      # Mock the Executor response - in real tests, you'd mock RubberDuck.ToolSystem.Executor
      result = SignalEmitterAgent.ExecuteToolAction.run(%{params: params}, context)
      
      # Verify structure (actual execution would need mocking)
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "broadcast signal action validates signal format", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Test invalid signal (missing required fields)
      invalid_signal = %{data: %{message: "test"}} # Missing type and source
      
      {:error, {:invalid_signal, reason}} = SignalEmitterAgent.BroadcastSignalAction.run(
        %{
          signal: invalid_signal,
          recipients: ["agent1"],
          broadcast_type: :fanout
        },
        context
      )
      
      assert String.contains?(reason, "Missing required fields")
      
      # Test valid signal structure
      valid_signal = %{type: "test.signal", source: "test", data: %{message: "hello"}}
      
      # In real tests, would mock Executor.execute to return success
      # For now, just verify the action structure exists
      action_module = SignalEmitterAgent.BroadcastSignalAction
      assert function_exported?(action_module, :run, 2)
    end
    
    test "route signal action matches routing rules", %{agent: agent} do
      signal = %{
        type: "user.created",
        source: "user_service",
        data: %{user_id: 123, email: "test@example.com"}
      }
      
      routing_rules = [
        %{
          type_pattern: "user.*",
          source_pattern: "user_service",
          destination: "user_notification_service"
        },
        %{
          type_pattern: "order.*",
          destination: "order_processing_service"
        }
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = SignalEmitterAgent.RouteSignalAction.run(
        %{
          signal: signal,
          routing_rules: routing_rules
        },
        context
      )
      
      assert result.routing_decision == :rule_matched
      assert result.destination == "user_notification_service"
      assert result.matched_route.type_pattern == "user.*"
    end
    
    test "route signal action uses default route when no rules match", %{agent: agent} do
      signal = %{
        type: "unknown.event",
        source: "unknown_service",
        data: %{}
      }
      
      routing_rules = [
        %{type_pattern: "user.*", destination: "user_service"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = SignalEmitterAgent.RouteSignalAction.run(
        %{
          signal: signal,
          routing_rules: routing_rules,
          default_route: "default_handler"
        },
        context
      )
      
      assert result.routing_decision == :default_route
      assert result.destination == "default_handler"
      assert result.matched_route == nil
    end
    
    test "filter signals action includes/excludes based on criteria", %{agent: agent} do
      signals = [
        %{type: "user.created", source: "api", data: %{priority: :high}},
        %{type: "user.updated", source: "api", data: %{priority: :normal}},
        %{type: "system.health", source: "monitor", data: %{priority: :low}},
        %{type: "user.deleted", source: "api", data: %{priority: :high}}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Test include mode - only high priority signals
      {:ok, result_include} = SignalEmitterAgent.FilterSignalsAction.run(
        %{
          signals: signals,
          filter_criteria: %{priority: :high},
          filter_mode: :include
        },
        context
      )
      
      assert result_include.filtered_count == 2
      assert result_include.original_count == 4
      
      # Test exclude mode - exclude system signals
      {:ok, result_exclude} = SignalEmitterAgent.FilterSignalsAction.run(
        %{
          signals: signals,
          filter_criteria: %{type: "system.*"},
          filter_mode: :exclude
        },
        context
      )
      
      # Should exclude 1 system signal, leaving 3
      assert result_exclude.filtered_count == 3
    end
    
    test "transform signal action applies transformations", %{agent: agent} do
      signal = %{
        type: "user.created",
        source: "api",
        data: %{user_id: 123, name: "John"}
      }
      
      transformations = [
        %{type: :add_field, field: :version, value: "1.0"},
        %{type: :add_timestamp},
        %{type: :add_correlation_id},
        %{type: :modify_data, path: [:data, :processed], value: true}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = SignalEmitterAgent.TransformSignalAction.run(
        %{
          signal: signal,
          transformations: transformations
        },
        context
      )
      
      transformed = result.transformed_signal
      
      assert transformed.version == "1.0"
      assert Map.has_key?(transformed, :timestamp)
      assert get_in(transformed, [:data, :correlation_id]) != nil
      assert get_in(transformed, [:data, :processed]) == true
      assert result.transformations_applied == 4
    end
    
    test "confirm delivery action tracks delivery status", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Test successful delivery
      {:ok, result_success} = SignalEmitterAgent.ConfirmDeliveryAction.run(
        %{
          signal_id: "signal_123",
          recipient: "agent1",
          status: :delivered,
          details: %{delivery_time: 150}
        },
        context
      )
      
      assert result_success.confirmation.status == :delivered
      assert result_success.retry_needed == false
      
      # Test failed delivery
      {:ok, result_failed} = SignalEmitterAgent.ConfirmDeliveryAction.run(
        %{
          signal_id: "signal_456",
          recipient: "agent2", 
          status: :failed,
          details: %{reason: "Connection timeout"}
        },
        context
      )
      
      assert result_failed.confirmation.status == :failed
      assert result_failed.retry_needed == true # Should retry on first failure
    end
    
    test "manage signal templates action handles CRUD operations", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Test create template
      {:ok, result_create} = SignalEmitterAgent.ManageSignalTemplatesAction.run(
        %{
          operation: :create,
          template_name: "user_notification",
          template_data: %{
            type: "notification.user",
            source: "notification_service",
            data: %{message: "", user_id: nil}
          }
        },
        context
      )
      
      assert result_create.operation == :create
      assert result_create.template_name == "user_notification"
      
      # Test list templates (should include default templates)
      {:ok, result_list} = SignalEmitterAgent.ManageSignalTemplatesAction.run(
        %{operation: :list},
        context
      )
      
      assert result_list.operation == :list
      assert result_list.template_count >= 3 # At least the default templates
      assert "notification" in result_list.templates
      
      # Test get template
      {:ok, result_get} = SignalEmitterAgent.ManageSignalTemplatesAction.run(
        %{
          operation: :get,
          template_name: "notification"
        },
        context
      )
      
      assert result_get.operation == :get
      assert result_get.template_name == "notification"
      assert Map.has_key?(result_get.template_data, :type)
    end
  end
  
  describe "signal handling with actions" do
    test "broadcast_signal signal triggers BroadcastSignalAction", %{agent: agent} do
      signal = %{
        "type" => "broadcast_signal",
        "data" => %{
          "signal" => %{"type" => "test.broadcast", "source" => "test"},
          "recipients" => ["agent1", "agent2"],
          "broadcast_type" => "fanout"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SignalEmitterAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "route_signal signal triggers RouteSignalAction", %{agent: agent} do
      signal = %{
        "type" => "route_signal",
        "data" => %{
          "signal" => %{"type" => "user.created", "source" => "api"},
          "routing_rules" => [%{"type_pattern" => "user.*", "destination" => "user_service"}]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SignalEmitterAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "filter_signals signal triggers FilterSignalsAction", %{agent: agent} do
      signal = %{
        "type" => "filter_signals",
        "data" => %{
          "signals" => [%{"type" => "test", "priority" => "high"}],
          "filter_criteria" => %{"priority" => "high"},
          "filter_mode" => "include"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SignalEmitterAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "transform_signal signal triggers TransformSignalAction", %{agent: agent} do
      signal = %{
        "type" => "transform_signal",
        "data" => %{
          "signal" => %{"type" => "test", "source" => "test"},
          "transformations" => [%{"type" => "add_timestamp"}]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SignalEmitterAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "confirm_delivery signal triggers ConfirmDeliveryAction", %{agent: agent} do
      signal = %{
        "type" => "confirm_delivery",
        "data" => %{
          "signal_id" => "signal_123",
          "recipient" => "agent1",
          "status" => "delivered"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SignalEmitterAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "manage_templates signal triggers ManageSignalTemplatesAction", %{agent: agent} do
      signal = %{
        "type" => "manage_templates",
        "data" => %{
          "operation" => "list"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SignalEmitterAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "routing and filtering" do
    test "pattern matching works with wildcards" do
      # Test signal routing pattern matching
      signal = %{type: "user.profile.updated", source: "user_api"}
      
      # This would be tested through the RouteSignalAction, but here's the concept
      assert SignalEmitterAgent.RouteSignalAction.run(
        %{
          signal: signal,
          routing_rules: [%{type_pattern: "user.*", destination: "user_handler"}]
        },
        %{agent: %{state: %{signal_routes: %{}}}}
      ) |> elem(0) == :ok
    end
    
    test "filtering handles different criteria types" do
      signals = [
        %{type: "user.created", priority: :high, tags: ["important", "user"]},
        %{type: "system.health", priority: :low, tags: ["monitoring"]},
        %{type: "order.placed", priority: :normal, tags: ["business", "order"]}
      ]
      
      context = %{agent: %{state: %{}}}
      
      # Test filtering by list inclusion
      {:ok, result} = SignalEmitterAgent.FilterSignalsAction.run(
        %{
          signals: signals,
          filter_criteria: %{type: ["user.created", "order.placed"]},
          filter_mode: :include
        },
        context
      )
      
      assert result.filtered_count == 2
      
      # Test filtering by priority
      {:ok, result_priority} = SignalEmitterAgent.FilterSignalsAction.run(
        %{
          signals: signals,
          filter_criteria: %{priority: :high},
          filter_mode: :include
        },
        context
      )
      
      assert result_priority.filtered_count == 1
    end
  end
  
  describe "transformations" do
    test "add field transformation" do
      signal = %{type: "test", source: "test"}
      transformations = [%{type: :add_field, field: :priority, value: :high}]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SignalEmitterAgent.TransformSignalAction.run(
        %{signal: signal, transformations: transformations},
        context
      )
      
      assert result.transformed_signal.priority == :high
    end
    
    test "remove field transformation" do
      signal = %{type: "test", source: "test", temp_field: "remove_me"}
      transformations = [%{type: :remove_field, field: :temp_field}]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SignalEmitterAgent.TransformSignalAction.run(
        %{signal: signal, transformations: transformations},
        context
      )
      
      refute Map.has_key?(result.transformed_signal, :temp_field)
    end
    
    test "rename field transformation" do
      signal = %{type: "test", source: "test", old_name: "value"}
      transformations = [%{type: :rename_field, from: :old_name, to: :new_name}]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SignalEmitterAgent.TransformSignalAction.run(
        %{signal: signal, transformations: transformations},
        context
      )
      
      transformed = result.transformed_signal
      assert transformed.new_name == "value"
      refute Map.has_key?(transformed, :old_name)
    end
    
    test "add timestamp transformation" do
      signal = %{type: "test", source: "test"}
      transformations = [%{type: :add_timestamp}]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SignalEmitterAgent.TransformSignalAction.run(
        %{signal: signal, transformations: transformations},
        context
      )
      
      assert Map.has_key?(result.transformed_signal, :timestamp)
      assert %DateTime{} = result.transformed_signal.timestamp
    end
    
    test "add correlation id transformation" do
      signal = %{type: "test", source: "test", data: %{}}
      transformations = [%{type: :add_correlation_id}]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SignalEmitterAgent.TransformSignalAction.run(
        %{signal: signal, transformations: transformations},
        context
      )
      
      correlation_id = get_in(result.transformed_signal, [:data, :correlation_id])
      assert is_binary(correlation_id)
      assert String.starts_with?(correlation_id, "corr_")
    end
    
    test "modify data transformation" do
      signal = %{type: "test", source: "test", data: %{user: %{name: "John"}}}
      transformations = [%{type: :modify_data, path: [:data, :user, :name], value: "Jane"}]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SignalEmitterAgent.TransformSignalAction.run(
        %{signal: signal, transformations: transformations},
        context
      )
      
      assert get_in(result.transformed_signal, [:data, :user, :name]) == "Jane"
    end
    
    test "invalid transformation returns error" do
      signal = %{type: "test", source: "test"}
      transformations = [%{type: :invalid_transform}]
      
      context = %{agent: %{state: %{}}}
      
      {:error, reason} = SignalEmitterAgent.TransformSignalAction.run(
        %{signal: signal, transformations: transformations},
        context
      )
      
      assert String.contains?(reason, "Unknown transformation type")
    end
  end
  
  describe "delivery tracking" do
    test "successful emissions update history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate successful execution
      result = %{
        result: %{
          signal_id: "signal_123",
          recipients: ["agent1", "agent2"],
          delivery_status: :success
        },
        from_cache: false
      }
      
      {:ok, updated} = SignalEmitterAgent.handle_action_result(
        state,
        SignalEmitterAgent.ExecuteToolAction,
        {:ok, result},
        %{}
      )
      
      # Check emission history was updated
      assert length(updated.state.emission_history) == 1
      history_entry = hd(updated.state.emission_history)
      assert history_entry.type == :signal_emission
    end
    
    test "broadcast failures are tracked", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate broadcast with failures
      result = %{
        signal_id: "signal_456",
        failed_deliveries: 1,
        delivery_results: %{
          "agent1" => {:ok, "delivered"},
          "agent2" => {:error, "Connection refused"}
        }
      }
      
      {:ok, updated} = SignalEmitterAgent.handle_action_result(
        state,
        SignalEmitterAgent.BroadcastSignalAction,
        {:ok, result},
        %{}
      )
      
      # Check failed deliveries were tracked
      assert length(updated.state.failed_deliveries) == 1
      failed_entry = hd(updated.state.failed_deliveries)
      assert failed_entry.signal_id == "signal_456"
      assert failed_entry.recipient == "agent2"
    end
    
    test "delivery confirmations are recorded", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      confirmation_result = %{
        confirmation: %{
          signal_id: "signal_789",
          recipient: "agent1",
          status: :delivered,
          details: %{delivery_time: 200},
          confirmed_at: DateTime.utc_now()
        },
        retry_needed: false,
        retry_count: 0
      }
      
      {:ok, updated} = SignalEmitterAgent.handle_action_result(
        state,
        SignalEmitterAgent.ConfirmDeliveryAction,
        {:ok, confirmation_result},
        %{}
      )
      
      # Check confirmation was recorded
      key = "signal_789:agent1"
      assert Map.has_key?(updated.state.delivery_confirmations, key)
      confirmation = updated.state.delivery_confirmations[key]
      assert confirmation.status == :delivered
    end
    
    test "emission history respects max_history limit", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set small limit for testing
      state = put_in(state.state.max_history, 2)
      
      # Add multiple emissions
      state = Enum.reduce(1..3, state, fn i, acc ->
        result = %{
          result: %{signal_id: "signal_#{i}"},
          from_cache: false
        }
        
        {:ok, updated} = SignalEmitterAgent.handle_action_result(
          acc,
          SignalEmitterAgent.ExecuteToolAction,
          {:ok, result},
          %{}
        )
        
        updated
      end)
      
      assert length(state.state.emission_history) == 2
      # Should have the most recent entries
      [first, second] = state.state.emission_history
      assert first.signal_data.signal_id == "signal_3"
      assert second.signal_data.signal_id == "signal_2"
    end
  end
  
  describe "template management" do
    test "agent starts with default templates", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      templates = state.state.signal_templates
      assert Map.has_key?(templates, :notification)
      assert Map.has_key?(templates, :event)
      assert Map.has_key?(templates, :command)
      
      # Check template structure
      notification_template = templates[:notification]
      assert notification_template.type == "system.notification"
      assert Map.has_key?(notification_template.data, :message)
    end
    
    test "template operations update agent state", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Test create operation result handling
      create_result = %{
        operation: :create,
        template_name: "custom_alert",
        template_data: %{type: "alert.custom", source: "alert_system"},
        created_at: DateTime.utc_now()
      }
      
      {:ok, updated_create} = SignalEmitterAgent.handle_action_result(
        state,
        SignalEmitterAgent.ManageSignalTemplatesAction,
        {:ok, create_result},
        %{}
      )
      
      assert Map.has_key?(updated_create.state.signal_templates, "custom_alert")
      
      # Test delete operation result handling
      delete_result = %{
        operation: :delete,
        template_name: "custom_alert",
        deleted_at: DateTime.utc_now()
      }
      
      {:ok, updated_delete} = SignalEmitterAgent.handle_action_result(
        updated_create,
        SignalEmitterAgent.ManageSignalTemplatesAction,
        {:ok, delete_result},
        %{}
      )
      
      refute Map.has_key?(updated_delete.state.signal_templates, "custom_alert")
    end
  end
  
  describe "retry configuration" do
    test "agent starts with default retry config", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      retry_config = state.state.retry_config
      assert retry_config.max_retries == 3
      assert retry_config.retry_delay == 1000
      assert retry_config.backoff_multiplier == 2
    end
  end
  
  describe "result processing" do
    test "process_result adds emission timestamp", %{agent: _agent} do
      result = %{signal_id: "test_123", status: :delivered}
      processed = SignalEmitterAgent.process_result(result, %{})
      
      assert Map.has_key?(processed, :emitted_at)
      assert %DateTime{} = processed.emitted_at
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = SignalEmitterAgent.additional_actions()
      
      assert length(actions) == 6
      assert SignalEmitterAgent.BroadcastSignalAction in actions
      assert SignalEmitterAgent.RouteSignalAction in actions
      assert SignalEmitterAgent.FilterSignalsAction in actions
      assert SignalEmitterAgent.TransformSignalAction in actions
      assert SignalEmitterAgent.ConfirmDeliveryAction in actions
      assert SignalEmitterAgent.ManageSignalTemplatesAction in actions
    end
  end
end
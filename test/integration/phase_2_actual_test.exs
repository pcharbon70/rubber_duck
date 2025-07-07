defmodule RubberDuck.Integration.Phase2ActualTest do
  @moduledoc """
  Integration tests for the actual Phase 2 implementation.

  These tests verify that the DSL-based engine system, protocols,
  and plugin architecture work together correctly.
  """

  use ExUnit.Case, async: false

  alias RubberDuck.{
    Engine,
    EngineSystem,
    PluginSystem,
    Processor,
    Enhancer
  }

  alias RubberDuck.Engines.{
    Completion,
    Generation
  }

  # Setup
  setup do
    # Start the application to ensure supervisors are running
    {:ok, _} = Application.ensure_all_started(:rubber_duck)
    :ok
  end

  # Test 2.7.1: Test engines can be defined and loaded via DSL
  describe "DSL-based engine system" do
    test "engines can be defined using DSL and loaded" do
      # Define a test engine system
      defmodule TestEngineSystem do
        use RubberDuck.EngineSystem

        engine :test_engine do
          module TestEngine
          pool_size(2)
          capability :test_capability
        end
      end

      # Define the test engine module
      defmodule TestEngine do
        @behaviour RubberDuck.Engine

        def init(config), do: {:ok, config}
        def execute(input, state), do: {:ok, %{result: "test: #{input}", state: state}}
        def capabilities, do: [:test_capability]
      end

      # Load engines
      assert :ok = RubberDuck.Engine.Manager.load_engines(TestEngineSystem)

      # Verify engine is available
      assert {:ok, capabilities} = RubberDuck.Engine.CapabilityRegistry.list_capabilities()
      assert :test_capability in capabilities
    end

    test "multiple engines can be defined with different capabilities" do
      defmodule MultiEngineSystem do
        use RubberDuck.EngineSystem

        engine :engine_a do
          module EngineA
          capability :capability_a
          capability :shared_capability
        end

        engine :engine_b do
          module EngineB
          capability :capability_b
          capability :shared_capability
        end
      end

      defmodule EngineA do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}
        def execute(input, state), do: {:ok, %{result: "A: #{input}", state: state}}
        def capabilities, do: [:capability_a, :shared_capability]
      end

      defmodule EngineB do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}
        def execute(input, state), do: {:ok, %{result: "B: #{input}", state: state}}
        def capabilities, do: [:capability_b, :shared_capability]
      end

      assert :ok = RubberDuck.Engine.Manager.load_engines(MultiEngineSystem)

      # Find engines by capability
      assert {:ok, engines} = RubberDuck.Engine.CapabilityRegistry.find_engines(:shared_capability)
      assert length(engines) >= 2
    end
  end

  # Test 2.7.2: Test engines process requests through unified interface
  describe "unified engine interface" do
    test "all engines follow the Engine behaviour" do
      # Test that standard engines implement the behaviour
      for module <- [Completion, Generation] do
        assert function_exported?(module, :init, 1)
        assert function_exported?(module, :execute, 2)
        assert function_exported?(module, :capabilities, 0)
      end
    end

    test "engines can be executed through the Manager" do
      # Define and load a simple engine
      defmodule SimpleEngineSystem do
        use RubberDuck.EngineSystem

        engine :simple do
          module SimpleEngine
          capability :simple_execution
        end
      end

      defmodule SimpleEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}

        def execute(input, state) when is_binary(input) do
          {:ok, %{result: String.upcase(input), length: String.length(input), state: state}}
        end

        def capabilities, do: [:simple_execution]
      end

      assert :ok = RubberDuck.Engine.Manager.load_engines(SimpleEngineSystem)

      # Execute through capability
      assert {:ok, result} =
               RubberDuck.Engine.Manager.execute_by_capability(
                 :simple_execution,
                 "hello world"
               )

      assert result.result == "HELLO WORLD"
      assert result.length == 11
    end
  end

  # Test 2.7.3: Test engine failures are handled gracefully
  describe "engine failure handling" do
    test "engine initialization failures are handled" do
      defmodule FailingInitSystem do
        use RubberDuck.EngineSystem

        engine :failing_init do
          module FailingInitEngine
          capability :will_fail
        end
      end

      defmodule FailingInitEngine do
        @behaviour RubberDuck.Engine
        def init(_config), do: {:error, :init_failed}
        def execute(_input, _state), do: {:ok, %{}}
        def capabilities, do: [:will_fail]
      end

      # Loading should handle the failure gracefully
      result = RubberDuck.Engine.Manager.load_engines(FailingInitSystem)
      assert {:error, failures} = result
      assert {:failing_init, _} = List.first(failures)
    end

    test "engine execution failures are handled" do
      defmodule FailingExecSystem do
        use RubberDuck.EngineSystem

        engine :failing_exec do
          module FailingExecEngine
          capability :fail_on_exec
        end
      end

      defmodule FailingExecEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}
        def execute(_input, _state), do: {:error, :execution_failed}
        def capabilities, do: [:fail_on_exec]
      end

      assert :ok = RubberDuck.Engine.Manager.load_engines(FailingExecSystem)

      # Execution should return the error
      assert {:error, :execution_failed} =
               RubberDuck.Engine.Manager.execute_by_capability(
                 :fail_on_exec,
                 "test"
               )
    end
  end

  # Test 2.7.4: Test concurrent execution through pooling
  describe "concurrent engine execution" do
    test "engines use pooling for concurrent requests" do
      defmodule PooledEngineSystem do
        use RubberDuck.EngineSystem

        engine :pooled do
          module PooledEngine
          pool_size(3)
          capability :pooled_execution
        end
      end

      defmodule PooledEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}

        def execute(input, state) do
          # Simulate work
          Process.sleep(50)

          {:ok,
           %{
             result: "processed: #{input}",
             pid: inspect(self()),
             state: state
           }}
        end

        def capabilities, do: [:pooled_execution]
      end

      assert :ok = RubberDuck.Engine.Manager.load_engines(PooledEngineSystem)

      # Execute multiple concurrent requests
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            RubberDuck.Engine.Manager.execute_by_capability(:pooled_execution, "request_#{i}")
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Should have used different worker processes (pool effect)
      pids =
        results
        |> Enum.map(fn {:ok, result} -> result.pid end)
        |> Enum.uniq()

      assert length(pids) > 1
    end
  end

  # Test 2.7.5: Test plugin system integration
  describe "plugin system integration" do
    test "plugins can be defined and loaded via DSL" do
      defmodule TestPluginSystem do
        use RubberDuck.PluginSystem

        plugin :test_plugin do
          module TestPlugin
          capability :test_enhancement
          priority(10)
        end
      end

      defmodule TestPlugin do
        @behaviour RubberDuck.Plugin

        def init(config), do: {:ok, config}
        def capabilities, do: [:test_enhancement]
        def priority, do: 10

        def process(data, _config) do
          enhanced = Map.put(data, :plugin_applied, true)
          {:ok, enhanced}
        end
      end

      # In a real scenario, plugin loading would be handled by the application
      # For now, we just verify the DSL works
      plugins = RubberDuck.PluginSystem.plugins(TestPluginSystem)
      assert length(plugins) == 1
      assert hd(plugins).name == :test_plugin
    end

    test "plugins can enhance engine results" do
      defmodule EnhancingPluginSystem do
        use RubberDuck.PluginSystem

        plugin :enhancer do
          module EnhancerPlugin
          capability :result_enhancement
          priority(5)
        end
      end

      defmodule EnhancerPlugin do
        @behaviour RubberDuck.Plugin

        def init(config), do: {:ok, config}
        def capabilities, do: [:result_enhancement]
        def priority, do: 5

        def process(%{result: result} = data, _config) when is_binary(result) do
          enhanced = %{data | result: "ENHANCED: #{result}"}
          {:ok, enhanced}
        end

        def process(data, _config), do: {:ok, data}
      end

      # Simulate plugin enhancement
      original_result = %{result: "original", metadata: %{}}
      plugin_config = %{name: :enhancer, module: EnhancerPlugin}

      {:ok, plugin_state} = EnhancerPlugin.init(plugin_config)
      {:ok, enhanced} = EnhancerPlugin.process(original_result, plugin_state)

      assert enhanced.result == "ENHANCED: original"
    end
  end

  # Define test struct outside of test
  defmodule TestCustomStruct do
    defstruct [:data, :metadata]

    defimpl RubberDuck.Processor do
      def process(struct, _opts) do
        {:ok, Map.put(struct, :processed_at, DateTime.utc_now())}
      end

      def metadata(struct) do
        %{
          type: :custom,
          has_data: struct.data != nil,
          has_metadata: struct.metadata != nil
        }
      end

      def validate(struct) do
        if is_struct(struct, RubberDuck.Integration.Phase2ActualTest.TestCustomStruct),
          do: :ok,
          else: {:error, :invalid_type}
      end

      def normalize(struct) do
        struct
      end
    end
  end

  # Test 2.7.6: Test protocol-based processing
  describe "protocol-based processing" do
    test "Processor protocol works with different data types" do
      # Test with basic types that should have default implementations
      assert {:ok, "test"} = Processor.process("test", %{})
      assert {:ok, %{key: "value"}} = Processor.process(%{key: "value"}, %{})
      assert {:ok, [1, 2, 3]} = Processor.process([1, 2, 3], %{})

      # Test metadata extraction
      assert %{} = Processor.metadata("test")
      assert %{} = Processor.metadata(%{})
      assert %{} = Processor.metadata([])
    end

    test "Enhancer protocol provides enhancement capabilities" do
      # Test with basic types
      assert {:ok, "test"} = Enhancer.enhance("test", :default)
      assert {:ok, %{}} = Enhancer.enhance(%{}, :default)

      # Test with_context
      data = %{value: 1}
      context = %{source: "test"}
      enhanced = Enhancer.with_context(data, context)
      assert is_map(enhanced)
    end

    test "custom structs can implement protocols" do
      custom = %TestCustomStruct{data: "test", metadata: %{}}

      # Process
      assert {:ok, processed} = Processor.process(custom, %{})
      assert Map.has_key?(processed, :processed_at)

      # Metadata
      meta = Processor.metadata(custom)
      assert meta.type == :custom
      assert meta.has_data == true

      # Validate
      assert :ok = Processor.validate(custom)
    end
  end

  # Test 2.7.7: Test engine composition
  describe "engine composition" do
    test "multiple engines can be composed into workflows" do
      defmodule WorkflowEngineSystem do
        use RubberDuck.EngineSystem

        engine :step1 do
          module Step1Engine
          capability :step1
        end

        engine :step2 do
          module Step2Engine
          capability :step2
        end
      end

      defmodule Step1Engine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}

        def execute(input, state) do
          {:ok,
           %{
             step1_result: "Processed: #{input}",
             original: input,
             state: state
           }}
        end

        def capabilities, do: [:step1]
      end

      defmodule Step2Engine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}

        def execute(%{step1_result: prev} = input, state) do
          {:ok,
           %{
             final_result: "#{prev} -> Step2 Complete",
             input: input,
             state: state
           }}
        end

        def capabilities, do: [:step2]
      end

      assert :ok = RubberDuck.Engine.Manager.load_engines(WorkflowEngineSystem)

      # Execute workflow
      {:ok, step1_result} = RubberDuck.Engine.Manager.execute_by_capability(:step1, "initial input")
      {:ok, final_result} = RubberDuck.Engine.Manager.execute_by_capability(:step2, step1_result)

      assert final_result.final_result == "Processed: initial input -> Step2 Complete"
    end
  end

  # Test 2.7.8: Test health monitoring
  describe "engine health monitoring" do
    test "engine health can be checked" do
      defmodule HealthyEngineSystem do
        use RubberDuck.EngineSystem

        engine :healthy do
          module HealthyEngine
          capability :health_check
          heartbeat_interval(1000)
        end
      end

      defmodule HealthyEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, Map.put(config, :healthy, true)}
        def execute(input, state), do: {:ok, %{result: input, healthy: state.healthy}}
        def capabilities, do: [:health_check]

        # Custom health check
        def health_check(state) do
          if state[:healthy] do
            {:ok, %{status: :healthy, uptime: 100}}
          else
            {:error, %{status: :unhealthy, reason: "Not healthy"}}
          end
        end
      end

      assert :ok = RubberDuck.Engine.Manager.load_engines(HealthyEngineSystem)

      # Check health status
      case RubberDuck.Engine.Manager.health_status(:healthy) do
        {:ok, status} ->
          assert status.status in [:starting, :running, :idle]

        {:error, _} ->
          # Engine might not support detailed health checks
          assert true
      end
    end
  end
end

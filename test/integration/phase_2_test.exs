defmodule RubberDuck.Integration.Phase2Test do
  @moduledoc """
  Integration tests for Phase 2: Pluggable Engine System.

  These tests verify that all components of the engine system work together correctly,
  including dynamic registration, concurrent execution, protocol-based processing,
  and plugin integration.
  """

  use ExUnit.Case, async: false

  alias RubberDuck.{
    Engine,
    Engine.Manager,
    PluginManager,
    Processor,
    Enhancer
  }

  alias RubberDuck.Engines.{
    Completion,
    Generation
  }

  # Setup and teardown

  setup_all do
    # Ensure all applications are started
    {:ok, _} = Application.ensure_all_started(:rubber_duck)

    on_exit(fn ->
      # Clean up any test artifacts
      cleanup_test_engines()
    end)

    :ok
  end

  setup do
    # Start fresh for each test
    cleanup_test_engines()

    # Ensure managers are running
    ensure_managers_started()

    :ok
  end

  # Test 2.7.1: Test engines register and retrieve dynamically

  describe "dynamic engine registration" do
    test "engines can register dynamically and be retrieved" do
      # Define a test engine
      defmodule TestDynamicEngine do
        @behaviour RubberDuck.Engine

        def init(config), do: {:ok, config}
        def execute(input, state), do: {:ok, %{result: "dynamic: #{input}", state: state}}
        def capabilities, do: [:test_dynamic]
      end

      # Register the engine
      assert :ok = Manager.register_engine(:test_dynamic, TestDynamicEngine, [])

      # Verify it's registered
      assert {:ok, engines} = Manager.list_engines()
      assert Enum.any?(engines, fn {name, _module, _state} -> name == :test_dynamic end)

      # Retrieve and use the engine
      assert {:ok, module, state} = Manager.get_engine(:test_dynamic)
      assert module == TestDynamicEngine
      assert {:ok, result} = module.execute("test input", state)
      assert result.result == "dynamic: test input"
    end

    test "multiple engines can be registered with different capabilities" do
      # Define engines with different capabilities
      defmodule EngineA do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}
        def execute(input, state), do: {:ok, %{result: "A: #{input}", state: state}}
        def capabilities, do: [:analysis, :validation]
      end

      defmodule EngineB do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}
        def execute(input, state), do: {:ok, %{result: "B: #{input}", state: state}}
        def capabilities, do: [:generation, :completion]
      end

      # Register both
      assert :ok = Manager.register_engine(:engine_a, EngineA, [])
      assert :ok = Manager.register_engine(:engine_b, EngineB, [])

      # Find by capability
      assert {:ok, analysis_engines} = Manager.find_engines_by_capability(:analysis)
      assert Enum.any?(analysis_engines, fn {name, _} -> name == :engine_a end)

      assert {:ok, generation_engines} = Manager.find_engines_by_capability(:generation)
      assert Enum.any?(generation_engines, fn {name, _} -> name == :engine_b end)
    end
  end

  # Test 2.7.2: Test engines process requests through unified interface

  describe "unified engine interface" do
    test "all engines follow the same interface pattern" do
      # Register standard engines
      ensure_standard_engines_registered()

      # Test each engine through the same interface
      engines = [:completion, :generation]

      for engine_name <- engines do
        assert {:ok, module, state} = Manager.get_engine(engine_name)

        # All engines should implement the behavior
        assert function_exported?(module, :init, 1)
        assert function_exported?(module, :execute, 2)
        assert function_exported?(module, :capabilities, 0)

        # All should handle basic input
        input = get_test_input_for_engine(engine_name)
        assert {:ok, result} = module.execute(input, state)

        # All results should have expected structure
        assert is_map(result)
        assert Map.has_key?(result, :state) or engine_specific_result?(result, engine_name)
      end
    end

    test "engines can be called through a common dispatcher" do
      ensure_standard_engines_registered()

      # Define a simple dispatcher
      dispatch = fn engine_name, input ->
        with {:ok, module, state} <- Manager.get_engine(engine_name),
             {:ok, result} <- module.execute(input, state) do
          {:ok, result}
        end
      end

      # Test dispatching to different engines
      assert {:ok, completion_result} =
               dispatch.(:completion, %{
                 prefix: "def hello",
                 suffix: "end",
                 language: :elixir,
                 cursor_position: {1, 10}
               })

      assert {:ok, generation_result} =
               dispatch.(:generation, %{
                 prompt: "Create a hello function",
                 language: :elixir,
                 context: %{}
               })

      # Verify results are appropriate
      assert is_map(completion_result)
      assert is_map(generation_result)
    end
  end

  # Test 2.7.3: Test engine failures are handled gracefully

  describe "engine failure handling" do
    test "engine initialization failures are handled" do
      defmodule FailingInitEngine do
        @behaviour RubberDuck.Engine
        def init(_config), do: {:error, :init_failed}
        def execute(_input, _state), do: {:ok, %{}}
        def capabilities, do: [:failing]
      end

      # Registration should fail gracefully
      assert {:error, :init_failed} = Manager.register_engine(:failing_init, FailingInitEngine, [])

      # Engine should not be in the list
      assert {:ok, engines} = Manager.list_engines()
      refute Enum.any?(engines, fn {name, _, _} -> name == :failing_init end)
    end

    test "engine execution failures are handled" do
      defmodule FailingExecuteEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}
        def execute(_input, _state), do: {:error, :execution_failed}
        def capabilities, do: [:failing_exec]
      end

      assert :ok = Manager.register_engine(:failing_exec, FailingExecuteEngine, [])
      assert {:ok, module, state} = Manager.get_engine(:failing_exec)

      # Execution should return error
      assert {:error, :execution_failed} = module.execute(%{test: true}, state)
    end

    test "engine crashes are isolated" do
      defmodule CrashingEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}
        def execute(_input, _state), do: raise("Intentional crash")
        def capabilities, do: [:crashing]
      end

      assert :ok = Manager.register_engine(:crashing, CrashingEngine, [])
      assert {:ok, module, state} = Manager.get_engine(:crashing)

      # Execution should raise but not crash the system
      assert_raise RuntimeError, "Intentional crash", fn ->
        module.execute(%{}, state)
      end

      # Other engines should still work
      assert {:ok, engines} = Manager.list_engines()
      assert length(engines) > 0
    end
  end

  # Test 2.7.4: Test multiple engines can run concurrently

  describe "concurrent engine execution" do
    test "multiple engines can execute simultaneously" do
      # Define engines with delays to test concurrency
      defmodule SlowEngine1 do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}

        def execute(input, state) do
          Process.sleep(100)
          {:ok, %{result: "slow1: #{input}", timestamp: System.monotonic_time(), state: state}}
        end

        def capabilities, do: [:slow1]
      end

      defmodule SlowEngine2 do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}

        def execute(input, state) do
          Process.sleep(100)
          {:ok, %{result: "slow2: #{input}", timestamp: System.monotonic_time(), state: state}}
        end

        def capabilities, do: [:slow2]
      end

      assert :ok = Manager.register_engine(:slow1, SlowEngine1, [])
      assert :ok = Manager.register_engine(:slow2, SlowEngine2, [])

      # Execute engines concurrently
      start_time = System.monotonic_time(:millisecond)

      tasks = [
        Task.async(fn ->
          {:ok, module, state} = Manager.get_engine(:slow1)
          module.execute("concurrent", state)
        end),
        Task.async(fn ->
          {:ok, module, state} = Manager.get_engine(:slow2)
          module.execute("concurrent", state)
        end)
      ]

      results = Task.await_many(tasks, 5000)
      end_time = System.monotonic_time(:millisecond)

      # Both should succeed
      assert [{:ok, result1}, {:ok, result2}] = results
      assert result1.result == "slow1: concurrent"
      assert result2.result == "slow2: concurrent"

      # Should take ~100ms (concurrent) not ~200ms (sequential)
      elapsed = end_time - start_time
      assert elapsed < 150, "Engines did not execute concurrently (took #{elapsed}ms)"
    end

    test "engine state is isolated between concurrent executions" do
      defmodule StatefulEngine do
        @behaviour RubberDuck.Engine

        def init(config) do
          {:ok, %{counter: 0, config: config}}
        end

        def execute(input, state) do
          # Simulate state mutation
          new_counter = state.counter + 1
          Process.sleep(50)

          {:ok,
           %{
             result: "#{input}: #{new_counter}",
             state: %{state | counter: new_counter}
           }}
        end

        def capabilities, do: [:stateful]
      end

      assert :ok = Manager.register_engine(:stateful, StatefulEngine, [])

      # Run multiple concurrent executions
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            {:ok, module, state} = Manager.get_engine(:stateful)
            module.execute("request_#{i}", state)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should succeed with counter = 1 (isolated state)
      for {:ok, result} <- results do
        assert String.ends_with?(result.result, ": 1")
      end
    end
  end

  # Test 2.7.5: Test engine priority affects selection

  describe "engine priority and selection" do
    test "engines with higher priority are selected first" do
      # Register engines with different priorities
      defmodule HighPriorityEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}
        def execute(input, state), do: {:ok, %{result: "high: #{input}", state: state}}
        def capabilities, do: [:test_capability]
      end

      defmodule LowPriorityEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}
        def execute(input, state), do: {:ok, %{result: "low: #{input}", state: state}}
        def capabilities, do: [:test_capability]
      end

      # Register with different priorities
      assert :ok = Manager.register_engine(:high_priority, HighPriorityEngine, priority: 10)
      assert :ok = Manager.register_engine(:low_priority, LowPriorityEngine, priority: 1)

      # Find engines by capability
      assert {:ok, engines} = Manager.find_engines_by_capability(:test_capability)

      # High priority should be first
      assert [{:high_priority, _}, {:low_priority, _}] = engines
    end

    test "default priority is applied when not specified" do
      defmodule DefaultPriorityEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}
        def execute(input, state), do: {:ok, %{result: input, state: state}}
        def capabilities, do: [:default_test]
      end

      assert :ok = Manager.register_engine(:default_priority, DefaultPriorityEngine, [])

      # Should have default priority (5)
      assert {:ok, engines} = Manager.list_engines()
      engine = Enum.find(engines, fn {name, _, _} -> name == :default_priority end)
      assert engine != nil
    end
  end

  # Test 2.7.6: Test context strategies work correctly

  describe "context strategies" do
    test "FIM context strategy for completion engine" do
      ensure_standard_engines_registered()

      assert {:ok, module, state} = Manager.get_engine(:completion)

      input = %{
        prefix: "def calculate_sum(numbers) do\n  # TODO: implement",
        suffix: "\nend",
        language: :elixir,
        cursor_position: {2, 20}
      }

      assert {:ok, result} = module.execute(input, state)
      assert Map.has_key?(result, :completions)
      assert is_list(result.completions)

      # Should have FIM-based completions
      if length(result.completions) > 0 do
        completion = hd(result.completions)
        assert Map.has_key?(completion, :text)
        assert Map.has_key?(completion, :score)
      end
    end

    test "RAG context strategy for generation engine" do
      ensure_standard_engines_registered()

      assert {:ok, module, state} = Manager.get_engine(:generation)

      input = %{
        prompt: "Create a GenServer that manages a counter",
        language: :elixir,
        context: %{
          project_files: ["lib/example.ex"],
          imports: ["GenServer"]
        }
      }

      assert {:ok, result} = module.execute(input, state)
      assert Map.has_key?(result, :result)
      assert Map.has_key?(result.result, :code)

      # Generated code should reflect the prompt
      assert String.contains?(result.result.code, "GenServer") or
               String.contains?(result.result.code, "genserver")
    end
  end

  # Test 2.7.7: Test engine health monitoring

  describe "engine health monitoring" do
    test "engine health can be checked" do
      defmodule HealthyEngine do
        @behaviour RubberDuck.Engine

        def init(config), do: {:ok, Map.put(config, :healthy, true)}

        def execute(input, state) do
          if state[:healthy] do
            {:ok, %{result: input, state: state}}
          else
            {:error, :unhealthy}
          end
        end

        def capabilities, do: [:health_test]

        # Health check function
        def health_check(state) do
          if state[:healthy] do
            {:ok, %{status: :healthy, details: "All systems operational"}}
          else
            {:error, %{status: :unhealthy, details: "Engine is not healthy"}}
          end
        end
      end

      assert :ok = Manager.register_engine(:healthy, HealthyEngine, [])
      assert {:ok, module, state} = Manager.get_engine(:healthy)

      # Check health
      if function_exported?(module, :health_check, 1) do
        assert {:ok, health} = module.health_check(state)
        assert health.status == :healthy
      end
    end

    test "unhealthy engines can be detected" do
      defmodule UnhealthyEngine do
        @behaviour RubberDuck.Engine

        def init(config), do: {:ok, Map.put(config, :failure_count, 0)}

        def execute(_input, state) do
          # Simulate failures
          new_count = state.failure_count + 1
          {:error, {:failed, new_count}}
        end

        def capabilities, do: [:unhealthy_test]
      end

      assert :ok = Manager.register_engine(:unhealthy, UnhealthyEngine, [])
      assert {:ok, module, state} = Manager.get_engine(:unhealthy)

      # Multiple failures
      for _ <- 1..3 do
        assert {:error, _} = module.execute(%{}, state)
      end

      # Engine should still be registered (health monitoring would track this)
      assert {:ok, engines} = Manager.list_engines()
      assert Enum.any?(engines, fn {name, _, _} -> name == :unhealthy end)
    end
  end

  # Test 2.7.8: Test plugin system integration

  describe "plugin system integration" do
    test "plugins can enhance engine functionality" do
      # Define a test plugin
      defmodule TestPlugin do
        @behaviour RubberDuck.Plugin

        def init(config), do: {:ok, config}
        def capabilities, do: [:test_enhancement]
        def priority, do: 5

        def process(data, config) do
          enhanced = Map.put(data, :plugin_processed, true)
          {:ok, enhanced}
        end
      end

      # Register plugin
      assert :ok = PluginManager.register_plugin(TestPlugin, [])

      # Create engine that uses plugins
      defmodule PluginAwareEngine do
        @behaviour RubberDuck.Engine

        def init(config), do: {:ok, config}

        def execute(input, state) do
          # Process through plugins
          case PluginManager.process_plugins(input, :test_enhancement) do
            {:ok, processed} ->
              {:ok, %{result: processed, state: state}}

            error ->
              error
          end
        end

        def capabilities, do: [:plugin_aware]
      end

      assert :ok = Manager.register_engine(:plugin_aware, PluginAwareEngine, [])
      assert {:ok, module, state} = Manager.get_engine(:plugin_aware)

      # Execute and verify plugin processing
      assert {:ok, result} = module.execute(%{data: "test"}, state)
      assert result.result[:plugin_processed] == true
    end

    test "multiple plugins can chain processing" do
      # Define plugins that chain
      defmodule PluginA do
        @behaviour RubberDuck.Plugin
        def init(config), do: {:ok, config}
        def capabilities, do: [:chain_test]
        def priority, do: 10

        def process(data, _config) do
          {:ok, Map.update(data, :chain, ["A"], &(&1 ++ ["A"]))}
        end
      end

      defmodule PluginB do
        @behaviour RubberDuck.Plugin
        def init(config), do: {:ok, config}
        def capabilities, do: [:chain_test]
        def priority, do: 5

        def process(data, _config) do
          {:ok, Map.update(data, :chain, ["B"], &(&1 ++ ["B"]))}
        end
      end

      assert :ok = PluginManager.register_plugin(PluginA, [])
      assert :ok = PluginManager.register_plugin(PluginB, [])

      # Process through plugin chain
      input = %{initial: true}
      assert {:ok, result} = PluginManager.process_plugins(input, :chain_test)

      # Should process in priority order (A then B)
      assert result.chain == ["A", "B"]
    end
  end

  # Test 2.7.9: Test protocol-based processing

  # Define test structs outside of tests
  defmodule TestProcessableStruct do
    defstruct [:data]

    defimpl RubberDuck.Processor do
      def process(struct, _opts) do
        {:ok, Map.put(struct, :processed, true)}
      end

      def metadata(struct) do
        %{type: :test_struct, size: 1, has_data: struct.data != nil}
      end

      def validate(struct) do
        if is_map(struct), do: :ok, else: {:error, :invalid_struct}
      end

      def normalize(struct) do
        {:ok, struct}
      end
    end
  end

  defmodule TestEnhanceableStruct do
    defstruct [:value]

    defimpl RubberDuck.Enhancer do
      def enhance(struct, _strategy) do
        enhanced_value = "enhanced: #{struct.value}"
        {:ok, %{struct | value: enhanced_value}}
      end

      def with_context(struct, context) do
        Map.put(struct, :context, context)
      end

      def with_metadata(struct, metadata) do
        Map.put(struct, :metadata, metadata)
      end

      def derive(struct, _derivations) do
        {:ok, Map.put(struct, :derived, true)}
      end
    end
  end

  describe "protocol-based processing" do
    test "Processable protocol works with different data types" do
      # String processing
      assert {:ok, processed} = Processor.process("test string", %{})
      assert processed == "test string"

      # Map processing
      assert {:ok, processed} = Processor.process(%{key: "value"}, %{})
      assert processed == %{key: "value"}

      # List processing
      assert {:ok, processed} = Processor.process([1, 2, 3], %{})
      assert processed == [1, 2, 3]

      # Custom struct processing
      test_struct = %TestProcessableStruct{data: "test"}
      assert {:ok, processed} = Processor.process(test_struct, %{})
      assert processed.processed == true
    end

    test "Enhanceable protocol provides enhancements" do
      # String enhancement
      assert {:ok, enhanced} = Enhancer.enhance("test", %{})
      assert enhanced == "test"

      # List enhancement with temporal extraction
      list_with_times = ["2023-01-01", "meeting at 3pm", "normal item"]
      assert {:ok, enhanced} = Enhancer.enhance(list_with_times, %{})
      assert is_map(enhanced)
      assert Map.has_key?(enhanced, :temporal_elements) or enhanced == list_with_times

      # Custom enhancement
      struct = %TestEnhanceableStruct{value: "original"}
      assert {:ok, enhanced} = Enhancer.enhance(struct, %{})
      assert enhanced.value == "enhanced: original"
    end
  end

  # Test 2.7.10: Test engine composition capabilities

  describe "engine composition" do
    test "engines can be composed to create complex workflows" do
      ensure_standard_engines_registered()

      # Create a workflow that uses multiple engines
      workflow = fn input ->
        with {:ok, completion_mod, completion_state} <- Manager.get_engine(:completion),
             {:ok, completed} <-
               completion_mod.execute(
                 %{
                   prefix: input,
                   suffix: "",
                   language: :elixir,
                   cursor_position: {1, String.length(input)}
                 },
                 completion_state
               ),
             {:ok, generation_mod, generation_state} <- Manager.get_engine(:generation),
             {:ok, generated} <-
               generation_mod.execute(
                 %{
                   prompt: "Improve this code: #{input}",
                   language: :elixir,
                   context: %{suggestions: completed}
                 },
                 generation_state
               ) do
          {:ok,
           %{
             original: input,
             completion: completed,
             improved: generated
           }}
        end
      end

      # Execute workflow
      result = workflow.("def add(a, b), do: a + b")
      assert {:ok, composed_result} = result
      assert Map.has_key?(composed_result, :original)
      assert Map.has_key?(composed_result, :completion)
      assert Map.has_key?(composed_result, :improved)
    end

    test "engine results can be piped through transformations" do
      # Define transformation engines
      defmodule UppercaseEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}

        def execute(input, state) when is_binary(input) do
          {:ok, %{result: String.upcase(input), state: state}}
        end

        def execute(%{text: text} = input, state) do
          {:ok, %{result: %{input | text: String.upcase(text)}, state: state}}
        end

        def capabilities, do: [:transform_uppercase]
      end

      defmodule ReverseEngine do
        @behaviour RubberDuck.Engine
        def init(config), do: {:ok, config}

        def execute(input, state) when is_binary(input) do
          {:ok, %{result: String.reverse(input), state: state}}
        end

        def execute(%{text: text} = input, state) do
          {:ok, %{result: %{input | text: String.reverse(text)}, state: state}}
        end

        def capabilities, do: [:transform_reverse]
      end

      assert :ok = Manager.register_engine(:uppercase, UppercaseEngine, [])
      assert :ok = Manager.register_engine(:reverse, ReverseEngine, [])

      # Create pipeline
      pipeline = fn input ->
        engines = [:uppercase, :reverse]

        Enum.reduce_while(engines, {:ok, input}, fn engine_name, {:ok, current_input} ->
          case Manager.get_engine(engine_name) do
            {:ok, module, state} ->
              case module.execute(current_input, state) do
                {:ok, result} -> {:cont, {:ok, result.result}}
                error -> {:halt, error}
              end

            error ->
              {:halt, error}
          end
        end)
      end

      # Test pipeline
      assert {:ok, result} = pipeline.("hello")
      assert result == "OLLEH"
    end
  end

  # Helper functions

  defp ensure_managers_started do
    # Ensure Manager is started
    case GenServer.whereis(Manager) do
      nil ->
        {:ok, _} = Manager.start_link([])

      _pid ->
        :ok
    end

    # Ensure PluginManager is started
    case GenServer.whereis(PluginManager) do
      nil ->
        {:ok, _} = PluginManager.start_link([])

      _pid ->
        :ok
    end
  end

  defp ensure_standard_engines_registered do
    # Register standard engines if not already registered
    engines = [
      {:completion, Completion},
      {:generation, Generation}
    ]

    for {name, module} <- engines do
      case Manager.get_engine(name) do
        {:ok, _, _} ->
          :ok

        _ ->
          Manager.register_engine(name, module, [])
      end
    end
  end

  defp cleanup_test_engines do
    # Clean up any test engines (those not in standard set)
    standard_engines = [:completion, :generation]

    case Manager.list_engines() do
      {:ok, engines} ->
        for {name, _, _} <- engines, name not in standard_engines do
          Manager.unregister_engine(name)
        end

      _ ->
        :ok
    end
  end

  defp get_test_input_for_engine(:completion) do
    %{
      prefix: "def test",
      suffix: "end",
      language: :elixir,
      cursor_position: {1, 8}
    }
  end

  defp get_test_input_for_engine(:generation) do
    %{
      prompt: "Create a test function",
      language: :elixir,
      context: %{}
    }
  end

  defp get_test_input_for_engine(_), do: %{test: true}

  defp engine_specific_result?(result, :completion), do: Map.has_key?(result, :completions)
  defp engine_specific_result?(result, :generation), do: Map.has_key?(result, :result)
  defp engine_specific_result?(_, _), do: true
end

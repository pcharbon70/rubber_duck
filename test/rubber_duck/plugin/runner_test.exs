defmodule RubberDuck.Plugin.RunnerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Plugin.Runner
  alias RubberDuck.ExamplePlugins.{TextEnhancer, WordCounter}
  
  describe "plugin runner lifecycle" do
    test "starts plugin runner successfully" do
      {:ok, runner} = Runner.start_link(module: TextEnhancer, config: [])
      assert Process.alive?(runner)
      GenServer.stop(runner)
    end
    
    test "initializes plugin with config" do
      config = [prefix: ">>", suffix: "<<"]
      {:ok, runner} = Runner.start_link(module: TextEnhancer, config: config)
      
      {:ok, state} = Runner.get_state(runner)
      assert state.prefix == ">>"
      assert state.suffix == "<<"
      
      GenServer.stop(runner)
    end
    
    test "fails to start with invalid plugin" do
      assert {:error, {:plugin_init_failed, _}} = 
        Runner.start_link(module: NonExistentModule, config: [])
    end
  end
  
  describe "plugin execution" do
    setup do
      {:ok, runner} = Runner.start_link(
        module: TextEnhancer, 
        config: [prefix: "[[", suffix: "]]"]
      )
      on_exit(fn -> GenServer.stop(runner) end)
      {:ok, runner: runner}
    end
    
    test "executes plugin successfully", %{runner: runner} do
      assert {:ok, "[[hello]]"} = Runner.execute(runner, "hello")
    end
    
    test "handles plugin errors gracefully", %{runner: runner} do
      assert {:error, :invalid_input_type} = Runner.execute(runner, 123)
    end
    
    test "maintains state across executions" do
      {:ok, runner} = Runner.start_link(module: WordCounter, config: [])
      
      assert {:ok, %{word_count: 2, total_processed: 2}} = 
        Runner.execute(runner, "hello world")
        
      assert {:ok, %{word_count: 3, total_processed: 5}} = 
        Runner.execute(runner, "one two three")
        
      GenServer.stop(runner)
    end
  end
  
  describe "plugin isolation" do
    test "plugin crash doesn't affect runner" do
      defmodule CrashingPlugin do
        @behaviour RubberDuck.Plugin
        
        def name, do: :crasher
        def version, do: "1.0.0"
        def description, do: "Crashes on purpose"
        def supported_types, do: [:any]
        def dependencies, do: []
        def init(_), do: {:ok, %{}}
        
        def execute(:crash, _state) do
          raise "Intentional crash"
        end
        
        def execute(input, state) do
          {:ok, input, state}
        end
        
        def terminate(_, _), do: :ok
      end
      
      {:ok, runner} = Runner.start_link(module: CrashingPlugin, config: [])
      
      # Plugin crashes but runner survives
      assert {:error, {:plugin_crashed, _}} = Runner.execute(runner, :crash)
      assert Process.alive?(runner)
      
      # Can still execute normally
      assert {:ok, "normal"} = Runner.execute(runner, "normal")
      
      GenServer.stop(runner)
    end
  end
  
  describe "configuration updates" do
    test "updates configuration at runtime" do
      defmodule ConfigurablePlugin do
        @behaviour RubberDuck.Plugin
        
        def name, do: :configurable
        def version, do: "1.0.0"
        def description, do: "Supports config updates"
        def supported_types, do: [:any]
        def dependencies, do: []
        
        def init(config) do
          {:ok, %{multiplier: Keyword.get(config, :multiplier, 1)}}
        end
        
        def execute(num, state) when is_number(num) do
          {:ok, num * state.multiplier, state}
        end
        
        def terminate(_, _), do: :ok
        
        def handle_config_change(new_config, _state) do
          {:ok, %{multiplier: Keyword.get(new_config, :multiplier, 1)}}
        end
      end
      
      {:ok, runner} = Runner.start_link(module: ConfigurablePlugin, config: [multiplier: 2])
      
      assert {:ok, 20} = Runner.execute(runner, 10)
      
      # Update config
      assert :ok = Runner.update_config(runner, [multiplier: 3])
      
      assert {:ok, 30} = Runner.execute(runner, 10)
      
      GenServer.stop(runner)
    end
  end
end
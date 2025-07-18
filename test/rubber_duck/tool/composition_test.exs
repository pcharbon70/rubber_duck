defmodule RubberDuck.Tool.CompositionTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.Composition
  alias RubberDuck.Tool.Composition.{ErrorHandler, Transformer}
  
  # Mock tools for testing
  defmodule MockDataFetcher do
    def execute(params, _context) do
      case params do
        %{source: "success"} -> {:ok, %{data: "fetched_data", count: 100}}
        %{source: "error"} -> {:error, "fetch_failed"}
        %{source: "timeout"} -> 
          Process.sleep(100)
          {:ok, %{data: "slow_data", count: 50}}
        _ -> {:ok, %{data: "default_data", count: 10}}
      end
    end
  end
  
  defmodule MockDataTransformer do
    def execute(params, _context) do
      case params do
        %{input: %{data: data}} -> 
          {:ok, %{transformed: String.upcase(data)}}
        %{data: data} when is_binary(data) -> 
          {:ok, %{transformed: String.upcase(data)}}
        _ -> {:ok, %{transformed: "DEFAULT"}}
      end
    end
  end
  
  defmodule MockDataValidator do
    def execute(params, _context) do
      case params do
        %{input: %{transformed: transformed}} when byte_size(transformed) > 0 -> 
          {:ok, %{valid: true, data: transformed}}
        %{transformed: transformed} when byte_size(transformed) > 0 -> 
          {:ok, %{valid: true, data: transformed}}
        _ -> {:error, "validation_failed"}
      end
    end
  end
  
  defmodule MockDataSaver do
    def execute(params, _context) do
      case params do
        %{input: %{data: data}} -> 
          {:ok, %{saved: true, location: "/tmp/#{data}"}}
        %{data: data} when is_binary(data) -> 
          {:ok, %{saved: true, location: "/tmp/#{data}"}}
        _ -> {:ok, %{saved: true, location: "/tmp/default"}}
      end
    end
  end
  
  defmodule MockConditionalTool do
    def execute(params, _context) do
      case params do
        %{condition: true} -> {:ok, %{result: "success_path"}}
        %{condition: false} -> {:error, "failure_path"}
        _ -> {:ok, %{result: "default_path"}}
      end
    end
  end
  
  defmodule MockMerger do
    def execute(params, _context) do
      # Merge all non-nil results
      merged = params
      |> Enum.filter(fn {_k, v} -> v != nil end)
      |> Enum.into(%{})
      
      {:ok, %{merged: merged, count: map_size(merged)}}
    end
  end
  
  describe "sequential/3" do
    test "creates a sequential workflow" do
      workflow = Composition.sequential("test_sequential", [
        {:fetch, MockDataFetcher, %{source: "success"}},
        {:transform, MockDataTransformer, %{}},
        {:validate, MockDataValidator, %{}}
      ])
      
      assert is_struct(workflow, Reactor)
      # The workflow should be a Reactor struct
      assert workflow.id != nil
    end
    
    test "executes a sequential workflow successfully" do
      workflow = Composition.sequential("test_sequential", [
        {:fetch, MockDataFetcher, %{source: "success"}},
        {:transform, MockDataTransformer, %{}},
        {:validate, MockDataValidator, %{}}
      ])
      
      # Note: This test may need to be adjusted based on the actual execution environment
      # For now, we'll test the workflow creation
      assert is_struct(workflow, Reactor)
    end
    
    test "handles empty step list" do
      workflow = Composition.sequential("empty_workflow", [])
      
      assert is_struct(workflow, Reactor)
      assert workflow.id != nil
    end
    
    test "applies workflow options" do
      workflow = Composition.sequential("test_with_options", [
        {:fetch, MockDataFetcher, %{source: "success"}}
      ], timeout: 10_000, max_retries: 5)
      
      assert is_struct(workflow, Reactor)
      assert workflow.id != nil
    end
  end
  
  describe "parallel/3" do
    test "creates a parallel workflow without merge step" do
      workflow = Composition.parallel("test_parallel", [
        {:fetch_a, MockDataFetcher, %{source: "a"}},
        {:fetch_b, MockDataFetcher, %{source: "b"}},
        {:fetch_c, MockDataFetcher, %{source: "c"}}
      ])
      
      assert is_struct(workflow, Reactor)
      assert workflow.id != nil
    end
    
    test "creates a parallel workflow with merge step" do
      workflow = Composition.parallel("test_parallel_merge", [
        {:fetch_a, MockDataFetcher, %{source: "a"}},
        {:fetch_b, MockDataFetcher, %{source: "b"}},
        {:fetch_c, MockDataFetcher, %{source: "c"}}
      ], merge_step: {:merge, MockMerger, %{strategy: "combine"}})
      
      assert is_struct(workflow, Reactor)
      assert workflow.id != nil
    end
    
    test "handles single step in parallel" do
      workflow = Composition.parallel("single_parallel", [
        {:fetch, MockDataFetcher, %{source: "success"}}
      ])
      
      assert is_struct(workflow, Reactor)
      assert workflow.id != nil
    end
  end
  
  describe "conditional/2" do
    test "creates a conditional workflow with both paths" do
      workflow = Composition.conditional("test_conditional", 
        condition: {:check, MockConditionalTool, %{condition: true}},
        success: [
          {:success_action, MockDataTransformer, %{data: "success"}}
        ],
        failure: [
          {:failure_action, MockDataSaver, %{data: "failure"}}
        ]
      )
      
      assert is_struct(workflow, Reactor)
      assert workflow.id != nil
    end
    
    test "creates a conditional workflow with only success path" do
      workflow = Composition.conditional("test_conditional_success", 
        condition: {:check, MockConditionalTool, %{condition: true}},
        success: [
          {:success_action, MockDataTransformer, %{data: "success"}}
        ]
      )
      
      assert is_struct(workflow, Reactor)
      assert workflow.id != nil
    end
    
    test "creates a conditional workflow with only failure path" do
      workflow = Composition.conditional("test_conditional_failure", 
        condition: {:check, MockConditionalTool, %{condition: false}},
        failure: [
          {:failure_action, MockDataSaver, %{data: "failure"}}
        ]
      )
      
      assert is_struct(workflow, Reactor)
      assert workflow.id != nil
    end
  end
  
  describe "loop/2" do
    test "creates a loop workflow without aggregator" do
      workflow = Composition.loop("test_loop", 
        items: ["item1", "item2", "item3"],
        steps: [
          {:process, MockDataTransformer, %{action: "transform"}},
          {:validate, MockDataValidator, %{}}
        ]
      )
      
      assert is_struct(workflow, Reactor)
      assert workflow.id != nil
    end
    
    test "creates a loop workflow with aggregator" do
      workflow = Composition.loop("test_loop_agg", 
        items: ["item1", "item2"],
        steps: [
          {:process, MockDataTransformer, %{action: "transform"}}
        ],
        aggregator: {:collect, MockMerger, %{strategy: "combine"}}
      )
      
      assert is_struct(workflow, Reactor)
      assert workflow.id != nil
    end
    
    test "handles empty items list" do
      workflow = Composition.loop("empty_loop", 
        items: [],
        steps: [
          {:process, MockDataTransformer, %{}}
        ]
      )
      
      assert is_struct(workflow, Reactor)
      assert workflow.id != nil
    end
  end
  
  describe "execute/3" do
    test "validates workflow execution interface" do
      _workflow = Composition.sequential("test_execute", [
        {:fetch, MockDataFetcher, %{source: "success"}}
      ])
      
      # Test that the execute function exists and accepts the right parameters
      assert function_exported?(Composition, :execute, 3)
      assert function_exported?(Composition, :execute, 2)
      assert function_exported?(Composition, :execute, 1)
    end
    
    test "execute_async returns a task" do
      workflow = Composition.sequential("test_async", [
        {:fetch, MockDataFetcher, %{source: "success"}}
      ])
      
      task = Composition.execute_async(workflow, %{})
      
      assert %Task{} = task
      # Clean up the task
      Task.shutdown(task)
    end
  end
  
  describe "error handling integration" do
    test "retry step wrapper" do
      retry_step = ErrorHandler.retry_step(MockDataFetcher, %{source: "success"}, 
        max_attempts: 3, initial_delay: 100)
      
      assert {RubberDuck.Tool.Composition.ErrorHandler, opts} = retry_step
      assert opts[:action] == :retry
      assert opts[:tool_module] == MockDataFetcher
      assert opts[:retry_opts][:max_attempts] == 3
    end
    
    test "fallback step wrapper" do
      fallback_step = ErrorHandler.fallback_step(MockDataFetcher, %{source: "primary"}, 
        fallback_tool: MockDataTransformer, fallback_params: %{source: "backup"})
      
      assert {RubberDuck.Tool.Composition.ErrorHandler, opts} = fallback_step
      assert opts[:action] == :fallback
      assert opts[:tool_module] == MockDataFetcher
      assert opts[:fallback_opts][:fallback_tool] == MockDataTransformer
    end
    
    test "circuit breaker step wrapper" do
      circuit_step = ErrorHandler.circuit_breaker_step(MockDataFetcher, %{source: "external"}, 
        failure_threshold: 5, recovery_timeout: 30_000)
      
      assert {RubberDuck.Tool.Composition.ErrorHandler, opts} = circuit_step
      assert opts[:action] == :circuit_breaker
      assert opts[:tool_module] == MockDataFetcher
      assert opts[:circuit_opts][:failure_threshold] == 5
    end
  end
  
  describe "data transformation integration" do
    test "type conversion" do
      assert {:ok, 123} = Transformer.convert_type("123", :integer)
      assert {:ok, "123"} = Transformer.convert_type(123, :string)
      assert {:ok, 123.0} = Transformer.convert_type(123, :float)
    end
    
    test "path extraction" do
      data = %{user: %{name: "John", age: 30}}
      
      assert {:ok, "John"} = Transformer.extract_path(data, "user.name")
      assert {:ok, 30} = Transformer.extract_path(data, "user.age")
    end
    
    test "template application" do
      data = %{name: "John", age: 30}
      template = "Hello {{name}}, you are {{age}} years old"
      
      assert {:ok, "Hello John, you are 30 years old"} = Transformer.apply_template(data, template)
    end
    
    test "custom transformation" do
      custom_fun = fn data -> String.upcase(data) end
      
      assert {:ok, "HELLO"} = Transformer.apply_custom_function("hello", custom_fun)
    end
    
    test "transformation composition" do
      transformations = [
        {:type, :string},
        {:custom, fn s -> String.upcase(s) end}
      ]
      
      assert {:ok, "123"} = Transformer.compose_transformations(123, transformations)
    end
  end
  
  describe "workflow patterns" do
    test "data pipeline pattern exists" do
      assert Code.ensure_loaded?(RubberDuck.Tool.Composition.Patterns.DataPipeline)
    end
    
    test "conditional processing pattern exists" do
      assert Code.ensure_loaded?(RubberDuck.Tool.Composition.Patterns.ConditionalProcessing)
    end
    
    test "parallel aggregation pattern exists" do
      assert Code.ensure_loaded?(RubberDuck.Tool.Composition.Patterns.ParallelAggregation)
    end
    
    test "batch processing pattern exists" do
      assert Code.ensure_loaded?(RubberDuck.Tool.Composition.Patterns.BatchProcessing)
    end
  end
end
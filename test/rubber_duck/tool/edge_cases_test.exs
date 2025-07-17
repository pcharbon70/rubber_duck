defmodule RubberDuck.Tool.EdgeCasesTest do
  @moduledoc """
  Edge cases and error condition tests for the tool execution system.
  
  Tests unusual scenarios, boundary conditions, and error recovery.
  """
  
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.{Executor, Validator, Authorizer, Sandbox}
  
  @test_user %{
    id: "edge-test-user",
    roles: [:user],
    permissions: [:read, :execute]
  }
  
  # Edge case test tools
  defmodule EdgeCaseTool do
    use RubberDuck.Tool
    
    tool do
      name :edge_case_tool
      description "Tool for testing edge cases"
      category :testing
      
      parameter :edge_case do
        type :string
        required true
        constraints [enum: ["empty_result", "nil_result", "large_result", "unicode", "binary", "nested_error"]]
      end
      
      parameter :data do
        type :any
        required false
      end
      
      execution do
        handler &EdgeCaseTool.execute/2
        timeout 5_000
      end
      
      security do
        sandbox :balanced
        capabilities [:execute]
      end
    end
    
    def execute(params, _context) do
      case params.edge_case do
        "empty_result" ->
          {:ok, ""}
        
        "nil_result" ->
          {:ok, nil}
        
        "large_result" ->
          # Create a large result string
          large_string = String.duplicate("x", 10_000)
          {:ok, large_string}
        
        "unicode" ->
          {:ok, "Hello 🌍 こんにちは Здравствуй العالم"}
        
        "binary" ->
          # Return binary data
          {:ok, <<1, 2, 3, 4, 5>>}
        
        "nested_error" ->
          try do
            raise "Inner error"
          rescue
            error -> raise "Nested error: #{error.message}"
          end
      end
    end
  end
  
  defmodule MalformedTool do
    use RubberDuck.Tool
    
    tool do
      name :malformed_tool
      description "Tool with malformed responses"
      category :testing
      
      parameter :malformed_type do
        type :string
        required true
        constraints [enum: ["wrong_tuple", "atom_result", "invalid_format", "missing_key"]]
      end
      
      execution do
        handler &MalformedTool.execute/2
        timeout 5_000
      end
      
      security do
        sandbox :balanced
        capabilities [:execute]
      end
    end
    
    def execute(params, _context) do
      case params.malformed_type do
        "wrong_tuple" ->
          # Return wrong tuple format
          {:result, "This is not a valid return format"}
        
        "atom_result" ->
          # Return just an atom
          :invalid_return
        
        "invalid_format" ->
          # Return improper format
          "This should be a tuple"
        
        "missing_key" ->
          # Return map without required keys
          %{wrong_key: "value"}
      end
    end
  end
  
  defmodule BoundaryTool do
    use RubberDuck.Tool
    
    tool do
      name :boundary_tool
      description "Tool for testing boundary conditions"
      category :testing
      
      parameter :boundary_type do
        type :string
        required true
        constraints [enum: ["max_string", "max_integer", "max_list", "empty_values", "special_chars"]]
      end
      
      parameter :value do
        type :any
        required false
      end
      
      execution do
        handler &BoundaryTool.execute/2
        timeout 10_000
      end
      
      security do
        sandbox :balanced
        capabilities [:execute]
      end
    end
    
    def execute(params, _context) do
      case params.boundary_type do
        "max_string" ->
          # Test with maximum string length
          max_string = String.duplicate("a", 1_000_000)
          {:ok, "String length: #{String.length(max_string)}"}
        
        "max_integer" ->
          # Test with very large integer
          large_int = 9_999_999_999_999_999_999
          {:ok, "Large integer: #{large_int}"}
        
        "max_list" ->
          # Test with large list
          large_list = Enum.to_list(1..100_000)
          {:ok, "List length: #{length(large_list)}"}
        
        "empty_values" ->
          # Test with empty values
          {:ok, %{empty_string: "", empty_list: [], empty_map: %{}}}
        
        "special_chars" ->
          # Test with special characters
          special = "!@#$%^&*()_+-=[]{}|;':\",./<>?`~"
          {:ok, "Special chars: #{special}"}
      end
    end
  end
  
  defmodule ConcurrencyTool do
    use RubberDuck.Tool
    
    tool do
      name :concurrency_tool
      description "Tool for testing concurrency edge cases"
      category :testing
      
      parameter :concurrency_type do
        type :string
        required true
        constraints [enum: ["shared_state", "race_condition", "deadlock_sim", "process_flood"]]
      end
      
      parameter :identifier do
        type :string
        required false
        default "default"
      end
      
      execution do
        handler &ConcurrencyTool.execute/2
        timeout 5_000
      end
      
      security do
        sandbox :balanced
        capabilities [:execute]
      end
    end
    
    def execute(params, _context) do
      case params.concurrency_type do
        "shared_state" ->
          # Test shared state access
          :ets.new(:test_table, [:named_table, :public, :set])
          :ets.insert(:test_table, {params.identifier, System.monotonic_time()})
          {:ok, "Shared state updated for #{params.identifier}"}
        
        "race_condition" ->
          # Simulate race condition scenario
          Process.sleep(Enum.random(1..100))
          current_time = System.monotonic_time()
          {:ok, "Race condition test completed at #{current_time}"}
        
        "deadlock_sim" ->
          # Simulate potential deadlock scenario
          parent = self()
          spawn_link(fn ->
            Process.sleep(100)
            send(parent, :child_done)
          end)
          
          receive do
            :child_done -> {:ok, "Deadlock simulation completed"}
          after
            1000 -> {:error, "Deadlock timeout"}
          end
        
        "process_flood" ->
          # Test with many short-lived processes
          processes = Enum.map(1..100, fn i ->
            spawn(fn -> Process.sleep(10) end)
          end)
          
          {:ok, "Created #{length(processes)} processes"}
      end
    end
  end
  
  describe "result format edge cases" do
    test "handles empty results" do
      params = %{edge_case: "empty_result"}
      
      assert {:ok, result} = Executor.execute(EdgeCaseTool, params, @test_user)
      assert result.status == :success
      assert result.output == ""
    end
    
    test "handles nil results" do
      params = %{edge_case: "nil_result"}
      
      assert {:ok, result} = Executor.execute(EdgeCaseTool, params, @test_user)
      assert result.status == :success
      assert result.output == nil
    end
    
    test "handles large results" do
      params = %{edge_case: "large_result"}
      
      assert {:ok, result} = Executor.execute(EdgeCaseTool, params, @test_user)
      assert result.status == :success
      assert String.length(result.output) == 10_000
    end
    
    test "handles unicode results" do
      params = %{edge_case: "unicode"}
      
      assert {:ok, result} = Executor.execute(EdgeCaseTool, params, @test_user)
      assert result.status == :success
      assert result.output =~ "🌍"
      assert result.output =~ "こんにちは"
    end
    
    test "handles binary results" do
      params = %{edge_case: "binary"}
      
      assert {:ok, result} = Executor.execute(EdgeCaseTool, params, @test_user)
      assert result.status == :success
      assert result.output == <<1, 2, 3, 4, 5>>
    end
    
    test "handles nested errors" do
      params = %{edge_case: "nested_error"}
      
      assert {:error, :execution_failed, reason} = Executor.execute(EdgeCaseTool, params, @test_user)
      assert reason =~ "Nested error"
    end
  end
  
  describe "malformed tool responses" do
    test "handles wrong tuple format" do
      params = %{malformed_type: "wrong_tuple"}
      
      # Should handle gracefully
      result = Executor.execute(MalformedTool, params, @test_user)
      assert match?({:error, :execution_failed, _}, result)
    end
    
    test "handles atom results" do
      params = %{malformed_type: "atom_result"}
      
      result = Executor.execute(MalformedTool, params, @test_user)
      assert match?({:error, :execution_failed, _}, result)
    end
    
    test "handles invalid format results" do
      params = %{malformed_type: "invalid_format"}
      
      result = Executor.execute(MalformedTool, params, @test_user)
      assert match?({:error, :execution_failed, _}, result)
    end
    
    test "handles missing key results" do
      params = %{malformed_type: "missing_key"}
      
      result = Executor.execute(MalformedTool, params, @test_user)
      assert match?({:error, :execution_failed, _}, result)
    end
  end
  
  describe "boundary conditions" do
    test "handles maximum string length" do
      params = %{boundary_type: "max_string"}
      
      # May succeed or hit memory limits
      result = Executor.execute(BoundaryTool, params, @test_user)
      
      case result do
        {:ok, _} -> :ok
        {:error, :memory_limit_exceeded, _} -> :ok
        {:error, :timeout, _} -> :ok
      end
    end
    
    test "handles large integers" do
      params = %{boundary_type: "max_integer"}
      
      assert {:ok, result} = Executor.execute(BoundaryTool, params, @test_user)
      assert result.status == :success
      assert result.output =~ "Large integer:"
    end
    
    test "handles large lists" do
      params = %{boundary_type: "max_list"}
      
      # May succeed or hit memory limits
      result = Executor.execute(BoundaryTool, params, @test_user)
      
      case result do
        {:ok, _} -> :ok
        {:error, :memory_limit_exceeded, _} -> :ok
        {:error, :timeout, _} -> :ok
      end
    end
    
    test "handles empty values" do
      params = %{boundary_type: "empty_values"}
      
      assert {:ok, result} = Executor.execute(BoundaryTool, params, @test_user)
      assert result.status == :success
      assert is_map(result.output)
    end
    
    test "handles special characters" do
      params = %{boundary_type: "special_chars"}
      
      assert {:ok, result} = Executor.execute(BoundaryTool, params, @test_user)
      assert result.status == :success
      assert result.output =~ "!@#$%^&*"
    end
  end
  
  describe "parameter validation edge cases" do
    test "handles null/nil parameters" do
      assert {:error, :validation_failed, _} = Executor.execute(EdgeCaseTool, nil, @test_user)
      assert {:error, :validation_failed, _} = Executor.execute(EdgeCaseTool, %{edge_case: nil}, @test_user)
    end
    
    test "handles parameters with wrong types" do
      params = %{edge_case: 123}  # Should be string
      
      assert {:error, :validation_failed, errors} = Executor.execute(EdgeCaseTool, params, @test_user)
      assert is_list(errors)
    end
    
    test "handles parameters with unexpected keys" do
      params = %{
        edge_case: "empty_result",
        unexpected_key: "value",
        another_unexpected: 123
      }
      
      # Should ignore unexpected keys and validate normally
      assert {:ok, result} = Executor.execute(EdgeCaseTool, params, @test_user)
      assert result.status == :success
    end
    
    test "handles deeply nested parameter structures" do
      params = %{
        edge_case: "empty_result",
        data: %{
          level1: %{
            level2: %{
              level3: [1, 2, 3, %{level4: "deep"}]
            }
          }
        }
      }
      
      assert {:ok, result} = Executor.execute(EdgeCaseTool, params, @test_user)
      assert result.status == :success
    end
  end
  
  describe "authorization edge cases" do
    test "handles user with empty permissions" do
      empty_user = %{
        id: "empty-user",
        roles: [],
        permissions: []
      }
      
      params = %{edge_case: "empty_result"}
      
      assert {:error, :authorization_failed, _reason} = Executor.execute(EdgeCaseTool, params, empty_user)
    end
    
    test "handles user with nil values" do
      malformed_user = %{
        id: nil,
        roles: nil,
        permissions: nil
      }
      
      params = %{edge_case: "empty_result"}
      
      assert {:error, :authorization_failed, _reason} = Executor.execute(EdgeCaseTool, params, malformed_user)
    end
    
    test "handles user with invalid structure" do
      invalid_user = %{wrong_key: "value"}
      
      params = %{edge_case: "empty_result"}
      
      assert {:error, :authorization_failed, _reason} = Executor.execute(EdgeCaseTool, params, invalid_user)
    end
  end
  
  describe "sandbox edge cases" do
    test "handles sandbox with empty restrictions" do
      defmodule EmptySecurityTool do
        use RubberDuck.Tool
        
        tool do
          name :empty_security_tool
          description "Tool with empty security restrictions"
          
          parameter :input do
            type :string
            required true
          end
          
          execution do
            handler &EmptySecurityTool.execute/2
          end
          
          security do
            sandbox :balanced
            capabilities []
            file_access []
            network_access false
          end
        end
        
        def execute(params, _context) do
          {:ok, "Empty security result: #{params.input}"}
        end
      end
      
      params = %{input: "test"}
      
      assert {:ok, result} = Executor.execute(EmptySecurityTool, params, @test_user)
      assert result.status == :success
    end
    
    test "handles sandbox validation with edge case paths" do
      edge_paths = [
        "",
        "/",
        "///",
        "/tmp/../tmp/test",
        "/tmp/./test",
        "/tmp/test/../..",
        "relative/path",
        "~/home/test"
      ]
      
      config = %{file_access: ["/tmp/"]}
      
      results = Enum.map(edge_paths, fn path ->
        {path, Sandbox.validate_file_access(path, config)}
      end)
      
      # Should handle all edge cases gracefully
      assert Enum.all?(results, fn {_path, result} ->
        match?(:ok, result) or match?({:error, _}, result)
      end)
    end
  end
  
  describe "concurrency edge cases" do
    test "handles shared state access" do
      params = %{concurrency_type: "shared_state", identifier: "test1"}
      
      # Execute multiple times concurrently
      refs = Enum.map(1..5, fn i ->
        params_with_id = %{params | identifier: "test#{i}"}
        {:ok, ref} = Executor.execute_async(ConcurrencyTool, params_with_id, @test_user)
        ref
      end)
      
      # Wait for all results
      results = Enum.map(refs, fn ref ->
        assert_receive {^ref, {:ok, result}}, 2000
        result
      end)
      
      # All should succeed
      assert length(results) == 5
      assert Enum.all?(results, & &1.status == :success)
    end
    
    test "handles race conditions" do
      params = %{concurrency_type: "race_condition"}
      
      # Execute multiple times concurrently
      refs = Enum.map(1..10, fn _i ->
        {:ok, ref} = Executor.execute_async(ConcurrencyTool, params, @test_user)
        ref
      end)
      
      # Wait for all results
      results = Enum.map(refs, fn ref ->
        assert_receive {^ref, {:ok, result}}, 2000
        result
      end)
      
      # All should succeed despite race conditions
      assert length(results) == 10
      assert Enum.all?(results, & &1.status == :success)
      
      # Results should have different timestamps
      outputs = Enum.map(results, & &1.output)
      assert length(Enum.uniq(outputs)) > 1
    end
    
    test "handles deadlock simulation" do
      params = %{concurrency_type: "deadlock_sim"}
      
      assert {:ok, result} = Executor.execute(ConcurrencyTool, params, @test_user)
      assert result.status == :success
      assert result.output =~ "Deadlock simulation completed"
    end
    
    test "handles process flooding" do
      params = %{concurrency_type: "process_flood"}
      
      assert {:ok, result} = Executor.execute(ConcurrencyTool, params, @test_user)
      assert result.status == :success
      assert result.output =~ "Created 100 processes"
    end
  end
  
  describe "error recovery and resilience" do
    test "continues execution after tool failures" do
      # Mix of successful and failing executions
      operations = [
        {:ok, %{edge_case: "empty_result"}},
        {:error, %{edge_case: "nested_error"}},
        {:ok, %{edge_case: "unicode"}},
        {:error, %{edge_case: "nested_error"}},
        {:ok, %{edge_case: "binary"}}
      ]
      
      results = Enum.map(operations, fn {expected, params} ->
        case expected do
          :ok -> Executor.execute(EdgeCaseTool, params, @test_user)
          :error -> Executor.execute(EdgeCaseTool, params, @test_user)
        end
      end)
      
      # Should have mix of successes and failures
      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _, _}, &1))
      
      assert successes == 3
      assert failures == 2
    end
    
    test "handles system resource exhaustion gracefully" do
      # Try to exhaust different system resources
      resource_tests = [
        %{boundary_type: "max_string"},
        %{boundary_type: "max_list"},
        %{boundary_type: "max_integer"}
      ]
      
      results = Enum.map(resource_tests, fn params ->
        Executor.execute(BoundaryTool, params, @test_user)
      end)
      
      # Should handle all gracefully (either succeed or fail gracefully)
      assert Enum.all?(results, fn result ->
        case result do
          {:ok, _} -> true
          {:error, :memory_limit_exceeded, _} -> true
          {:error, :timeout, _} -> true
          {:error, :execution_failed, _} -> true
          _ -> false
        end
      end)
    end
  end
  
  describe "cleanup and resource management" do
    test "cleans up resources after execution" do
      # Execute tool that creates resources
      params = %{concurrency_type: "process_flood"}
      
      initial_process_count = length(Process.list())
      
      assert {:ok, _result} = Executor.execute(ConcurrencyTool, params, @test_user)
      
      # Give some time for cleanup
      Process.sleep(100)
      
      final_process_count = length(Process.list())
      
      # Should not have significantly more processes
      assert final_process_count - initial_process_count < 50
    end
    
    test "handles memory cleanup after large operations" do
      params = %{boundary_type: "max_string"}
      
      initial_memory = :erlang.memory(:total)
      
      # Execute (may fail due to memory limits)
      _result = Executor.execute(BoundaryTool, params, @test_user)
      
      # Force garbage collection
      :erlang.garbage_collect()
      Process.sleep(100)
      
      final_memory = :erlang.memory(:total)
      memory_increase = final_memory - initial_memory
      
      # Memory increase should be reasonable
      assert memory_increase < 100_000_000  # Less than 100MB permanent increase
    end
  end
end
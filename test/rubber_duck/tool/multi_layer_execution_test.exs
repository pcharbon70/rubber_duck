defmodule RubberDuck.Tool.MultiLayerExecutionTest do
  @moduledoc """
  Comprehensive integration tests for the multi-layer execution architecture.

  Tests the complete pipeline: validation → authorization → execution → result processing
  """

  use ExUnit.Case, async: true

  alias RubberDuck.Tool.Executor

  # Test users with different permission levels
  @admin_user %{
    id: "admin-123",
    roles: [:admin],
    permissions: [:all]
  }

  @regular_user %{
    id: "user-456",
    roles: [:user],
    permissions: [:read, :execute, :file_read, :file_write]
  }

  @restricted_user %{
    id: "restricted-789",
    roles: [:restricted],
    permissions: [:read]
  }

  @guest_user %{
    id: "guest-000",
    roles: [:guest],
    permissions: []
  }

  # Test tools with different security configurations
  defmodule BasicTool do
    use RubberDuck.Tool

    tool do
      name :basic_tool
      description "A basic tool with minimal security"
      category(:basic)

      parameter :input do
        type :string
        required(true)
        constraints min_length: 1, max_length: 100
      end

      parameter :format do
        type :string
        required(false)
        default "text"
        constraints enum: ["text", "json", "xml"]
      end

      execution do
        handler(&BasicTool.execute/2)
        timeout 5_000
        retries(1)
      end

      security do
        sandbox(:balanced)
        capabilities([:execute])
      end
    end

    def execute(params, context) do
      format = params[:format] || "text"

      output =
        case format do
          "json" -> Jason.encode!(%{message: params.input, user: context.user.id})
          "xml" -> "<message user=\"#{context.user.id}\">#{params.input}</message>"
          _ -> "#{params.input} (processed by #{context.user.id})"
        end

      {:ok, output}
    end
  end

  defmodule SecureTool do
    use RubberDuck.Tool

    tool do
      name :secure_tool
      description "A highly secure tool with strict sandboxing"
      category(:security)

      parameter :action do
        type :string
        required(true)
        constraints enum: ["read", "write", "delete"]
      end

      parameter :path do
        type :string
        required(true)
        constraints pattern: "^/tmp/.*$"
      end

      execution do
        handler(&SecureTool.execute/2)
        timeout 10_000
        retries(0)
      end

      security do
        sandbox(:strict)
        capabilities([:file_read, :file_write])
        file_access(["/tmp/"])
        network_access(false)
      end
    end

    def execute(params, _context) do
      case params.action do
        "read" -> {:ok, "Reading from #{params.path}"}
        "write" -> {:ok, "Writing to #{params.path}"}
        "delete" -> {:ok, "Deleting #{params.path}"}
      end
    end
  end

  defmodule AdminTool do
    use RubberDuck.Tool

    tool do
      name :admin_tool
      description "An admin-only tool with elevated privileges"
      category(:admin)

      parameter :command do
        type :string
        required(true)
        constraints enum: ["status", "restart", "shutdown"]
      end

      parameter :force do
        type :boolean
        required(false)
        default false
      end

      execution do
        handler(&AdminTool.execute/2)
        timeout 30_000
        retries(0)
      end

      security do
        sandbox(:relaxed)
        capabilities([:admin_access, :system_modify])
        network_access(true)
      end
    end

    def execute(params, _context) do
      force_text = if params[:force], do: " (forced)", else: ""
      {:ok, "Executing #{params.command}#{force_text}"}
    end
  end

  defmodule ErrorTool do
    use RubberDuck.Tool

    tool do
      name :error_tool
      description "A tool that simulates various error conditions"
      category(:testing)

      parameter :error_type do
        type :string
        required(true)
        constraints enum: ["timeout", "memory", "crash", "validation"]
      end

      execution do
        handler(&ErrorTool.execute/2)
        timeout 5_000
        retries(2)
      end

      security do
        sandbox(:strict)
        capabilities([:execute])
      end
    end

    def execute(params, _context) do
      case params.error_type do
        "timeout" ->
          Process.sleep(10_000)
          {:ok, "Should not reach here"}

        "memory" ->
          # Create large data structure
          _big_list = Enum.to_list(1..10_000_000)
          {:ok, "Memory consumed"}

        "crash" ->
          raise "Simulated crash"

        "validation" ->
          {:ok, "This should not validate"}
      end
    end
  end

  defmodule AsyncTool do
    use RubberDuck.Tool

    tool do
      name :async_tool
      description "A tool for testing async execution"
      category(:async)

      parameter :delay do
        type :integer
        required(false)
        default 100
        constraints min: 1, max: 5000
      end

      parameter :result do
        type :string
        required(false)
        default "async_complete"
      end

      execution do
        handler(&AsyncTool.execute/2)
        timeout 10_000
        async(true)
      end

      security do
        sandbox(:balanced)
        capabilities([:execute])
      end
    end

    def execute(params, _context) do
      Process.sleep(params[:delay] || 100)
      {:ok, params[:result] || "async_complete"}
    end
  end

  describe "validation layer" do
    test "validates parameters through complete pipeline" do
      # Valid parameters
      params = %{input: "test", format: "json"}
      assert {:ok, result} = Executor.execute(BasicTool, params, @regular_user)
      assert result.status == :success

      # Invalid parameters - missing required
      params = %{format: "json"}
      assert {:error, :validation_failed, errors} = Executor.execute(BasicTool, params, @regular_user)
      assert is_list(errors)

      # Invalid parameters - wrong type
      params = %{input: 123, format: "json"}
      assert {:error, :validation_failed, errors} = Executor.execute(BasicTool, params, @regular_user)
      assert is_list(errors)

      # Invalid parameters - constraint violation
      params = %{input: "test", format: "invalid"}
      assert {:error, :validation_failed, errors} = Executor.execute(BasicTool, params, @regular_user)
      assert is_list(errors)
    end

    test "validates complex constraints" do
      # Valid secure tool parameters
      params = %{action: "read", path: "/tmp/test.txt"}
      assert {:ok, result} = Executor.execute(SecureTool, params, @regular_user)
      assert result.status == :success

      # Invalid path pattern
      params = %{action: "read", path: "/etc/passwd"}
      assert {:error, :validation_failed, errors} = Executor.execute(SecureTool, params, @regular_user)
      assert is_list(errors)

      # Invalid action enum
      params = %{action: "execute", path: "/tmp/test.txt"}
      assert {:error, :validation_failed, errors} = Executor.execute(SecureTool, params, @regular_user)
      assert is_list(errors)
    end

    test "validates optional parameters with defaults" do
      # Using default format
      params = %{input: "test"}
      assert {:ok, result} = Executor.execute(BasicTool, params, @regular_user)
      assert result.output =~ "test"

      # Using default delay
      params = %{result: "delayed"}
      assert {:ok, execution_ref} = Executor.execute_async(AsyncTool, params, @regular_user)
      assert_receive {^execution_ref, {:ok, result}}, 1000
      assert result.output == "delayed"
    end
  end

  describe "authorization layer" do
    test "authorizes based on capabilities" do
      # Regular user can execute basic tools
      params = %{input: "test"}
      assert {:ok, result} = Executor.execute(BasicTool, params, @regular_user)
      assert result.status == :success

      # Regular user can execute secure tools (has file_read capability)
      params = %{action: "read", path: "/tmp/test.txt"}
      assert {:ok, result} = Executor.execute(SecureTool, params, @regular_user)
      assert result.status == :success

      # Regular user cannot execute admin tools
      params = %{command: "status"}
      assert {:error, :authorization_failed, reason} = Executor.execute(AdminTool, params, @regular_user)
      assert reason in [:insufficient_capabilities, :insufficient_role]
    end

    test "authorizes based on roles" do
      # Admin can execute any tool
      params = %{command: "status"}
      assert {:ok, result} = Executor.execute(AdminTool, params, @admin_user)
      assert result.status == :success

      # Restricted user cannot execute tools requiring write capabilities
      params = %{action: "write", path: "/tmp/test.txt"}
      assert {:error, :authorization_failed, _reason} = Executor.execute(SecureTool, params, @restricted_user)

      # Guest user cannot execute any tools
      params = %{input: "test"}
      assert {:error, :authorization_failed, _reason} = Executor.execute(BasicTool, params, @guest_user)
    end

    test "provides context-aware authorization" do
      # Authorization depends on execution context
      read_params = %{action: "read", path: "/tmp/test.txt"}
      write_params = %{action: "write", path: "/tmp/test.txt"}

      # User with only read capability
      user = %{@regular_user | permissions: [:read, :file_read]}

      # Read should succeed
      assert {:ok, _result} = Executor.execute(SecureTool, read_params, user)

      # Write should fail (needs file_write capability)
      assert {:error, :authorization_failed, _reason} = Executor.execute(SecureTool, write_params, user)
    end
  end

  describe "execution layer" do
    test "executes tools in sandbox environment" do
      params = %{input: "test", format: "json"}

      assert {:ok, result} = Executor.execute(BasicTool, params, @regular_user)
      assert result.status == :success
      assert result.output =~ "user-456"
      assert is_map(result.metadata)
      assert result.metadata.tool_name == :basic_tool
    end

    test "enforces sandbox security levels" do
      # Strict sandbox (SecureTool)
      params = %{action: "read", path: "/tmp/test.txt"}
      assert {:ok, result} = Executor.execute(SecureTool, params, @regular_user)
      assert result.status == :success

      # Relaxed sandbox (AdminTool)
      params = %{command: "status"}
      assert {:ok, result} = Executor.execute(AdminTool, params, @admin_user)
      assert result.status == :success
    end

    test "handles async execution" do
      params = %{delay: 200, result: "async_test"}

      assert {:ok, execution_ref} = Executor.execute_async(AsyncTool, params, @regular_user)
      assert is_reference(execution_ref)

      # Wait for completion
      assert_receive {^execution_ref, {:ok, result}}, 2000
      assert result.output == "async_test"
      assert result.status == :success
    end

    test "handles execution timeouts" do
      params = %{error_type: "timeout"}

      # Should timeout
      assert {:error, :timeout} = Executor.execute(ErrorTool, params, @regular_user)
    end

    test "handles memory limits" do
      params = %{error_type: "memory"}

      # Should hit memory limit
      assert {:error, :memory_limit_exceeded, _details} = Executor.execute(ErrorTool, params, @regular_user)
    end

    test "handles execution errors with retries" do
      params = %{error_type: "crash"}

      # Should fail even with retries
      assert {:error, :execution_failed, reason} = Executor.execute(ErrorTool, params, @regular_user)
      assert reason =~ "Simulated crash"
    end
  end

  describe "result processing layer" do
    test "processes successful results" do
      params = %{input: "test", format: "json"}

      assert {:ok, result} = Executor.execute(BasicTool, params, @regular_user)
      assert result.status == :success
      assert is_binary(result.output)
      assert is_map(result.metadata)
      assert is_number(result.execution_time)
      assert is_number(result.metadata.started_at)
      assert is_number(result.metadata.completed_at)
    end

    test "processes error results" do
      params = %{error_type: "crash"}

      assert {:error, :execution_failed, reason} = Executor.execute(ErrorTool, params, @regular_user)
      assert is_binary(reason)
    end

    test "includes execution metadata" do
      params = %{input: "test"}

      assert {:ok, result} = Executor.execute(BasicTool, params, @regular_user)

      # Check metadata structure
      metadata = result.metadata
      assert metadata.tool_name == :basic_tool
      assert metadata.user_id == "user-456"
      assert is_binary(metadata.execution_id)
      assert is_number(metadata.started_at)
      assert is_number(metadata.completed_at)
      assert metadata.completed_at >= metadata.started_at
    end
  end

  describe "complete pipeline integration" do
    test "executes full pipeline with all layers" do
      # This test validates the complete flow:
      # 1. Parameter validation
      # 2. User authorization
      # 3. Sandboxed execution
      # 4. Result processing

      params = %{input: "integration_test", format: "json"}

      # Trace the execution through all layers
      assert {:ok, result} = Executor.execute(BasicTool, params, @regular_user)

      # Validate result structure
      assert result.status == :success
      assert is_binary(result.output)
      assert result.output =~ "integration_test"
      assert result.output =~ "user-456"

      # Validate metadata
      assert is_map(result.metadata)
      assert result.metadata.tool_name == :basic_tool
      assert result.metadata.user_id == "user-456"
      assert is_binary(result.metadata.execution_id)
      assert is_number(result.execution_time)
      assert result.execution_time > 0
    end

    test "handles pipeline failures at different layers" do
      # Validation layer failure
      # Too short
      params = %{input: ""}
      assert {:error, :validation_failed, errors} = Executor.execute(BasicTool, params, @regular_user)
      assert is_list(errors)

      # Authorization layer failure
      params = %{command: "shutdown"}
      assert {:error, :authorization_failed, _reason} = Executor.execute(AdminTool, params, @regular_user)

      # Execution layer failure
      params = %{error_type: "crash"}
      assert {:error, :execution_failed, reason} = Executor.execute(ErrorTool, params, @regular_user)
      assert is_binary(reason)
    end

    test "maintains consistency across concurrent executions" do
      # Execute multiple tools concurrently
      params = %{input: "concurrent_test", format: "text"}

      # Start multiple async executions
      execution_refs =
        Enum.map(1..5, fn i ->
          params_with_id = %{params | input: "concurrent_test_#{i}"}
          {:ok, ref} = Executor.execute_async(BasicTool, params_with_id, @regular_user)
          {ref, i}
        end)

      # Wait for all results
      results =
        Enum.map(execution_refs, fn {ref, i} ->
          assert_receive {^ref, {:ok, result}}, 2000
          {result, i}
        end)

      # Verify all succeeded
      assert length(results) == 5
      assert Enum.all?(results, fn {result, _i} -> result.status == :success end)

      # Verify results are distinct
      outputs = Enum.map(results, fn {result, _i} -> result.output end)
      assert length(Enum.uniq(outputs)) == 5
    end
  end

  describe "error handling and recovery" do
    test "gracefully handles malformed input" do
      # Non-map parameters should be handled gracefully
      result = Executor.execute(BasicTool, "not_a_map", @regular_user)
      assert match?({:error, _, _}, result)

      # Nil parameters should be handled gracefully
      result = Executor.execute(BasicTool, nil, @regular_user)
      assert match?({:error, _, _}, result)
    end

    test "handles invalid user contexts" do
      # Malformed user
      malformed_user = %{invalid: "user"}
      params = %{input: "test"}

      assert {:error, :authorization_failed, _reason} = Executor.execute(BasicTool, params, malformed_user)
    end

    test "handles tool module errors" do
      # Non-existent tool should be handled gracefully
      params = %{input: "test"}
      result = Executor.execute(NonExistentTool, params, @regular_user)
      assert match?({:error, _, _}, result)
    end

    test "provides detailed error information" do
      # Validation error
      params = %{input: "test", format: "invalid"}
      assert {:error, :validation_failed, errors} = Executor.execute(BasicTool, params, @regular_user)
      assert is_list(errors)
      assert length(errors) > 0

      error = List.first(errors)
      assert Map.has_key?(error, :field)
      assert Map.has_key?(error, :message)
      assert Map.has_key?(error, :type)
    end
  end

  describe "performance and resource management" do
    test "enforces resource limits" do
      # Memory limit test
      params = %{error_type: "memory"}
      assert {:error, :memory_limit_exceeded, _details} = Executor.execute(ErrorTool, params, @regular_user)

      # Timeout test
      params = %{error_type: "timeout"}
      assert {:error, :timeout, _details} = Executor.execute(ErrorTool, params, @regular_user)
    end

    test "manages concurrent execution limits" do
      # Test with multiple long-running tasks
      long_params = %{delay: 1000}

      # Start multiple executions
      refs =
        Enum.map(1..3, fn _i ->
          {:ok, ref} = Executor.execute_async(AsyncTool, long_params, @regular_user)
          ref
        end)

      # All should start successfully
      assert length(refs) == 3

      # Cancel them to avoid timeout
      Enum.each(refs, fn ref ->
        Executor.cancel_execution(ref)
      end)
    end

    test "tracks execution performance" do
      params = %{input: "performance_test"}

      start_time = System.monotonic_time(:millisecond)
      assert {:ok, result} = Executor.execute(BasicTool, params, @regular_user)
      end_time = System.monotonic_time(:millisecond)

      # Should complete quickly
      assert end_time - start_time < 1000

      # Should track execution time
      assert is_number(result.execution_time)
      assert result.execution_time > 0
    end
  end
end

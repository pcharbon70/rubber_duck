defmodule RubberDuck.OllamaExecutionTraceTest do
  use ExUnit.Case

  alias RubberDuck.LLM.ConnectionManager
  alias RubberDuck.LLM.Service

  describe "ollama execution trace" do
    test "trace where conversation send hangs step by step" do
      # Step 1: Test ConnectionManager.status() directly
      IO.puts("=== Testing ConnectionManager.status() ===")
      start_time = System.monotonic_time(:millisecond)

      status_result =
        try do
          ConnectionManager.status()
        rescue
          error -> {:error, error}
        catch
          :exit, reason -> {:exit, reason}
        end

      end_time = System.monotonic_time(:millisecond)
      status_time = end_time - start_time

      IO.puts("ConnectionManager.status() result: #{inspect(status_result)}")
      IO.puts("ConnectionManager.status() time: #{status_time}ms")

      # Step 2: Test LLM Service model validation
      IO.puts("\n=== Testing LLM Service model validation ===")
      start_time = System.monotonic_time(:millisecond)

      # Try a simple completion request to see where it fails
      opts = [
        model: "codellama",
        messages: [%{role: "user", content: "test"}],
        # Short timeout to see if it's hanging
        timeout: 5_000
      ]

      service_result =
        try do
          Task.async(fn -> Service.completion(opts) end)
          |> Task.await(5_100)
        rescue
          error -> {:error, error}
        catch
          :exit, reason -> {:exit, reason}
          :timeout -> {:timeout, "Service call exceeded 5 seconds"}
        end

      end_time = System.monotonic_time(:millisecond)
      service_time = end_time - start_time

      IO.puts("LLM Service.completion() result: #{inspect(service_result)}")
      IO.puts("LLM Service.completion() time: #{service_time}ms")

      # Step 3: Test conversation handler ensure_llm_connected
      IO.puts("\n=== Testing conversation handler ensure_llm_connected ===")
      start_time = System.monotonic_time(:millisecond)

      # Access the private function via module compilation
      ensure_result =
        try do
          # Create a simple test to call ensure_llm_connected logic
          case ConnectionManager.status() do
            connections when is_map(connections) ->
              connected? =
                Enum.any?(connections, fn {_provider, info} ->
                  info.status == :connected && info.health in [:ok, :healthy]
                end)

              if connected?, do: :ok, else: {:error, :no_llm_connected}

            _ ->
              {:error, :no_llm_connected}
          end
        rescue
          error -> {:error, error}
        catch
          :exit, reason -> {:exit, reason}
        end

      end_time = System.monotonic_time(:millisecond)
      ensure_time = end_time - start_time

      IO.puts("ensure_llm_connected logic result: #{inspect(ensure_result)}")
      IO.puts("ensure_llm_connected logic time: #{ensure_time}ms")

      # The test always passes, we're just tracing execution
      assert true
    end
  end
end

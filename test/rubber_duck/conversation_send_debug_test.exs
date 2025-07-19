defmodule RubberDuck.ConversationSendDebugTest do
  use ExUnit.Case
  require Logger

  alias RubberDuck.Commands.{Command, Context}
  alias RubberDuck.Commands.Handlers.Conversation
  alias RubberDuck.LLM.{ConnectionManager, Service}

  describe "debug conversation send with actual processes" do
    test "trace why conversation send doesn't return response" do
      # First check what providers and models are configured
      providers = Application.get_env(:rubber_duck, :llm, [])[:providers] || []

      IO.puts("\n=== Configured Providers ===")

      Enum.each(providers, fn provider ->
        IO.puts("Provider: #{inspect(provider.name)}")
        IO.puts("  Models: #{inspect(provider[:models])}")
        IO.puts("  Adapter: #{inspect(provider.adapter)}")
      end)

      # Check if processes are running
      IO.puts("\n=== Process Status ===")
      conn_mgr_pid = Process.whereis(ConnectionManager)
      llm_svc_pid = Process.whereis(Service)

      IO.puts("ConnectionManager: #{inspect(conn_mgr_pid)}")
      IO.puts("LLM Service: #{inspect(llm_svc_pid)}")

      # If ConnectionManager is running, check status
      if conn_mgr_pid do
        IO.puts("\n=== ConnectionManager Status ===")

        try do
          status = ConnectionManager.status()
          IO.inspect(status, label: "Connection Status", pretty: true)
        catch
          kind, error ->
            IO.puts("Error getting status: #{kind} - #{inspect(error)}")
        end
      end

      # If LLM Service is running, check available models
      if llm_svc_pid do
        IO.puts("\n=== LLM Service Models ===")

        try do
          {:ok, models} = Service.list_models()

          Enum.each(models, fn model ->
            IO.puts("Model: #{model.model} (Provider: #{model.provider}, Available: #{model.available})")
          end)
        catch
          kind, error ->
            IO.puts("Error listing models: #{kind} - #{inspect(error)}")
        end
      end

      # Try a simple completion directly with LLM Service
      if llm_svc_pid do
        IO.puts("\n=== Direct LLM Service Test ===")

        opts = [
          model: "codellama",
          messages: [%{role: "user", content: "test"}],
          timeout: 10_000
        ]

        IO.puts("Testing with options: #{inspect(opts)}")

        start_time = System.monotonic_time(:millisecond)

        result =
          try do
            Service.completion(opts)
          catch
            kind, error ->
              {:error, {kind, error}}
          end

        end_time = System.monotonic_time(:millisecond)

        IO.puts("Result: #{inspect(result)}")
        IO.puts("Time taken: #{end_time - start_time}ms")
      end

      # Now test through conversation handler
      IO.puts("\n=== Conversation Handler Test ===")

      # Create a minimal context
      {:ok, context} =
        Context.new(%{
          user_id: "test-user-001",
          session_id: "test-session",
          permissions: [:read, :write]
        })

      # Create conversation start command
      start_cmd = %Command{
        name: :conversation,
        subcommand: :start,
        args: ["Debug Test"],
        options: %{},
        context: context,
        client_type: :cli,
        format: :text
      }

      IO.puts("Starting conversation...")
      start_result = Conversation.execute(start_cmd)
      IO.inspect(start_result, label: "Start Result", pretty: true)

      case start_result do
        {:ok, response} when is_binary(response) ->
          # Extract conversation ID from response
          case Regex.run(~r/ID: ([a-f0-9\-]+)/, response) do
            [_, conv_id] ->
              IO.puts("\nConversation ID: #{conv_id}")

              # Now try to send a message
              send_cmd = %Command{
                name: :conversation,
                subcommand: :send,
                args: ["What is 2+2?"],
                options: %{conversation: conv_id},
                context: context,
                client_type: :cli,
                format: :text
              }

              IO.puts("\nSending message...")
              start_time = System.monotonic_time(:millisecond)
              send_result = Conversation.execute(send_cmd)
              end_time = System.monotonic_time(:millisecond)

              IO.inspect(send_result, label: "Send Result", pretty: true)
              IO.puts("Time taken: #{end_time - start_time}ms")

            nil ->
              IO.puts("Could not extract conversation ID from response")
          end

        error ->
          IO.puts("Failed to start conversation: #{inspect(error)}")
      end

      # Always pass the test - this is for debugging
      assert true
    end
  end
end

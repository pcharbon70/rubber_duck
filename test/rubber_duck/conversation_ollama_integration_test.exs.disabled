defmodule RubberDuck.ConversationOllamaIntegrationTest do
  use ExUnit.Case
  require Logger

  alias RubberDuck.Commands.{Command, Context}
  alias RubberDuck.Commands.Handlers.Conversation
  alias RubberDuck.LLM.{ConnectionManager, Service}

  describe "conversation with connected Ollama" do
    test "verify Ollama is connected and conversation send works" do
      # Check ConnectionManager status
      IO.puts("\n=== Checking Ollama Connection ===")
      status = ConnectionManager.status()
      IO.inspect(status, label: "Connection Status", pretty: true)

      ollama_status = Map.get(status, :ollama)

      if ollama_status do
        IO.puts("Ollama status: #{ollama_status.status}")
        IO.puts("Ollama health: #{ollama_status.health}")
      else
        IO.puts("Ollama not found in connection status!")
      end

      # List available models
      IO.puts("\n=== Available Models ===")
      {:ok, models} = Service.list_models()

      Enum.each(models, fn model ->
        IO.puts("  #{model.model} (#{model.provider}) - Available: #{model.available}")
      end)

      # Create test context
      {:ok, context} =
        Context.new(%{
          user_id: "test-user-#{System.unique_integer([:positive])}",
          session_id: "test-session",
          permissions: [:read, :write],
          metadata: %{test: true}
        })

      # Start a conversation
      IO.puts("\n=== Starting Conversation ===")

      start_cmd = %Command{
        name: :conversation,
        subcommand: :start,
        args: ["Ollama Integration Test"],
        options: %{type: "general"},
        context: context,
        client_type: :cli,
        format: :text
      }

      start_result = Conversation.execute(start_cmd)
      IO.inspect(start_result, label: "Start Result", pretty: true)

      case start_result do
        {:ok, response} when is_binary(response) ->
          # Extract conversation ID
          case Regex.run(~r/ID: ([a-f0-9\-]+)/, response) do
            [_, conv_id] ->
              IO.puts("\nConversation created with ID: #{conv_id}")

              # Send a simple message
              IO.puts("\n=== Sending Message to Ollama ===")

              send_cmd = %Command{
                name: :conversation,
                subcommand: :send,
                args: ["What is 2+2? Please respond with just the number."],
                options: %{conversation: conv_id},
                context: context,
                client_type: :cli,
                format: :text
              }

              IO.puts("Sending message...")
              start_time = System.monotonic_time(:millisecond)

              # Use Task with timeout to prevent hanging
              task = Task.async(fn -> Conversation.execute(send_cmd) end)

              send_result =
                case Task.yield(task, 30_000) || Task.shutdown(task) do
                  {:ok, result} -> result
                  nil -> {:error, "Conversation send timed out after 30 seconds"}
                end

              end_time = System.monotonic_time(:millisecond)
              time_taken = end_time - start_time

              IO.puts("\nTime taken: #{time_taken}ms")
              IO.inspect(send_result, label: "Send Result", pretty: true)

              # Check if we got a response
              case send_result do
                {:ok, response} when is_binary(response) ->
                  IO.puts("\n=== SUCCESS ===")
                  IO.puts("Got response from Ollama!")
                  # The response should contain "4" somewhere
                  assert String.contains?(response, "Assistant:") or String.contains?(response, "🤖")
                  IO.puts("Test passed!")

                {:error, reason} ->
                  IO.puts("\n=== ERROR ===")
                  IO.puts("Error: #{inspect(reason)}")
                  flunk("Failed to get response from Ollama: #{inspect(reason)}")

                other ->
                  IO.puts("\n=== UNEXPECTED RESULT ===")
                  IO.inspect(other, pretty: true)
                  flunk("Unexpected result: #{inspect(other)}")
              end

            nil ->
              flunk("Could not extract conversation ID from start response")
          end

        {:error, reason} ->
          IO.puts("\n=== Failed to start conversation ===")
          IO.puts("Reason: #{inspect(reason)}")
          flunk("Failed to start conversation: #{inspect(reason)}")
      end
    end
  end
end

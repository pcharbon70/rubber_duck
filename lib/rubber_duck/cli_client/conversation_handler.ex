defmodule RubberDuck.CLIClient.ConversationHandler do
  @moduledoc """
  Handles interactive conversation mode for the CLI client.
  
  Manages the chat REPL, WebSocket connection, and streaming responses.
  """

  alias RubberDuck.CLIClient.{Auth, Client}
  require Logger

  @prompt "rubber_duck> "
  @assistant_prefix "🤖 "
  @user_prefix "👤 "
  @system_prefix "ℹ️  "

  @doc """
  Runs the interactive chat mode.
  """
  def run_chat(args, opts) do
    conversation_id = Map.get(args.args, :conversation_id)
    title = Map.get(args.options, :title, "CLI Chat Session")
    
    # Start the WebSocket client if not already running
    ensure_client_started(opts)
    
    # Check if an LLM is connected before proceeding
    case check_llm_status() do
      {:ok, _} ->
        # Continue with chat
        :ok
      {:error, :no_llm_connected} ->
        IO.puts(:stderr, """
        Error: No LLM provider is connected.
        
        Please connect an LLM provider first using:
          rubber_duck llm connect <provider>
          
        Available providers can be listed with:
          rubber_duck llm status
        """)
        System.halt(1)
      {:error, reason} ->
        # Some other error (like server connection)
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
    
    # Create or join conversation
    conversation_id = if conversation_id do
      # Verify the conversation exists
      case send_command(["conversation", "show", conversation_id]) do
        {:ok, _} -> 
          IO.puts("#{@system_prefix}Joining conversation: #{conversation_id}")
          conversation_id
        {:error, _} ->
          IO.puts(:stderr, "Error: Conversation #{conversation_id} not found")
          System.halt(1)
      end
    else
      # Create new conversation
      case send_command(["conversation", "start", title]) do
        {:ok, response} ->
          # Extract conversation ID from response
          case extract_conversation_id(response) do
            {:ok, id} ->
              IO.puts("#{@system_prefix}Started new conversation: #{title}")
              IO.puts("#{@system_prefix}Conversation ID: #{id}")
              id
            {:error, _} ->
              IO.puts(:stderr, "Error: Failed to create conversation")
              System.halt(1)
          end
        {:error, reason} ->
          IO.puts(:stderr, "Error: #{reason}")
          System.halt(1)
      end
    end
    
    # Show welcome message
    show_welcome()
    
    # Start the REPL
    chat_loop(conversation_id)
  end

  defp ensure_client_started(opts) do
    case Process.whereis(RubberDuck.CLIClient.Client) do
      nil ->
        # Start the client
        server_url = opts[:server] || Auth.get_server_url()
        api_key = Auth.get_api_key()
        
        {:ok, _pid} = Client.start_link(url: server_url, api_key: api_key)
        
        # Wait for connection
        Process.sleep(500)
        
      _pid ->
        # Client already running
        :ok
    end
  end

  defp chat_loop(conversation_id) do
    case IO.gets(@prompt) do
      :eof ->
        IO.puts("\n#{@system_prefix}Goodbye!")
        System.halt(0)
        
      {:error, reason} ->
        IO.puts(:stderr, "\nError reading input: #{inspect(reason)}")
        System.halt(1)
        
      input ->
        input = String.trim(input)
        
        case input do
          "/exit" ->
            IO.puts("#{@system_prefix}Goodbye!")
            System.halt(0)
            
          "/help" ->
            show_help()
            chat_loop(conversation_id)
            
          "/clear" ->
            clear_screen()
            chat_loop(conversation_id)
            
          "/history" ->
            show_history(conversation_id)
            chat_loop(conversation_id)
            
          "" ->
            # Empty input, just show prompt again
            chat_loop(conversation_id)
            
          message ->
            # Send message and handle response
            handle_message(conversation_id, message)
            chat_loop(conversation_id)
        end
    end
  end

  defp handle_message(conversation_id, message) do
    IO.puts("#{@user_prefix}#{message}")
    
    # Show typing indicator
    typing_task = Task.async(fn -> show_typing_indicator() end)
    
    # Send message through conversation send command
    case send_streaming_command(
      ["conversation", "send", message, "--conversation", conversation_id],
      &handle_stream_chunk/1
    ) do
      {:ok, _} ->
        # Response already printed by stream handler
        :ok
        
      {:error, reason} ->
        IO.puts(:stderr, "\n#{@system_prefix}Error: #{reason}")
    end
    
    # Cancel typing indicator
    Task.shutdown(typing_task, :brutal_kill)
    IO.write("\r\e[K") # Clear the typing line
  end

  defp handle_stream_chunk(chunk) do
    case chunk do
      %{content: content} when is_binary(content) ->
        # First chunk, clear typing indicator and start response
        IO.write("\r\e[K#{@assistant_prefix}")
        IO.write(content)
        
      %{metadata: %{type: "content_block_delta"}, content: content} ->
        # Continuation chunk
        IO.write(content)
        
      %{metadata: %{type: "message_stop"}} ->
        # End of message
        IO.puts("")
        
      _ ->
        # Other chunk types, ignore for now
        :ok
    end
  end

  defp show_typing_indicator do
    frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    Enum.each(Stream.cycle(frames), fn frame ->
      IO.write("\r#{@assistant_prefix}#{frame} Thinking...")
      Process.sleep(100)
    end)
  end

  defp send_command(args) do
    config = build_config()
    
    case RubberDuck.CLIClient.UnifiedIntegration.execute_command(args, config) do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_streaming_command(args, handler) do
    config = build_config()
    
    # For streaming, we need to use the WebSocket client directly
    # The client expects a command string and params
    command = Enum.join(args, " ")
    
    case Client.send_streaming_command(command, config, handler) do
      {:ok, _} -> {:ok, ""}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_config do
    %{
      user_id: Auth.get_user_id(),
      session_id: "cli_chat_#{System.system_time(:millisecond)}",
      permissions: [:read, :write, :execute],
      format: :text,
      server_url: Auth.get_server_url(),
      metadata: %{
        cli_version: "0.1.0",
        interactive: true
      }
    }
  end

  @doc """
  Extracts conversation ID from a response text.
  Used by both ConversationHandler and REPLHandler.
  """
  def extract_conversation_id(response) do
    # Try to extract ID from response text
    case Regex.run(~r/ID:\s*([a-f0-9-]+)/i, response) do
      [_, id] -> {:ok, id}
      _ -> {:error, "Could not extract conversation ID"}
    end
  end

  defp show_welcome do
    IO.puts("""
    
    #{@system_prefix}Welcome to RubberDuck Interactive Chat!
    #{@system_prefix}Type /help for commands, /exit to quit.
    
    """)
  end

  defp show_help do
    IO.puts("""
    
    #{@system_prefix}Available commands:
      /help     - Show this help message
      /exit     - Exit the chat
      /clear    - Clear the screen
      /history  - Show conversation history
    
    """)
  end

  defp show_history(conversation_id) do
    case send_command(["conversation", "show", conversation_id]) do
      {:ok, history} ->
        IO.puts("\n#{@system_prefix}Conversation History:")
        IO.puts(history)
        IO.puts("")
      {:error, reason} ->
        IO.puts(:stderr, "\n#{@system_prefix}Error loading history: #{reason}")
    end
  end

  defp clear_screen do
    IO.write("\e[2J\e[H")
    show_welcome()
  end
  
  defp check_llm_status do
    # Send an llm status command to check if any LLM is connected
    case send_command(["llm", "status"]) do
      {:ok, status_output} ->
        # Parse the output to see if any provider is connected
        if String.contains?(status_output, "connected") && 
           not String.contains?(status_output, "No providers") &&
           not String.contains?(status_output, "disconnected") do
          {:ok, status_output}
        else
          {:error, :no_llm_connected}
        end
      {:error, reason} ->
        # If we can't connect to server, it's a different error
        if String.contains?(to_string(reason), "Cannot connect") do
          # Re-raise the server connection error
          {:error, reason}
        else
          {:error, :no_llm_connected}
        end
    end
  end
end
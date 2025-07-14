defmodule RubberDuck.Commands.Handlers.ConversationDebug do
  @moduledoc """
  Debug wrapper for conversation handler to trace execution flow
  """
  
  alias RubberDuck.Commands.Handlers.Conversation
  alias RubberDuck.Commands.Command
  require Logger
  
  def execute(%Command{subcommand: :send} = command) do
    Logger.info("[ConversationDebug] Starting conversation send execution")
    Logger.info("[ConversationDebug] Command: #{inspect(command, pretty: true)}")
    
    start_time = System.monotonic_time(:millisecond)
    
    # Wrap the execution to catch any issues
    result = try do
      # Step 1: Execute the command
      Logger.info("[ConversationDebug] Calling Conversation.execute...")
      result = Conversation.execute(command)
      
      end_time = System.monotonic_time(:millisecond)
      Logger.info("[ConversationDebug] Execution completed in #{end_time - start_time}ms")
      Logger.info("[ConversationDebug] Result: #{inspect(result, pretty: true)}")
      
      result
    catch
      kind, error ->
        end_time = System.monotonic_time(:millisecond)
        Logger.error("[ConversationDebug] Caught #{kind}: #{inspect(error)}")
        Logger.error("[ConversationDebug] Failed after #{end_time - start_time}ms")
        Logger.error("[ConversationDebug] Stacktrace: #{inspect(__STACKTRACE__, pretty: true)}")
        {:error, "Conversation execution failed: #{inspect(error)}"}
    end
    
    result
  end
  
  def execute(command) do
    # Pass through other commands
    Conversation.execute(command)
  end
end
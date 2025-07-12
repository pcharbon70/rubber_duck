defmodule RubberDuck.CLIClient.UnifiedIntegration do
  @moduledoc """
  Integration layer between CLI client and unified command system.
  
  This module provides a bridge between the CLI client's expectations and the
  unified command abstraction layer, handling format conversion and command
  execution through the unified system.
  """

  alias RubberDuck.Commands.{Parser, Processor, Context}

  @doc """
  Execute a command through the unified command system.
  
  ## Parameters
  - `args` - List of command line arguments (e.g., ["analyze", "mix.exs"])
  - `config` - CLI configuration map containing user context and formatting preferences
  
  ## Returns
  - `{:ok, formatted_result}` - On successful execution
  - `{:error, reason}` - On failure
  """
  def execute_command(args, config) when is_list(args) do
    # Determine the unified format based on CLI client format preference
    unified_format = map_cli_format_to_unified(Map.get(config, :format, :plain))
    
    with {:ok, context} <- build_context(config),
         {:ok, command} <- Parser.parse(args, :cli, context),
         # Override the command format with our mapped format
         command <- %{command | format: unified_format},
         {:ok, result} <- Processor.execute(command) do
      
      # The result should already be formatted by the unified system
      {:ok, result}
    else
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  @doc """
  Execute a streaming command through the unified command system.
  
  ## Parameters
  - `args` - List of command line arguments
  - `config` - CLI configuration map
  - `handler` - Function to handle streaming chunks
  
  ## Returns
  - `{:ok, %{request_id: id}}` - On successful start
  - `{:error, reason}` - On failure
  """
  def execute_streaming_command(args, config, handler) when is_list(args) and is_function(handler, 1) do
    # Determine the unified format based on CLI client format preference
    unified_format = map_cli_format_to_unified(Map.get(config, :format, :plain))
    
    with {:ok, context} <- build_context(config),
         {:ok, command} <- Parser.parse(args, :cli, context),
         # Override the command format with our mapped format
         command <- %{command | format: unified_format},
         {:ok, %{request_id: request_id}} <- Processor.execute_async(command) do
      
      # Start monitoring the async request and call handler with chunks
      start_stream_monitor(request_id, handler, config)
      
      {:ok, %{request_id: request_id}}
    else
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  @doc """
  Get the status of an async command execution.
  """
  def get_status(request_id) do
    Processor.get_status(request_id)
  end

  @doc """
  Cancel an async command execution.
  """
  def cancel(request_id) do
    Processor.cancel(request_id)
  end

  # Private functions

  defp build_context(config) do
    context_data = %{
      user_id: Map.get(config, :user_id, "cli_user"),
      project_id: Map.get(config, :project_id),
      conversation_id: Map.get(config, :conversation_id),
      session_id: Map.get(config, :session_id, generate_session_id()),
      permissions: Map.get(config, :permissions, [:read, :write, :execute]),
      metadata: Map.merge(
        %{client: "cli", interface: "unified"},
        Map.get(config, :metadata, %{})
      )
    }
    
    Context.new(context_data)
  end

  defp generate_session_id do
    "cli_session_#{System.system_time(:millisecond)}_#{:rand.uniform(1000)}"
  end

  defp map_cli_format_to_unified(format) do
    case format do
      :json -> :json
      :plain -> :text
      :table -> :table
      _ -> :text
    end
  end


  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp start_stream_monitor(request_id, handler, _config) do
    # Start a task to monitor the async request and call handler with results
    Task.start_link(fn ->
      monitor_async_request(request_id, handler, 0)
    end)
  end

  defp monitor_async_request(request_id, handler, attempts) when attempts < 60 do
    case Processor.get_status(request_id) do
      {:ok, %{status: :completed, result: result}} ->
        # Final result - already formatted by unified system
        handler.(result)
        
      {:ok, %{status: :failed, result: {:error, reason}}} ->
        # Error result
        handler.({:error, format_error(reason)})
        
      {:ok, %{status: status}} when status in [:pending, :running] ->
        # Still processing - send progress update and continue monitoring
        handler.({:progress, status})
        Process.sleep(500)
        monitor_async_request(request_id, handler, attempts + 1)
        
      {:error, reason} ->
        handler.({:error, format_error(reason)})
    end
  end

  defp monitor_async_request(_request_id, handler, _attempts) do
    # Timeout after 30 seconds
    handler.({:error, "Command execution timed out"})
  end
end
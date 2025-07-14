defmodule RubberDuck.Commands.Adapters.CLI do
  @moduledoc """
  CLI adapter for the unified command system.
  
  Provides a convenient interface for CLI applications to interact with
  the command processor, handling argument parsing and result formatting.
  """

  alias RubberDuck.Commands.{Parser, Processor, Context}

  @doc """
  Execute a CLI command with the given arguments and options.
  
  ## Parameters
  - `args` - List of command line arguments (e.g., ["analyze", "--path", "lib/"])
  - `config` - CLI configuration map containing user context
  
  ## Returns
  - `{:ok, formatted_result}` - On successful execution
  - `{:error, reason}` - On failure
  """
  def execute(args, config) when is_list(args) do
    with {:ok, context} <- build_context(config),
         {:ok, command} <- Parser.parse(args, :cli, context),
         {:ok, result} <- Processor.execute(command) do
      {:ok, result}
    end
  end

  @doc """
  Execute a CLI command asynchronously.
  
  ## Parameters
  - `args` - List of command line arguments
  - `config` - CLI configuration map containing user context
  
  ## Returns
  - `{:ok, %{request_id: id}}` - On successful start
  - `{:error, reason}` - On failure
  """
  def execute_async(args, config) when is_list(args) do
    with {:ok, context} <- build_context(config),
         {:ok, command} <- Parser.parse(args, :cli, context),
         {:ok, result} <- Processor.execute_async(command) do
      {:ok, result}
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

  @doc """
  Parse CLI arguments into a Command struct without executing.
  
  Useful for validation or inspection of commands before execution.
  """
  def parse(args, config) when is_list(args) do
    with {:ok, context} <- build_context(config),
         {:ok, command} <- Parser.parse(args, :cli, context) do
      {:ok, command}
    end
  end

  @doc """
  Convert legacy CLI command results to unified format.
  
  This helps with migration from the old CLI system.
  """
  def convert_legacy_result(command_name, result) do
    case result do
      {:ok, %{type: _type} = data} ->
        {:ok, data}
        
      {:ok, data} when is_map(data) ->
        {:ok, Map.put(data, :type, normalize_command_name(command_name))}
        
      {:ok, data} ->
        {:ok, %{
          type: normalize_command_name(command_name),
          result: data,
          timestamp: DateTime.utc_now()
        }}
        
      error ->
        error
    end
  end

  # Private functions

  defp build_context(config) do
    context_data = %{
      user_id: Map.get(config, :user_id, "cli_user"),
      project_id: Map.get(config, :project_id),
      conversation_id: Map.get(config, :conversation_id),
      session_id: Map.get(config, :session_id, generate_session_id()),
      permissions: Map.get(config, :permissions, [:read, :write, :execute]),
      metadata: Map.get(config, :metadata, %{})
    }
    
    Context.new(context_data)
  end

  defp generate_session_id do
    "cli_session_#{System.system_time(:millisecond)}_#{:rand.uniform(1000)}"
  end

  defp normalize_command_name(command_name) when is_atom(command_name) do
    to_string(command_name)
  end
  defp normalize_command_name(command_name) when is_binary(command_name) do
    command_name
  end
  defp normalize_command_name(_), do: "unknown"
end
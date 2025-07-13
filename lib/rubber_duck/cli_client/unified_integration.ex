defmodule RubberDuck.CLIClient.UnifiedIntegration do
  @moduledoc """
  Integration layer between CLI client and unified command system.
  
  This module provides a bridge between the CLI client's expectations and the
  unified command abstraction layer, handling format conversion and command
  execution through the unified system.
  """

  # alias RubberDuck.Commands.{Parser, Processor, Context}

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
    # For escript/CLI client, we need to send commands through WebSocket
    # The server will handle parsing and execution through the unified system
    ensure_client_started(config)
    
    # Parse command and params from args
    {command, params} = parse_command_args(args)
    
    # Add format to params
    params = Map.put(params, :format, config[:format] || :plain)
    
    
    
    # Send through WebSocket client
    case RubberDuck.CLIClient.Client.send_command(command, params) do
      {:ok, %{"status" => "ok", "response" => response}} -> 
        {:ok, format_response(response, config[:format] || :plain)}
      {:ok, %{"status" => "error", "error" => reason}} -> 
        {:error, format_error(reason)}
      {:ok, result} -> 
        {:ok, format_response(result, config[:format] || :plain)}
      {:error, reason} -> 
        {:error, format_error(reason)}
    end
  end
  
  defp ensure_client_started(config) do
    case Process.whereis(RubberDuck.CLIClient.Client) do
      nil ->
        server_url = config[:server_url] || RubberDuck.CLIClient.Auth.get_server_url()
        api_key = RubberDuck.CLIClient.Auth.get_api_key()
        
        if config[:verbose] do
          IO.puts("Connecting to server: #{server_url}")
          IO.puts("Using API key: #{String.slice(api_key || "", 0..7)}...")
        end
        
        case RubberDuck.CLIClient.Client.start_link(url: server_url, api_key: api_key) do
          {:ok, pid} ->
            if config[:verbose] do
              IO.puts("Client started with PID: #{inspect(pid)}")
            end
            # Explicitly connect
            case RubberDuck.CLIClient.Client.connect(server_url) do
              :ok ->
                if config[:verbose] do
                  IO.puts("Connection initiated")
                end
                # Wait for connection
                wait_for_connection(10)
              {:error, reason} ->
                IO.puts("Failed to connect: #{inspect(reason)}")
                raise "Failed to connect to server: #{inspect(reason)}"
            end
          {:error, reason} ->
            IO.puts("Failed to start client: #{inspect(reason)}")
            raise "Failed to start WebSocket client: #{inspect(reason)}"
        end
        
      _pid ->
        :ok
    end
  end
  
  defp wait_for_connection(0) do
    raise "Failed to connect to server"
  end
  
  defp wait_for_connection(attempts) do
    if RubberDuck.CLIClient.Client.connected?() do
      :ok
    else
      Process.sleep(500)
      wait_for_connection(attempts - 1)
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
  defp format_error(%{"reason" => reason}) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
  
  defp format_response(response, :plain) when is_binary(response), do: response
  defp format_response(%{"data" => data}, :plain), do: format_response(data, :plain)
  defp format_response(%{"message" => message, "type" => "llm_connection"}, :plain) do
    message
  end
  defp format_response(%{"providers" => providers} = data, :plain) do
    # Format LLM status output
    lines = ["LLM Provider Status:", ""]
    
    provider_lines = for provider <- providers do
      status_icon = if provider["status"] == "connected", do: "✓", else: "✗"
      "#{status_icon} #{provider["name"]}: #{provider["status"]} (#{provider["health"]})"
    end
    
    lines = lines ++ provider_lines
    
    if summary = data["summary"] do
      lines = lines ++ ["", "Summary: #{summary["connected"]}/#{summary["total"]} connected"]
    end
    
    Enum.join(lines, "\n")
  end
  defp format_response(response, :json) when is_map(response) or is_list(response) do
    Jason.encode!(response, pretty: true)
  end
  defp format_response(response, _format) when is_binary(response), do: response
  defp format_response(response, _format), do: inspect(response, pretty: true)
  
  defp parse_command_args([command | rest]) do
    # Extract the main command
    main_command = to_string(command)
    
    # Parse the rest of the args into params
    params = parse_remaining_args(rest, %{})
    
    {main_command, params}
  end
  
  defp parse_command_args([]), do: {"help", %{}}
  
  defp parse_remaining_args([], params), do: params
  
  defp parse_remaining_args([subcommand | rest], params) when is_binary(subcommand) or is_atom(subcommand) do
    # Check if this is a flag or a subcommand
    if String.starts_with?(to_string(subcommand), "--") do
      # Parse flag and its value
      parse_flag(subcommand, rest, params)
    else
      # It's a subcommand
      params = Map.put(params, :subcommand, to_string(subcommand))
      parse_remaining_args(rest, params)
    end
  end
  
  defp parse_remaining_args([arg | rest], params) do
    # Other arguments go into args list
    args = Map.get(params, :args, [])
    params = Map.put(params, :args, args ++ [to_string(arg)])
    parse_remaining_args(rest, params)
  end
  
  defp parse_flag(flag, [value | rest], params) do
    flag_name = String.trim_leading(flag, "--")
    params = Map.put(params, String.to_atom(flag_name), value)
    parse_remaining_args(rest, params)
  end
  
  defp parse_flag(flag, [], params) do
    # Boolean flag
    flag_name = String.trim_leading(flag, "--")
    Map.put(params, String.to_atom(flag_name), true)
  end

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
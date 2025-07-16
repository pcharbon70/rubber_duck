defmodule RubberDuck.MCP.Integration.WorkflowSteps do
  @moduledoc """
  Workflow step implementations for MCP integration.
  
  This module provides Reactor step types that enable workflows to
  interact with MCP tools and resources.
  """
  
  defmodule MCPToolStep do
    @moduledoc """
    A workflow step that executes an MCP tool.
    """
    
    use Reactor.Step
    
    alias RubberDuck.MCP.{Client, Registry}
    
    @impl true
    def run(arguments, context, options) do
      tool_name = arguments[:tool_name] || options[:tool_name]
      tool_params = arguments[:params] || %{}
      client_name = options[:client] || :default
      
      with {:ok, client} <- get_client(client_name),
           {:ok, tool} <- Client.get_tool(client, tool_name),
           {:ok, result} <- Client.call_tool(client, tool_name, tool_params) do
        
        # Record metrics
        Registry.record_metric(tool_name, {:execution, :success, result.duration_ms}, nil)
        
        {:ok, result}
      else
        {:error, reason} = error ->
          Registry.record_metric(tool_name, {:execution, :failure, reason}, nil)
          error
      end
    end
    
    @impl true
    def compensate(reason, arguments, context, options) do
      # Compensation logic for MCP tool failures
      tool_name = arguments[:tool_name] || options[:tool_name]
      
      # Log compensation
      Logger.warn("Compensating for failed MCP tool: #{tool_name}, reason: #{inspect(reason)}")
      
      # Attempt cleanup if tool supports it
      if cleanup_params = options[:cleanup] do
        try_cleanup(tool_name, cleanup_params, options)
      end
      
      :ok
    end
    
    defp get_client(client_name) do
      case RubberDuck.MCP.ClientSupervisor.get_client(client_name) do
        {:ok, client} -> {:ok, client}
        {:error, :not_found} -> {:error, "MCP client not found: #{client_name}"}
      end
    end
    
    defp try_cleanup(tool_name, cleanup_params, options) do
      client_name = options[:client] || :default
      
      with {:ok, client} <- get_client(client_name),
           {:ok, _} <- Client.call_tool(client, "#{tool_name}_cleanup", cleanup_params) do
        :ok
      else
        _ -> :ok  # Ignore cleanup failures
      end
    end
  end
  
  defmodule MCPResourceStep do
    @moduledoc """
    A workflow step that reads an MCP resource.
    """
    
    use Reactor.Step
    
    alias RubberDuck.MCP.Client
    
    @impl true
    def run(arguments, context, options) do
      resource_uri = arguments[:resource_uri] || options[:resource_uri]
      resource_params = arguments[:params] || %{}
      client_name = options[:client] || :default
      
      with {:ok, client} <- get_client(client_name),
           {:ok, resource} <- Client.read_resource(client, resource_uri, resource_params) do
        {:ok, resource}
      else
        error -> error
      end
    end
    
    defp get_client(client_name) do
      case RubberDuck.MCP.ClientSupervisor.get_client(client_name) do
        {:ok, client} -> {:ok, client}
        {:error, :not_found} -> {:error, "MCP client not found: #{client_name}"}
      end
    end
  end
  
  defmodule MCPCompositionStep do
    @moduledoc """
    A workflow step that executes an MCP tool composition.
    """
    
    use Reactor.Step
    
    alias RubberDuck.MCP.Registry.Composition
    
    @impl true
    def run(arguments, context, options) do
      composition_id = arguments[:composition_id] || options[:composition_id]
      input_data = arguments[:input] || %{}
      
      with {:ok, composition} <- Registry.get_composition(composition_id),
           {:ok, result} <- Composition.execute(composition, input_data) do
        {:ok, result}
      else
        error -> error
      end
    end
    
    @impl true
    def compensate(reason, arguments, context, options) do
      # Compensation for composition failures
      composition_id = arguments[:composition_id] || options[:composition_id]
      
      Logger.warn("Compensating for failed MCP composition: #{composition_id}")
      
      # Attempt to cancel any running composition
      case Registry.get_composition(composition_id) do
        {:ok, composition} ->
          Composition.cancel(composition)
        _ ->
          :ok
      end
      
      :ok
    end
  end
  
  defmodule MCPStreamingStep do
    @moduledoc """
    A workflow step that handles streaming MCP tool execution.
    """
    
    use Reactor.Step
    
    alias RubberDuck.MCP.Client
    
    @impl true
    def run(arguments, context, options) do
      tool_name = arguments[:tool_name] || options[:tool_name]
      tool_params = arguments[:params] || %{}
      client_name = options[:client] || :default
      callback = options[:stream_callback]
      
      with {:ok, client} <- get_client(client_name) do
        # Set up streaming callback
        stream_callback = fn chunk ->
          if callback, do: callback.(chunk)
          # Store chunk in context for later processing
          Reactor.Context.put_private(context, :stream_chunks, 
            [chunk | Reactor.Context.get_private(context, :stream_chunks, [])])
        end
        
        case Client.stream_tool(client, tool_name, tool_params, stream_callback) do
          {:ok, final_result} ->
            # Combine streaming chunks with final result
            chunks = Reactor.Context.get_private(context, :stream_chunks, [])
            
            {:ok, %{
              final_result: final_result,
              stream_chunks: Enum.reverse(chunks),
              total_chunks: length(chunks)
            }}
            
          error -> error
        end
      end
    end
    
    defp get_client(client_name) do
      case RubberDuck.MCP.ClientSupervisor.get_client(client_name) do
        {:ok, client} -> {:ok, client}
        {:error, :not_found} -> {:error, "MCP client not found: #{client_name}"}
      end
    end
  end
end
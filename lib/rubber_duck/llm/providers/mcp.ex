defmodule RubberDuck.LLM.Providers.MCP do
  @moduledoc """
  MCP (Model Context Protocol) provider adapter for RubberDuck.
  
  This provider enables RubberDuck to interact with language models through
  MCP-compatible clients, bridging the gap between RubberDuck's internal
  LLM abstractions and external MCP servers.
  
  Features:
  - Automatic tool discovery from MCP servers
  - Resource access integration
  - Prompt template utilization
  - Streaming response support
  - Error handling and fallback
  """
  
  @behaviour RubberDuck.LLM.Provider
  
  alias RubberDuck.MCP.Client
  alias RubberDuck.MCP.Registry
  alias RubberDuck.LLM.{Request, Response, Usage}
  
  require Logger
  
  @impl true
  def execute(request, config) do
    with {:ok, client} <- get_mcp_client(config),
         {:ok, mcp_request} <- transform_request(request, config),
         {:ok, mcp_response} <- Client.completion(client, mcp_request) do
      
      # Record metrics
      record_execution_metrics(config, mcp_response)
      
      # Transform response
      transform_response(mcp_response, config)
    else
      {:error, reason} = error ->
        Logger.error("MCP provider execution failed: #{inspect(reason)}")
        error
    end
  end
  
  @impl true
  def stream_completion(request, config, callback) do
    with {:ok, client} <- get_mcp_client(config),
         {:ok, mcp_request} <- transform_request(request, config, streaming: true) do
      
      # Create streaming callback wrapper
      wrapped_callback = fn chunk ->
        case transform_stream_chunk(chunk, config) do
          {:ok, response_chunk} -> callback.(response_chunk)
          {:error, reason} -> 
            Logger.warn("Failed to transform stream chunk: #{inspect(reason)}")
            :error
        end
      end
      
      Client.stream_completion(client, mcp_request, wrapped_callback)
    else
      {:error, reason} = error ->
        Logger.error("MCP stream completion failed: #{inspect(reason)}")
        error
    end
  end
  
  @impl true
  def validate_config(config) do
    required_fields = [:mcp_client, :models]
    
    case validate_required_fields(config, required_fields) do
      :ok -> validate_mcp_config(config)
      error -> error
    end
  end
  
  @impl true
  def supports_feature?(feature) do
    case feature do
      :streaming -> true
      :tools -> true
      :vision -> check_vision_support()
      :function_calling -> true
      :system_messages -> true
      _ -> false
    end
  end
  
  @impl true
  def count_tokens(text, config) do
    # Use MCP client for token counting if available
    with {:ok, client} <- get_mcp_client(config),
         {:ok, count} <- Client.count_tokens(client, text) do
      {:ok, count}
    else
      _ ->
        # Fallback to simple estimation
        word_count = text |> String.split() |> length()
        {:ok, round(word_count * 1.3)}
    end
  end
  
  @impl true
  def health_check(config) do
    with {:ok, client} <- get_mcp_client(config),
         {:ok, _status} <- Client.health_check(client) do
      {:ok, %{status: :healthy, provider: :mcp}}
    else
      {:error, reason} ->
        {:error, %{status: :unhealthy, provider: :mcp, reason: reason}}
    end
  end
  
  @impl true
  def connect(config) do
    case get_or_create_mcp_client(config) do
      {:ok, client} ->
        # Store client reference in config
        {:ok, Map.put(config, :_client, client)}
      error ->
        error
    end
  end
  
  @impl true
  def disconnect(config, _reason) do
    case Map.get(config, :_client) do
      nil -> :ok
      client -> Client.disconnect(client)
    end
  end
  
  # Private functions
  
  defp get_mcp_client(config) do
    case Map.get(config, :_client) do
      nil -> get_or_create_mcp_client(config)
      client -> {:ok, client}
    end
  end
  
  defp get_or_create_mcp_client(config) do
    client_name = config.mcp_client
    
    case RubberDuck.MCP.ClientSupervisor.get_client(client_name) do
      {:ok, client} -> {:ok, client}
      {:error, :not_found} -> create_mcp_client(config)
    end
  end
  
  defp create_mcp_client(config) do
    client_config = Map.merge(
      %{
        name: config.mcp_client,
        transport: config.mcp_config.transport,
        capabilities: [:tools, :resources, :prompts]
      },
      config.mcp_config
    )
    
    RubberDuck.MCP.ClientSupervisor.start_client(client_config)
  end
  
  defp transform_request(request, config, opts \\ []) do
    mcp_request = %{
      model: request.model,
      messages: transform_messages(request.messages),
      temperature: request.options.temperature,
      max_tokens: request.options.max_tokens,
      stream: Keyword.get(opts, :streaming, false)
    }
    
    # Add tools if available
    mcp_request = add_available_tools(mcp_request, config)
    
    # Add resources if requested
    mcp_request = add_available_resources(mcp_request, config, request)
    
    {:ok, mcp_request}
  end
  
  defp transform_messages(messages) do
    Enum.map(messages, fn message ->
      %{
        role: message.role,
        content: message.content,
        # Transform tool calls if present
        tool_calls: transform_tool_calls(message.tool_calls),
        # Transform tool results if present
        tool_call_id: message.tool_call_id
      }
    end)
  end
  
  defp transform_tool_calls(nil), do: nil
  defp transform_tool_calls(tool_calls) do
    Enum.map(tool_calls, fn call ->
      %{
        id: call.id,
        type: "function",
        function: %{
          name: call.name,
          arguments: Jason.encode!(call.arguments)
        }
      }
    end)
  end
  
  defp add_available_tools(request, config) do
    with {:ok, client} <- get_mcp_client(config),
         {:ok, tools} <- Client.list_tools(client) do
      
      # Transform MCP tools to OpenAI format
      transformed_tools = Enum.map(tools, fn tool ->
        %{
          type: "function",
          function: %{
            name: tool.name,
            description: tool.description,
            parameters: tool.input_schema
          }
        }
      end)
      
      Map.put(request, :tools, transformed_tools)
    else
      _ -> request
    end
  end
  
  defp add_available_resources(request, config, original_request) do
    # Check if request mentions resources
    if mentions_resources?(original_request) do
      with {:ok, client} <- get_mcp_client(config),
           {:ok, resources} <- Client.list_resources(client) do
        
        # Add resource information to system message
        resource_info = format_resource_info(resources)
        add_system_message(request, resource_info)
      else
        _ -> request
      end
    else
      request
    end
  end
  
  defp mentions_resources?(request) do
    # Simple heuristic to detect resource requests
    content = request.messages
    |> Enum.map(& &1.content)
    |> Enum.join(" ")
    |> String.downcase()
    
    String.contains?(content, "file") or
    String.contains?(content, "document") or
    String.contains?(content, "resource")
  end
  
  defp format_resource_info(resources) do
    resource_list = Enum.map(resources, fn resource ->
      "- #{resource.name}: #{resource.description}"
    end)
    |> Enum.join("\n")
    
    """
    Available resources:
    #{resource_list}
    
    You can access these resources by using the appropriate tools.
    """
  end
  
  defp add_system_message(request, content) do
    system_message = %{
      role: "system",
      content: content
    }
    
    Map.update(request, :messages, [system_message], fn messages ->
      [system_message | messages]
    end)
  end
  
  defp transform_response(mcp_response, config) do
    {:ok, %Response{
      id: mcp_response["id"] || generate_id(),
      model: mcp_response["model"] || config.models |> List.first(),
      provider: :mcp,
      choices: transform_choices(mcp_response["choices"] || []),
      usage: transform_usage(mcp_response["usage"]),
      created: DateTime.utc_now()
    }}
  end
  
  defp transform_choices(choices) do
    Enum.map(choices, fn choice ->
      %{
        message: transform_choice_message(choice["message"]),
        finish_reason: choice["finish_reason"],
        index: choice["index"] || 0
      }
    end)
  end
  
  defp transform_choice_message(message) do
    %{
      role: message["role"],
      content: message["content"],
      tool_calls: transform_response_tool_calls(message["tool_calls"])
    }
  end
  
  defp transform_response_tool_calls(nil), do: nil
  defp transform_response_tool_calls(tool_calls) do
    Enum.map(tool_calls, fn call ->
      %{
        id: call["id"],
        type: call["type"],
        name: call["function"]["name"],
        arguments: Jason.decode!(call["function"]["arguments"])
      }
    end)
  end
  
  defp transform_usage(nil), do: %Usage{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}
  defp transform_usage(usage) do
    %Usage{
      prompt_tokens: usage["prompt_tokens"] || 0,
      completion_tokens: usage["completion_tokens"] || 0,
      total_tokens: usage["total_tokens"] || 0
    }
  end
  
  defp transform_stream_chunk(chunk, config) do
    # Transform MCP stream chunk to RubberDuck format
    case chunk do
      %{"choices" => choices} ->
        transformed_choices = Enum.map(choices, fn choice ->
          %{
            delta: %{
              role: choice["delta"]["role"],
              content: choice["delta"]["content"],
              tool_calls: transform_response_tool_calls(choice["delta"]["tool_calls"])
            },
            finish_reason: choice["finish_reason"],
            index: choice["index"] || 0
          }
        end)
        
        {:ok, %Response{
          id: chunk["id"] || generate_id(),
          model: chunk["model"] || config.models |> List.first(),
          provider: :mcp,
          choices: transformed_choices,
          usage: transform_usage(chunk["usage"]),
          created: DateTime.utc_now()
        }}
        
      _ ->
        {:error, :invalid_chunk_format}
    end
  end
  
  defp validate_required_fields(config, required_fields) do
    missing = Enum.filter(required_fields, fn field ->
      not Map.has_key?(config, field) or is_nil(config[field])
    end)
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required_fields, missing}}
    end
  end
  
  defp validate_mcp_config(config) do
    mcp_config = config.mcp_config
    
    cond do
      not is_map(mcp_config) ->
        {:error, :invalid_mcp_config}
        
      not Map.has_key?(mcp_config, :transport) ->
        {:error, :missing_transport_config}
        
      not is_list(config.models) or Enum.empty?(config.models) ->
        {:error, :invalid_models_config}
        
      true ->
        :ok
    end
  end
  
  defp check_vision_support do
    # Check if any registered MCP clients support vision
    # This is a simplified check
    false
  end
  
  defp record_execution_metrics(config, response) do
    # Record metrics with the registry if available
    if Registry.Registry.started?() do
      client_name = config.mcp_client
      tokens = response["usage"]["total_tokens"] || 0
      
      Registry.record_metric(client_name, {:llm_completion, tokens}, nil)
    end
  end
  
  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64()
  end
end
defmodule RubberDuck.Tool.Streaming do
  @moduledoc """
  Provides streaming capabilities for tool execution results.
  
  Features:
  - Server-sent events (SSE) for web clients
  - WebSocket streaming for real-time updates
  - Chunked response handling for large outputs
  - Progress tracking and incremental results
  """
  
  alias Phoenix.PubSub
  
  require Logger
  
  @chunk_size 4096  # 4KB chunks
  
  @doc """
  Streams tool execution results to a client.
  
  Supports multiple streaming protocols based on client capabilities.
  """
  def stream_result(request_id, result, opts \\ []) do
    protocol = Keyword.get(opts, :protocol, :sse)
    
    case protocol do
      :sse -> stream_as_sse(request_id, result, opts)
      :websocket -> stream_via_websocket(request_id, result, opts)
      :chunked -> stream_as_chunks(request_id, result, opts)
      _ -> {:error, :unsupported_protocol}
    end
  end
  
  @doc """
  Creates a streaming adapter for progressive results.
  """
  def create_streaming_adapter(request_id, opts \\ []) do
    %{
      request_id: request_id,
      buffer: [],
      chunk_size: Keyword.get(opts, :chunk_size, @chunk_size),
      format: Keyword.get(opts, :format, :json),
      started_at: System.monotonic_time(:millisecond),
      bytes_sent: 0,
      chunks_sent: 0
    }
  end
  
  @doc """
  Adds data to the streaming buffer and flushes if needed.
  """
  def stream_data(adapter, data) do
    new_buffer = adapter.buffer ++ [data]
    buffer_size = IO.iodata_length(new_buffer)
    
    if buffer_size >= adapter.chunk_size do
      flush_buffer(adapter, new_buffer)
    else
      {:ok, %{adapter | buffer: new_buffer}}
    end
  end
  
  @doc """
  Flushes any remaining data in the buffer.
  """
  def flush_stream(adapter) do
    if adapter.buffer != [] do
      flush_buffer(adapter, adapter.buffer)
    else
      {:ok, adapter}
    end
  end
  
  @doc """
  Subscribes to streaming updates for a request.
  """
  def subscribe_to_stream(request_id) do
    PubSub.subscribe(RubberDuck.PubSub, "tool_stream:#{request_id}")
  end
  
  @doc """
  Broadcasts streaming data to subscribers.
  """
  def broadcast_stream_data(request_id, data, metadata \\ %{}) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "tool_stream:#{request_id}",
      {:stream_data, %{
        request_id: request_id,
        data: data,
        metadata: metadata,
        timestamp: DateTime.utc_now()
      }}
    )
  end
  
  # Private functions
  
  defp stream_as_sse(request_id, result, opts) do
    # Format result as Server-Sent Events
    conn = Keyword.get(opts, :conn)
    
    if conn do
      # Send SSE headers
      conn = conn
      |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.send_chunked(200)
      
      # Stream the result
      case result do
        data when is_binary(data) ->
          # Stream in chunks
          stream_binary_as_sse(conn, request_id, data)
        
        data when is_list(data) ->
          # Stream list items
          stream_list_as_sse(conn, request_id, data)
        
        data ->
          # Stream as single event
          send_sse_event(conn, request_id, "result", data)
      end
      
      # Send completion event
      send_sse_event(conn, request_id, "complete", %{status: "success"})
      
      {:ok, conn}
    else
      {:error, :no_connection}
    end
  end
  
  defp stream_via_websocket(request_id, result, _opts) do
    # WebSocket streaming is handled by Phoenix Channels
    # This broadcasts to the appropriate channel
    
    case result do
      data when is_binary(data) ->
        # Stream in chunks
        chunks = chunk_binary(data, @chunk_size)
        
        Enum.each(chunks, fn chunk ->
          broadcast_stream_data(request_id, %{
            type: "chunk",
            data: Base.encode64(chunk),
            encoding: "base64"
          })
        end)
      
      data when is_list(data) ->
        # Stream list items
        Enum.each(data, fn item ->
          broadcast_stream_data(request_id, %{
            type: "item",
            data: item
          })
        end)
      
      data ->
        # Stream as single message
        broadcast_stream_data(request_id, %{
          type: "result",
          data: data
        })
    end
    
    # Broadcast completion
    broadcast_stream_data(request_id, %{
      type: "complete",
      status: "success"
    })
    
    :ok
  end
  
  defp stream_as_chunks(_request_id, result, opts) do
    # HTTP chunked transfer encoding
    conn = Keyword.get(opts, :conn)
    
    if conn do
      conn = conn
      |> Plug.Conn.put_resp_header("transfer-encoding", "chunked")
      |> Plug.Conn.send_chunked(200)
      
      case result do
        data when is_binary(data) ->
          chunks = chunk_binary(data, @chunk_size)
          
          Enum.reduce_while(chunks, {:ok, conn}, fn chunk, {:ok, conn} ->
            case Plug.Conn.chunk(conn, chunk) do
              {:ok, conn} -> {:cont, {:ok, conn}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)
        
        data ->
          encoded = Jason.encode!(data)
          Plug.Conn.chunk(conn, encoded)
      end
    else
      {:error, :no_connection}
    end
  end
  
  defp flush_buffer(adapter, buffer) do
    data = IO.iodata_to_binary(buffer)
    size = byte_size(data)
    
    # Broadcast the chunk
    broadcast_stream_data(adapter.request_id, %{
      type: "buffer_flush",
      data: data,
      chunk_number: adapter.chunks_sent + 1,
      byte_size: size
    })
    
    # Update adapter state
    {:ok, %{adapter |
      buffer: [],
      bytes_sent: adapter.bytes_sent + size,
      chunks_sent: adapter.chunks_sent + 1
    }}
  end
  
  defp send_sse_event(conn, request_id, event_type, data) do
    formatted = format_sse_event(request_id, event_type, data)
    
    case Plug.Conn.chunk(conn, formatted) do
      {:ok, conn} -> conn
      {:error, _reason} -> conn
    end
  end
  
  defp format_sse_event(request_id, event_type, data) do
    encoded_data = case data do
      d when is_binary(d) -> d
      d -> Jason.encode!(d)
    end
    
    """
    id: #{request_id}_#{System.unique_integer([:positive])}
    event: #{event_type}
    data: #{encoded_data}
    
    """
  end
  
  defp stream_binary_as_sse(conn, request_id, binary) do
    chunks = chunk_binary(binary, @chunk_size)
    
    Enum.reduce(chunks, {conn, 0}, fn chunk, {conn, index} ->
      conn = send_sse_event(conn, request_id, "chunk", %{
        index: index,
        data: Base.encode64(chunk),
        encoding: "base64",
        size: byte_size(chunk)
      })
      
      {conn, index + 1}
    end)
    |> elem(0)
  end
  
  defp stream_list_as_sse(conn, request_id, list) do
    Enum.reduce(list, {conn, 0}, fn item, {conn, index} ->
      conn = send_sse_event(conn, request_id, "item", %{
        index: index,
        data: item
      })
      
      {conn, index + 1}
    end)
    |> elem(0)
  end
  
  defp chunk_binary(binary, chunk_size) do
    chunk_binary(binary, chunk_size, [])
  end
  
  defp chunk_binary(<<>>, _chunk_size, acc), do: Enum.reverse(acc)
  defp chunk_binary(binary, chunk_size, acc) do
    case binary do
      <<chunk::binary-size(chunk_size), rest::binary>> ->
        chunk_binary(rest, chunk_size, [chunk | acc])
      
      chunk ->
        Enum.reverse([chunk | acc])
    end
  end
end
defmodule RubberDuck.LLMAbstraction.HTTPClient do
  @moduledoc """
  HTTP client for making requests to LLM provider APIs.
  
  This module provides a standardized HTTP client with built-in error handling,
  retries, timeouts, and rate limiting for communicating with external LLM services.
  """

  require Logger

  @type request_opts :: [
    method: :get | :post | :put | :delete,
    headers: [{String.t(), String.t()}],
    body: String.t() | map(),
    timeout: pos_integer(),
    recv_timeout: pos_integer(),
    max_retries: non_neg_integer(),
    retry_delay: pos_integer(),
    retry_backoff: float()
  ]

  @type response :: %{
    status: pos_integer(),
    headers: [{String.t(), String.t()}],
    body: String.t()
  }

  @default_timeout 30_000
  @default_recv_timeout 60_000
  @default_max_retries 3
  @default_retry_delay 1000
  @default_retry_backoff 2.0

  @doc """
  Make an HTTP request to the specified URL.
  """
  @spec request(String.t(), request_opts()) :: {:ok, response()} | {:error, term()}
  def request(url, opts \\ []) do
    method = Keyword.get(opts, :method, :post)
    headers = prepare_headers(Keyword.get(opts, :headers, []))
    body = prepare_body(Keyword.get(opts, :body, ""))
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    recv_timeout = Keyword.get(opts, :recv_timeout, @default_recv_timeout)
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)

    http_opts = [
      timeout: timeout,
      recv_timeout: recv_timeout,
      ssl: [
        verify: :verify_peer,
        cacerts: :certifi.cacerts(),
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    request_with_retry(method, url, headers, body, http_opts, max_retries, opts)
  end

  @doc """
  Make a GET request.
  """
  @spec get(String.t(), request_opts()) :: {:ok, response()} | {:error, term()}
  def get(url, opts \\ []) do
    request(url, Keyword.put(opts, :method, :get))
  end

  @doc """
  Make a POST request.
  """
  @spec post(String.t(), String.t() | map(), request_opts()) :: {:ok, response()} | {:error, term()}
  def post(url, body, opts \\ []) do
    request(url, Keyword.merge(opts, [method: :post, body: body]))
  end

  @doc """
  Make a PUT request.
  """
  @spec put(String.t(), String.t() | map(), request_opts()) :: {:ok, response()} | {:error, term()}
  def put(url, body, opts \\ []) do
    request(url, Keyword.merge(opts, [method: :put, body: body]))
  end

  @doc """
  Make a DELETE request.
  """
  @spec delete(String.t(), request_opts()) :: {:ok, response()} | {:error, term()}
  def delete(url, opts \\ []) do
    request(url, Keyword.put(opts, :method, :delete))
  end

  @doc """
  Make a streaming HTTP request for server-sent events.
  """
  @spec stream_request(String.t(), request_opts()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_request(url, opts \\ []) do
    method = Keyword.get(opts, :method, :post)
    headers = prepare_headers(Keyword.get(opts, :headers, []))
    body = prepare_body(Keyword.get(opts, :body, ""))
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Add stream-specific headers
    stream_headers = [
      {"Accept", "text/event-stream"},
      {"Cache-Control", "no-cache"}
      | headers
    ]

    http_opts = [
      timeout: timeout,
      recv_timeout: :infinity,
      stream: :self,
      ssl: [
        verify: :verify_peer,
        cacerts: :certifi.cacerts(),
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    case :httpc.request(method, {to_charlist(url), stream_headers, 'application/json', body}, http_opts, []) do
      {:ok, request_id} ->
        {:ok, create_stream(request_id)}
      
      {:error, reason} ->
        Logger.error("Stream request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private Functions

  defp request_with_retry(method, url, headers, body, http_opts, retries_left, opts) do
    case make_http_request(method, url, headers, body, http_opts) do
      {:ok, response} ->
        {:ok, response}
      
      {:error, reason} when retries_left > 0 ->
        Logger.warning("HTTP request failed (#{retries_left} retries left): #{inspect(reason)}")
        
        delay = calculate_retry_delay(opts, @default_max_retries - retries_left)
        :timer.sleep(delay)
        
        request_with_retry(method, url, headers, body, http_opts, retries_left - 1, opts)
      
      {:error, reason} ->
        Logger.error("HTTP request failed after all retries: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp make_http_request(method, url, headers, body, http_opts) do
    request = case method do
      :get -> {to_charlist(url), headers}
      :delete -> {to_charlist(url), headers}
      _ -> {to_charlist(url), headers, 'application/json', body}
    end

    case :httpc.request(method, request, http_opts, []) do
      {:ok, {{_version, status, _reason_phrase}, response_headers, response_body}} ->
        {:ok, %{
          status: status,
          headers: normalize_headers(response_headers),
          body: to_string(response_body)
        }}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_headers(headers) do
    default_headers = [
      {"User-Agent", "RubberDuck/1.0"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    # Convert headers to charlist format and merge with defaults
    user_headers = Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)
    default_headers_cl = Enum.map(default_headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    # User headers override defaults
    Enum.reduce(user_headers, default_headers_cl, fn {key, value}, acc ->
      List.keystore(acc, key, 0, {key, value})
    end)
  end

  defp prepare_body(body) when is_map(body) do
    case Jason.encode(body) do
      {:ok, json} -> json
      {:error, reason} ->
        Logger.error("Failed to encode request body: #{inspect(reason)}")
        "{}"
    end
  end

  defp prepare_body(body) when is_binary(body) do
    body
  end

  defp prepare_body(_) do
    ""
  end

  defp normalize_headers(headers) do
    Enum.map(headers, fn {key, value} ->
      {to_string(key), to_string(value)}
    end)
  end

  defp calculate_retry_delay(opts, attempt) do
    base_delay = Keyword.get(opts, :retry_delay, @default_retry_delay)
    backoff = Keyword.get(opts, :retry_backoff, @default_retry_backoff)
    
    round(base_delay * :math.pow(backoff, attempt))
  end

  defp create_stream(request_id) do
    Stream.unfold(request_id, fn
      nil -> nil
      id ->
        receive do
          {:http, {id, :stream_start, _headers}} ->
            {"", id}
          
          {:http, {id, :stream, data}} ->
            {to_string(data), id}
          
          {:http, {id, :stream_end, _headers}} ->
            nil
          
          {:http, {id, {:error, reason}}} ->
            Logger.error("Stream error: #{inspect(reason)}")
            nil
        after
          30_000 ->
            Logger.warning("Stream timeout")
            nil
        end
    end)
  end

  @doc """
  Parse Server-Sent Events from a stream.
  """
  def parse_sse_stream(stream) do
    stream
    |> Stream.transform("", &parse_sse_chunk/2)
    |> Stream.filter(&(&1 != nil))
  end

  defp parse_sse_chunk(chunk, buffer) do
    # Combine buffer with new chunk
    full_data = buffer <> chunk
    
    # Split on double newlines (event boundaries)
    parts = String.split(full_data, "\n\n")
    
    # Last part might be incomplete, keep as buffer
    {complete_events, new_buffer} = case parts do
      [] -> {[], ""}
      [single] -> {[], single}
      parts -> 
        {Enum.slice(parts, 0..-2), List.last(parts)}
    end
    
    # Parse complete events
    events = Enum.map(complete_events, &parse_sse_event/1)
    
    {events, new_buffer}
  end

  defp parse_sse_event(event_data) do
    lines = String.split(event_data, "\n")
    
    Enum.reduce(lines, %{}, fn line, acc ->
      case String.split(line, ": ", parts: 2) do
        ["data", data] -> 
          existing_data = Map.get(acc, :data, "")
          Map.put(acc, :data, existing_data <> data <> "\n")
        
        ["event", event] -> 
          Map.put(acc, :event, event)
        
        ["id", id] -> 
          Map.put(acc, :id, id)
        
        ["retry", retry] -> 
          case Integer.parse(retry) do
            {num, _} -> Map.put(acc, :retry, num)
            _ -> acc
          end
        
        _ -> 
          acc
      end
    end)
    |> case do
      %{data: data} = event -> 
        # Remove trailing newline from data
        %{event | data: String.trim_trailing(data, "\n")}
      event -> 
        event
    end
  end

  @doc """
  Add authorization header for Bearer token authentication.
  """
  def add_bearer_auth(headers, token) when is_binary(token) do
    [{"Authorization", "Bearer #{token}"} | headers]
  end

  @doc """
  Add authorization header for API key authentication.
  """
  def add_api_key_auth(headers, key, header_name \\ "X-API-Key") do
    [{header_name, key} | headers]
  end

  @doc """
  Check if response indicates a rate limit error.
  """
  def rate_limited?(%{status: 429}), do: true
  def rate_limited?(%{status: 503}), do: true
  def rate_limited?(_), do: false

  @doc """
  Check if response indicates a successful request.
  """
  def success?(%{status: status}) when status >= 200 and status < 300, do: true
  def success?(_), do: false

  @doc """
  Check if response indicates a client error.
  """
  def client_error?(%{status: status}) when status >= 400 and status < 500, do: true
  def client_error?(_), do: false

  @doc """
  Check if response indicates a server error.
  """
  def server_error?(%{status: status}) when status >= 500, do: true
  def server_error?(_), do: false

  @doc """
  Extract retry-after header value (in seconds).
  """
  def get_retry_after(%{headers: headers}) do
    case Enum.find(headers, fn {k, _v} -> String.downcase(k) == "retry-after" end) do
      {_key, value} ->
        case Integer.parse(value) do
          {seconds, _} -> seconds
          _ -> nil
        end
      _ -> nil
    end
  end

  @doc """
  Parse JSON response body.
  """
  def parse_json_response(%{body: body}) do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  def parse_json_response({:error, reason}) do
    {:error, reason}
  end
end
defmodule RubberDuck.MCP.Protocol do
  @moduledoc """
  JSON-RPC 2.0 protocol implementation for MCP.

  Handles parsing, validation, and building of JSON-RPC messages according
  to the MCP specification. All messages follow the JSON-RPC 2.0 format.

  ## Message Types

  - **Request**: Has id, method, and optional params
  - **Response**: Has id and either result or error
  - **Notification**: Has method and optional params, but no id

  ## Error Codes

  Standard JSON-RPC 2.0 error codes:
  - -32700: Parse error
  - -32600: Invalid request
  - -32601: Method not found
  - -32602: Invalid params
  - -32603: Internal error

  MCP-specific error codes:
  - -32001: Resource not found
  - -32002: Resource access denied
  - -32003: Tool execution failed
  """

  @type json_rpc_id :: String.t() | integer() | nil

  @type request :: %{
          jsonrpc: String.t(),
          id: json_rpc_id(),
          method: String.t(),
          params: map() | list() | nil
        }

  @type response :: %{
          jsonrpc: String.t(),
          id: json_rpc_id(),
          result: term()
        }

  @type error_response :: %{
          jsonrpc: String.t(),
          id: json_rpc_id(),
          error: %{
            code: integer(),
            message: String.t(),
            data: term() | nil
          }
        }

  @type notification :: %{
          jsonrpc: String.t(),
          method: String.t(),
          params: map() | list() | nil
        }

  @type message :: request() | response() | error_response() | notification()

  # Error codes
  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @invalid_params -32602
  @internal_error -32603

  # MCP-specific error codes
  @resource_not_found -32001
  @resource_access_denied -32002
  @tool_execution_failed -32003

  @doc """
  Parses a JSON-RPC message from a JSON string or map.

  Returns `{:ok, message}` or `{:error, reason}`.
  """
  @spec parse_message(String.t() | map()) :: {:ok, message()} | {:error, String.t()}
  def parse_message(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, decoded} -> parse_message(decoded)
      {:error, _} -> {:error, "Invalid JSON"}
    end
  end

  def parse_message(message) when is_map(message) do
    with :ok <- validate_jsonrpc_version(message),
         {:ok, type} <- determine_message_type(message),
         :ok <- validate_message_structure(type, message) do
      {:ok, message}
    end
  end

  def parse_message(_), do: {:error, "Message must be a JSON string or map"}

  @doc """
  Builds a JSON-RPC request.
  """
  @spec build_request(json_rpc_id(), String.t(), map() | list() | nil) :: map()
  def build_request(id, method, params \\ nil) do
    base = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => method
    }

    if params do
      Map.put(base, "params", params)
    else
      base
    end
  end

  @doc """
  Builds a JSON-RPC response.
  """
  @spec build_response(json_rpc_id(), term()) :: map()
  def build_response(id, result) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  @doc """
  Builds a JSON-RPC error response.
  """
  @spec build_error(json_rpc_id(), atom() | integer(), String.t(), term() | nil) :: map()
  def build_error(id, code, message, data \\ nil)

  def build_error(id, code, message, data) when is_atom(code) do
    build_error(id, error_code(code), message, data)
  end

  def build_error(id, code, message, data) when is_integer(code) do
    error = %{
      "code" => code,
      "message" => message
    }

    error = if data, do: Map.put(error, "data", data), else: error

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => error
    }
  end

  @doc """
  Builds a JSON-RPC notification.
  """
  @spec build_notification(String.t(), map() | list() | nil) :: map()
  def build_notification(method, params \\ nil) do
    base = %{
      "jsonrpc" => "2.0",
      "method" => method
    }

    if params do
      Map.put(base, "params", params)
    else
      base
    end
  end

  @doc """
  Determines if a message is a request.
  """
  @spec request?(message()) :: boolean()
  def request?(message) do
    Map.has_key?(message, "method") and Map.has_key?(message, "id")
  end

  @doc """
  Determines if a message is a response.
  """
  @spec response?(message()) :: boolean()
  def response?(message) do
    Map.has_key?(message, "id") and
      (Map.has_key?(message, "result") or Map.has_key?(message, "error"))
  end

  @doc """
  Determines if a message is a notification.
  """
  @spec notification?(message()) :: boolean()
  def notification?(message) do
    Map.has_key?(message, "method") and not Map.has_key?(message, "id")
  end

  @doc """
  Encodes a message to JSON.
  """
  @spec encode_message(message()) :: {:ok, String.t()} | {:error, term()}
  def encode_message(message) do
    Jason.encode(message)
  end

  @doc """
  Validates a batch of messages.
  """
  @spec parse_batch(list()) :: {:ok, [message()]} | {:error, String.t()}
  def parse_batch(messages) when is_list(messages) do
    if Enum.empty?(messages) do
      {:error, "Batch cannot be empty"}
    else
      results = Enum.map(messages, &parse_message/1)

      case Enum.find(results, fn
             {:error, _} -> true
             _ -> false
           end) do
        {:error, reason} -> {:error, reason}
        _ -> {:ok, Enum.map(results, fn {:ok, msg} -> msg end)}
      end
    end
  end

  def parse_batch(_), do: {:error, "Batch must be an array"}

  # Private functions

  defp validate_jsonrpc_version(%{"jsonrpc" => "2.0"}), do: :ok
  defp validate_jsonrpc_version(_), do: {:error, "Invalid or missing jsonrpc version"}

  defp determine_message_type(message) do
    cond do
      request?(message) -> {:ok, :request}
      response?(message) -> {:ok, :response}
      notification?(message) -> {:ok, :notification}
      true -> {:error, "Unknown message type"}
    end
  end

  defp validate_message_structure(:request, message) do
    with :ok <- validate_id(message["id"]),
         :ok <- validate_method(message["method"]),
         :ok <- validate_params(message["params"]) do
      :ok
    end
  end

  defp validate_message_structure(:response, message) do
    with :ok <- validate_id(message["id"]) do
      cond do
        Map.has_key?(message, "result") and Map.has_key?(message, "error") ->
          {:error, "Response cannot have both result and error"}

        Map.has_key?(message, "error") ->
          validate_error(message["error"])

        true ->
          :ok
      end
    end
  end

  defp validate_message_structure(:notification, message) do
    with :ok <- validate_method(message["method"]),
         :ok <- validate_params(message["params"]) do
      :ok
    end
  end

  defp validate_id(nil), do: :ok
  defp validate_id(id) when is_binary(id) or is_integer(id), do: :ok
  defp validate_id(_), do: {:error, "Invalid id type"}

  defp validate_method(method) when is_binary(method) and byte_size(method) > 0, do: :ok
  defp validate_method(_), do: {:error, "Method must be a non-empty string"}

  defp validate_params(nil), do: :ok
  defp validate_params(params) when is_map(params) or is_list(params), do: :ok
  defp validate_params(_), do: {:error, "Params must be an object or array"}

  defp validate_error(error) when is_map(error) do
    with true <- is_integer(error["code"]),
         true <- is_binary(error["message"]) do
      :ok
    else
      _ -> {:error, "Invalid error object"}
    end
  end

  defp validate_error(_), do: {:error, "Error must be an object"}

  defp error_code(:parse_error), do: @parse_error
  defp error_code(:invalid_request), do: @invalid_request
  defp error_code(:method_not_found), do: @method_not_found
  defp error_code(:invalid_params), do: @invalid_params
  defp error_code(:internal_error), do: @internal_error
  defp error_code(:resource_not_found), do: @resource_not_found
  defp error_code(:resource_access_denied), do: @resource_access_denied
  defp error_code(:tool_execution_failed), do: @tool_execution_failed
  defp error_code(code) when is_integer(code), do: code
end

defmodule RubberDuck.LLM.Provider do
  @moduledoc """
  Behaviour that all LLM providers must implement.

  Providers are responsible for:
  - Formatting requests for their specific API
  - Making HTTP calls to the provider
  - Parsing responses into a unified format
  - Handling provider-specific errors
  """

  alias RubberDuck.LLM.{Request, Response, ProviderConfig}

  @doc """
  Executes a completion request.

  Should return `{:ok, Response.t()}` on success or `{:error, reason}` on failure.
  """
  @callback execute(Request.t(), ProviderConfig.t()) :: {:ok, Response.t()} | {:error, term()}

  @doc """
  Validates that the provider is properly configured.

  This is called during initialization to ensure all required settings are present.
  """
  @callback validate_config(ProviderConfig.t()) :: :ok | {:error, term()}

  @doc """
  Returns provider-specific information.

  This can include supported features, model capabilities, etc.
  """
  @callback info() :: map()

  @doc """
  Checks if the provider supports a specific feature.

  Common features:
  - `:streaming` - Supports streaming responses
  - `:function_calling` - Supports function/tool calling
  - `:system_messages` - Supports system role messages
  - `:vision` - Supports image inputs
  - `:json_mode` - Supports structured JSON output
  """
  @callback supports_feature?(atom()) :: boolean()

  @doc """
  Estimates token count for a message.

  This is used for cost estimation and context window management.
  Returns `{:ok, token_count}` or `{:error, :not_supported}`.
  """
  @callback count_tokens(String.t() | list(map()), String.t()) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Health check for the provider.

  This should be a lightweight check to verify the provider is accessible.
  """
  @callback health_check(ProviderConfig.t()) :: {:ok, map()} | {:error, term()}

  @doc """
  Executes a streaming completion request.

  The callback function will be called for each chunk received.
  Should return `{:ok, ref}` where ref can be used to track the stream.
  """
  @callback stream_completion(Request.t(), ProviderConfig.t(), function()) ::
              {:ok, reference()} | {:error, term()}

  @optional_callbacks [health_check: 1, stream_completion: 3]

  # Helper functions for providers

  @doc """
  Builds common HTTP headers for API requests.
  """
  def build_headers(config) do
    base_headers = %{
      "content-type" => "application/json",
      "user-agent" => "RubberDuck/1.0"
    }

    headers =
      if config.api_key do
        Map.put(base_headers, "authorization", "Bearer #{config.api_key}")
      else
        base_headers
      end

    Map.merge(headers, config.headers)
  end

  @doc """
  Handles common HTTP errors.
  """
  def handle_http_error({:ok, %{status: status, body: body}}) when status >= 400 do
    error_details = parse_error_body(body)

    error_type =
      case status do
        400 -> :bad_request
        401 -> :unauthorized
        403 -> :forbidden
        404 -> :not_found
        429 -> :rate_limited
        500 -> :server_error
        502 -> :bad_gateway
        503 -> :service_unavailable
        _ -> :http_error
      end

    {:error, {error_type, error_details}}
  end

  def handle_http_error({:error, reason}) do
    {:error, {:connection_error, reason}}
  end

  defp parse_error_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> %{"message" => body}
    end
  end

  defp parse_error_body(body), do: body
end

defmodule RubberDuckWeb.MCPAuth do
  @moduledoc """
  Authentication and authorization for MCP (Model Context Protocol) channels.

  Provides secure authentication mechanisms for MCP clients including:
  - Token-based authentication
  - API key authentication
  - Client capability verification
  - Session management
  """

  require Logger

  alias RubberDuck.MCP.SecurityManager

  @type auth_result :: {:ok, map()} | {:error, String.t()}
  @type client_info :: %{
          name: String.t(),
          version: String.t(),
          capabilities: map(),
          metadata: map()
        }

  @doc """
  Authenticates an MCP client connection.

  Supports multiple authentication methods:
  - Phoenix.Token for trusted clients
  - API key for external integrations
  - Client certificate (future)
  """
  @spec authenticate_client(map(), map()) :: auth_result()
  def authenticate_client(params, connect_info) do
    Logger.debug("Authenticating MCP client with params: #{inspect(sanitize_params(params))}")

    # Extract credentials
    credentials =
      case extract_auth_credentials(params, connect_info) do
        {:ok, :token, token} -> %{"token" => token}
        {:ok, :api_key, api_key} -> %{"apiKey" => api_key}
        {:error, reason} -> {:error, reason}
      end

    # Build connection info with IP address
    connection_info =
      Map.merge(connect_info, %{
        ip_address: extract_ip_address(connect_info),
        user_agent: extract_user_agent(connect_info)
      })

    case credentials do
      {:error, reason} ->
        {:error, reason}

      creds ->
        # Delegate to SecurityManager for comprehensive authentication
        case SecurityManager.authenticate(creds, connection_info) do
          {:ok, security_context} ->
            {:ok,
             %{
               user_id: security_context.user_id,
               permissions: MapSet.to_list(security_context.capabilities),
               role: determine_role_from_capabilities(security_context.capabilities),
               client_info: Map.get(params, "clientInfo", %{}),
               security_context: security_context
             }}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Validates client information and capabilities.

  Ensures client provides required information and has compatible capabilities.
  """
  @spec validate_client_info(map()) :: {:ok, client_info()} | {:error, String.t()}
  def validate_client_info(client_info) when is_map(client_info) do
    with {:ok, name} <- validate_client_name(client_info),
         {:ok, version} <- validate_client_version(client_info),
         {:ok, capabilities} <- validate_client_capabilities(client_info) do
      validated_info = %{
        name: name,
        version: version,
        capabilities: capabilities,
        metadata: Map.get(client_info, "metadata", %{})
      }

      {:ok, validated_info}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_client_info(_), do: {:error, "Invalid client info format"}

  @doc """
  Checks if a client is authorized to use specific MCP capabilities.

  Implements capability-based authorization for fine-grained access control.
  """
  @spec authorize_capability(map(), String.t()) :: boolean()
  def authorize_capability(auth_context, capability) do
    # Use SecurityManager for authorization if security context available
    case auth_context do
      %{security_context: security_context} ->
        case SecurityManager.authorize_operation(security_context, capability, %{}) do
          :allow -> true
          {:deny, _reason} -> false
        end

      # Fallback to legacy authorization
      %{permissions: permissions} when is_list(permissions) ->
        capability in permissions or "*" in permissions

      %{role: "admin"} ->
        true

      %{role: "user"} ->
        capability in user_allowed_capabilities()

      %{role: "readonly"} ->
        capability in readonly_capabilities()

      _ ->
        false
    end
  end

  @doc """
  Creates a secure session token for an authenticated client.

  Returns a signed token that can be used for subsequent requests.
  """
  @spec create_session_token(map()) :: String.t()
  def create_session_token(auth_context) do
    # If we have a security context with a session, use that token
    case auth_context do
      %{security_context: %{session_id: session_id}} ->
        # SecurityManager already created a session, return its token
        # Extract token from security context metadata
        case RubberDuck.MCP.SessionManager.validate_token(session_id) do
          {:ok, session} ->
            session.token

          _ ->
            # Fallback to creating our own token
            create_legacy_session_token(auth_context)
        end

      _ ->
        create_legacy_session_token(auth_context)
    end
  end

  defp create_legacy_session_token(auth_context) do
    session_data = %{
      user_id: auth_context.user_id,
      client_info: auth_context.client_info,
      permissions: auth_context.permissions,
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
    }

    Phoenix.Token.sign(RubberDuckWeb.Endpoint, "mcp_session", session_data)
  end

  @doc """
  Verifies a session token and returns the associated context.
  """
  @spec verify_session_token(String.t()) :: {:ok, map()} | {:error, String.t()}
  def verify_session_token(token) do
    case Phoenix.Token.verify(RubberDuckWeb.Endpoint, "mcp_session", token, max_age: 3600) do
      {:ok, session_data} ->
        if DateTime.compare(DateTime.utc_now(), session_data.expires_at) == :lt do
          {:ok, session_data}
        else
          {:error, "Session expired"}
        end

      {:error, reason} ->
        {:error, "Invalid session token: #{reason}"}
    end
  end

  @doc """
  Refreshes a session token if it's still valid.
  """
  @spec refresh_session_token(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def refresh_session_token(token) do
    case verify_session_token(token) do
      {:ok, session_data} ->
        # Create new token with extended expiration
        new_token = create_session_token(session_data)
        {:ok, new_token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp extract_auth_credentials(params, connect_info) do
    cond do
      # Check for token in params
      Map.has_key?(params, "token") and is_binary(params["token"]) ->
        {:ok, :token, params["token"]}

      # Check for API key in params
      Map.has_key?(params, "apiKey") and is_binary(params["apiKey"]) ->
        {:ok, :api_key, params["apiKey"]}

      # Check for API key in query string
      true ->
        case extract_api_key_from_uri(connect_info) do
          {:ok, api_key} -> {:ok, :api_key, api_key}
          :error -> {:error, "No authentication credentials provided"}
        end
    end
  end

  defp extract_api_key_from_uri(%{uri: %{query: query}}) when is_binary(query) do
    case URI.decode_query(query) do
      %{"api_key" => api_key} when is_binary(api_key) and api_key != "" ->
        {:ok, api_key}

      %{"apiKey" => api_key} when is_binary(api_key) and api_key != "" ->
        {:ok, api_key}

      _ ->
        :error
    end
  end

  defp extract_api_key_from_uri(_), do: :error

  defp validate_client_name(%{"name" => name}) when is_binary(name) and name != "" do
    {:ok, name}
  end

  defp validate_client_name(_), do: {:error, "Missing or invalid client name"}

  defp validate_client_version(%{"version" => version}) when is_binary(version) and version != "" do
    {:ok, version}
  end

  defp validate_client_version(_), do: {:error, "Missing or invalid client version"}

  defp validate_client_capabilities(client_info) do
    capabilities = Map.get(client_info, "capabilities", %{})

    if is_map(capabilities) do
      {:ok, capabilities}
    else
      {:error, "Invalid client capabilities format"}
    end
  end

  defp user_allowed_capabilities do
    [
      "tools:list",
      "tools:call",
      "resources:list",
      "resources:read",
      "prompts:list",
      "prompts:get",
      "workflows:create",
      "workflows:execute",
      "workflows:templates"
    ]
  end

  defp readonly_capabilities do
    [
      "tools:list",
      "resources:list",
      "resources:read",
      "prompts:list",
      "prompts:get",
      "workflows:templates"
    ]
  end

  defp sanitize_params(params) do
    params
    |> Map.drop(["token", "apiKey", "api_key", "password", "secret"])
    |> Map.put("sanitized", true)
  end

  defp extract_ip_address(connect_info) do
    case connect_info do
      %{peer_data: %{address: {a, b, c, d}}} ->
        "#{a}.#{b}.#{c}.#{d}"

      %{x_headers: headers} ->
        # Check for forwarded IP
        Enum.find_value(headers, fn
          {"x-forwarded-for", ip} -> String.split(ip, ",") |> List.first() |> String.trim()
          {"x-real-ip", ip} -> String.trim(ip)
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  defp extract_user_agent(connect_info) do
    case connect_info do
      %{x_headers: headers} ->
        Enum.find_value(headers, fn
          {"user-agent", ua} -> ua
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  defp determine_role_from_capabilities(capabilities) do
    cond do
      MapSet.member?(capabilities, "admin:*") -> "admin"
      MapSet.member?(capabilities, "workflows:create") -> "user"
      true -> "readonly"
    end
  end
end

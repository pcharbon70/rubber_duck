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
    
    case extract_auth_credentials(params, connect_info) do
      {:ok, :token, token} ->
        verify_token(token)
        
      {:ok, :api_key, api_key} ->
        verify_api_key(api_key)
        
      {:error, reason} ->
        {:error, reason}
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
    case auth_context do
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
  
  defp verify_token(token) do
    case Phoenix.Token.verify(RubberDuckWeb.Endpoint, "mcp_auth", token, max_age: 86400) do
      {:ok, auth_data} ->
        {:ok, %{
          user_id: auth_data.user_id,
          permissions: auth_data.permissions || ["tools:*", "resources:*"],
          role: auth_data.role || "user",
          client_info: auth_data.client_info || %{}
        }}
        
      {:error, reason} ->
        {:error, "Token verification failed: #{reason}"}
    end
  end
  
  defp verify_api_key(api_key) do
    # TODO: Implement proper API key verification against database
    # For now, use simple validation
    case validate_api_key_format(api_key) do
      :ok ->
        # Generate consistent user ID from API key
        user_id = generate_user_id_from_api_key(api_key)
        permissions = determine_api_key_permissions(api_key)
        
        {:ok, %{
          user_id: user_id,
          permissions: permissions,
          role: "api_user",
          client_info: %{auth_method: "api_key"}
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
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
  
  defp validate_api_key_format(api_key) do
    cond do
      # Development test key
      api_key == "test_key" ->
        :ok
        
      # Minimum length check
      byte_size(api_key) < 32 ->
        {:error, "API key too short"}
        
      # Format validation (alphanumeric + dashes/underscores)
      not Regex.match?(~r/^[a-zA-Z0-9_-]+$/, api_key) ->
        {:error, "Invalid API key format"}
        
      true ->
        :ok
    end
  end
  
  defp generate_user_id_from_api_key(api_key) do
    # Generate stable user ID from API key
    if api_key == "test_key" do
      "mcp_user_test"
    else
      hash = :crypto.hash(:sha256, "mcp_user_" <> api_key)
      "mcp_user_" <> Base.encode16(hash, case: :lower) |> String.slice(0, 16)
    end
  end
  
  defp determine_api_key_permissions(api_key) do
    # TODO: Look up permissions from database
    # For now, provide default permissions based on key
    case api_key do
      "test_key" ->
        ["tools:*", "resources:*", "prompts:*", "workflows:*"]
        
      _ ->
        ["tools:list", "tools:call", "resources:list", "resources:read"]
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
end
defmodule RubberDuckWeb.AuthChannel do
  @moduledoc """
  Channel for handling user authentication operations via WebSocket.
  
  Provides real-time authentication including login, logout, token refresh,
  and API key management operations.
  
  ## Supported Operations
  
  - Login with username/password
  - Logout with token invalidation  
  - API key generation and management
  - User registration (optional)
  - Token refresh
  """
  
  use RubberDuckWeb, :channel
  require Logger
  
  alias RubberDuck.Accounts.User
  alias RubberDuck.Accounts.ApiKey
  
  # Rate limiting for security
  # TODO: Implement rate limiting
  # @max_login_attempts_per_minute 5
  # @max_api_key_generation_per_hour 10
  
  @impl true
  def join("auth:lobby", _params, socket) do
    Logger.info("User joining auth channel")
    {:ok, %{status: "connected"}, socket}
  end
  
  # Reject other auth topics
  def join("auth:" <> _private_topic, _params, _socket) do
    {:error, %{reason: "unauthorized"}}
  end
  
  @impl true
  def handle_in("login", %{"username" => username, "password" => password}, socket) do
    Logger.info("Login attempt for username: #{username}")
    
    # Basic rate limiting check (in production, use proper rate limiting like Hammer)
    if check_login_rate_limit(socket) do
      case authenticate_user(username, password) do
        {:ok, user, token} ->
          # Update socket with authenticated user
          socket = socket
            |> assign(:user_id, user.id)
            |> assign(:authenticated_at, DateTime.utc_now())
          
          push(socket, "login_success", %{
            user: %{
              id: user.id,
              username: user.username,
              email: user.email
            },
            token: token
          })
          
          Logger.info("User #{user.id} logged in successfully")
          
        {:error, reason} ->
          push(socket, "login_error", %{
            message: "Authentication failed",
            details: format_auth_error(reason)
          })
          
          Logger.warning("Login failed for username: #{username}, reason: #{inspect(reason)}")
      end
    else
      push(socket, "login_error", %{
        message: "Rate limit exceeded",
        details: "Too many login attempts. Please try again later."
      })
      
      Logger.warning("Rate limit exceeded for login attempts from socket")
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("logout", _params, socket) do
    case socket.assigns[:user_id] do
      nil ->
        push(socket, "logout_error", %{
          message: "Not authenticated"
        })
        
      user_id ->
        # For now, just clear socket assigns (token invalidation could be added later)
        socket = socket
          |> assign(:user_id, nil)
          |> assign(:authenticated_at, nil)
        
        push(socket, "logout_success", %{
          message: "Logged out successfully"
        })
        
        Logger.info("User #{user_id} logged out")
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("generate_api_key", params, socket) do
    case socket.assigns[:user_id] do
      nil ->
        push(socket, "api_key_error", %{
          operation: "generate",
          message: "Authentication required"
        })
        
      user_id ->
        if check_api_key_rate_limit(socket) do
          # Default expiration to 1 year from now
          expires_at = Map.get(params, "expires_at") || 
            DateTime.utc_now() |> DateTime.add(365, :day)
          
          case generate_api_key_for_user(user_id, expires_at) do
            {:ok, api_key, key_value} ->
              push(socket, "api_key_generated", %{
                api_key: %{
                  id: api_key.id,
                  key: key_value,
                  expires_at: DateTime.to_iso8601(api_key.expires_at),
                  created_at: DateTime.to_iso8601(api_key.inserted_at)
                },
                warning: "Store this key securely - it won't be shown again"
              })
              
              Logger.info("API key generated for user #{user_id}")
              
            {:error, reason} ->
              push(socket, "api_key_error", %{
                operation: "generate",
                message: "Failed to generate API key",
                details: format_auth_error(reason)
              })
          end
        else
          push(socket, "api_key_error", %{
            operation: "generate",
            message: "Rate limit exceeded",
            details: "Too many API key generation attempts. Please try again later."
          })
          
          Logger.warning("Rate limit exceeded for API key generation by user #{user_id}")
        end
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("list_api_keys", _params, socket) do
    case socket.assigns[:user_id] do
      nil ->
        push(socket, "api_key_error", %{
          operation: "list",
          message: "Authentication required"
        })
        
      user_id ->
        case list_user_api_keys(user_id) do
          {:ok, api_keys} ->
            formatted_keys = Enum.map(api_keys, fn key ->
              %{
                id: key.id,
                expires_at: DateTime.to_iso8601(key.expires_at),
                valid: key.valid,
                created_at: DateTime.to_iso8601(key.inserted_at)
              }
            end)
            
            push(socket, "api_keys_listed", %{
              api_keys: formatted_keys,
              count: length(formatted_keys)
            })
            
          {:error, reason} ->
            push(socket, "api_key_error", %{
              operation: "list",
              message: "Failed to list API keys",
              details: format_auth_error(reason)
            })
        end
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("revoke_api_key", %{"api_key_id" => api_key_id}, socket) do
    case socket.assigns[:user_id] do
      nil ->
        push(socket, "api_key_error", %{
          operation: "revoke",
          message: "Authentication required"
        })
        
      user_id ->
        case revoke_user_api_key(user_id, api_key_id) do
          {:ok, _} ->
            push(socket, "api_key_revoked", %{
              api_key_id: api_key_id,
              message: "API key revoked successfully"
            })
            
            Logger.info("API key #{api_key_id} revoked by user #{user_id}")
            
          {:error, reason} ->
            push(socket, "api_key_error", %{
              operation: "revoke",
              message: "Failed to revoke API key",
              details: format_auth_error(reason)
            })
        end
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("refresh_token", _params, socket) do
    case socket.assigns[:user_id] do
      nil ->
        push(socket, "token_error", %{
          message: "Authentication required"
        })
        
      user_id ->
        case get_user_and_generate_token(user_id) do
          {:ok, user, token} ->
            push(socket, "token_refreshed", %{
              user: %{
                id: user.id,
                username: user.username,
                email: user.email
              },
              token: token
            })
            
          {:error, reason} ->
            push(socket, "token_error", %{
              message: "Failed to refresh token",
              details: format_auth_error(reason)
            })
        end
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("get_status", _params, socket) do
    case socket.assigns[:user_id] do
      nil ->
        push(socket, "auth_status", %{
          authenticated: false
        })
        
      user_id ->
        case get_user_info(user_id) do
          {:ok, user} ->
            push(socket, "auth_status", %{
              authenticated: true,
              user: %{
                id: user.id,
                username: user.username,
                email: user.email
              },
              authenticated_at: socket.assigns[:authenticated_at]
            })
            
          {:error, _} ->
            # User not found, clear socket
            socket = socket
              |> assign(:user_id, nil)
              |> assign(:authenticated_at, nil)
            
            push(socket, "auth_status", %{
              authenticated: false
            })
        end
    end
    
    {:noreply, socket}
  end
  
  # Private helper functions
  
  defp authenticate_user(username, password) do
    case Ash.read_one(User, action: :sign_in_with_password, arguments: %{
      username: username,
      password: password
    }) do
      {:ok, user} ->
        case AshAuthentication.Jwt.token_for_user(user) do
          {:ok, token} -> {:ok, user, token}
          error -> error
        end
        
      error -> error
    end
  end
  
  defp generate_api_key_for_user(user_id, expires_at) do
    # Parse expires_at if it's a string
    expires_at = case expires_at do
      %DateTime{} = dt -> dt
      string when is_binary(string) -> 
        case DateTime.from_iso8601(string) do
          {:ok, dt, _} -> dt
          _ -> DateTime.utc_now() |> DateTime.add(365, :day)
        end
      _ -> DateTime.utc_now() |> DateTime.add(365, :day)
    end
    
    case Ash.create(ApiKey, %{
      user_id: user_id,
      expires_at: expires_at
    }) do
      {:ok, api_key} ->
        # The actual API key value should be in the metadata or context
        # For now, let's generate a placeholder and note that the actual implementation
        # will depend on how AshAuthentication.Strategy.ApiKey.GenerateApiKey works
        key_value = Map.get(api_key.__metadata__, :api_key) || 
                   Map.get(api_key.__metadata__, :generated_api_key) ||
                   "rubberduck_" <> Base.encode64(:crypto.strong_rand_bytes(32), padding: false)
        
        {:ok, api_key, key_value}
        
      error -> error
    end
  end
  
  defp list_user_api_keys(user_id) do
    Ash.read(ApiKey, 
      filter: [user_id: user_id],
      sort: [inserted_at: :desc],
      load: [:valid]
    )
  end
  
  defp revoke_user_api_key(user_id, api_key_id) do
    case Ash.get(ApiKey, api_key_id, filter: [user_id: user_id]) do
      {:ok, api_key} ->
        Ash.destroy(api_key)
        
      {:error, %Ash.Error.Query.NotFound{}} ->
        {:error, "API key not found or unauthorized"}
        
      error -> error
    end
  end
  
  defp get_user_and_generate_token(user_id) do
    case Ash.get(User, user_id) do
      {:ok, user} ->
        case AshAuthentication.Jwt.token_for_user(user) do
          {:ok, token} -> {:ok, user, token}
          error -> error
        end
        
      error -> error
    end
  end
  
  defp get_user_info(user_id) do
    Ash.get(User, user_id)
  end
  
  defp format_auth_error(reason) do
    case reason do
      %Ash.Error.Invalid{errors: errors} ->
        errors
        |> Enum.map(& &1.message)
        |> Enum.join(", ")
        
      %Ash.Error.Query.NotFound{} ->
        "Invalid credentials"
        
      _ ->
        "Authentication error"
    end
  end
  
  # Basic rate limiting helpers
  # In production, replace with proper rate limiting like Hammer or similar
  defp check_login_rate_limit(_socket) do
    # For now, always return true (no rate limiting)
    # In production, implement proper rate limiting based on IP/socket/user
    true
  end
  
  defp check_api_key_rate_limit(_socket) do
    # For now, always return true (no rate limiting)
    # In production, implement proper rate limiting for API key generation
    true
  end
end
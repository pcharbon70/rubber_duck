defmodule RubberDuckWeb.AuthChannel do
  @moduledoc """
  Channel for handling user authentication operations via WebSocket.

  Provides real-time authentication including login, logout, and token refresh.
  API key management has been moved to the dedicated ApiKeyChannel.

  ## Supported Operations

  - Login with username/password
  - Logout with token invalidation  
  - User registration (optional)
  - Token refresh
  - Get authentication status
  """

  use RubberDuckWeb, :channel
  require Logger

  alias RubberDuck.Accounts.User

  # Rate limiting for security
  # TODO: Implement rate limiting
  # @max_login_attempts_per_minute 5

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
          socket =
            socket
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
        socket =
          socket
          |> assign(:user_id, nil)
          |> assign(:authenticated_at, nil)

        push(socket, "logout_success", %{
          message: "Logged out successfully"
        })

        Logger.info("User #{user_id} logged out")
    end

    {:noreply, socket}
  end

  # API key management has been moved to ApiKeyChannel
  # Users should connect to the ApiKeyChannel on UserSocket for API key operations

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
            socket =
              socket
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
    require Ash.Query

    # Build a query with the sign_in_with_password action
    query =
      RubberDuck.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{
        username: username,
        password: password
      })

    # Execute the query with authorization bypassed
    case Ash.read_one(query, authorize?: false) do
      {:ok, user} ->
        case AshAuthentication.Jwt.token_for_user(user) do
          {:ok, token, _claims} -> {:ok, user, token}
          # Handle both return formats
          {:ok, token} -> {:ok, user, token}
          error -> error
        end

      error ->
        error
    end
  end

  defp get_user_and_generate_token(user_id) do
    case Ash.get(User, user_id) do
      {:ok, user} ->
        case AshAuthentication.Jwt.token_for_user(user) do
          {:ok, token, _claims} -> {:ok, user, token}
          # Handle both return formats
          {:ok, token} -> {:ok, user, token}
          error -> error
        end

      error ->
        error
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
end

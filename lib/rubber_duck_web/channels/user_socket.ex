defmodule RubberDuckWeb.UserSocket do
  @moduledoc """
  Authenticated user socket for RubberDuck application.
  
  This socket requires JWT authentication. API key authentication has been moved
  to the AuthChannel on AuthSocket, which returns a JWT token.
  
  ## Authentication Flow
  
  1. Connect to AuthSocket and authenticate with username/password or API key
  2. Receive JWT token from AuthChannel
  3. Connect to UserSocket with the JWT token
  
  ## Connection Parameters
  
  - `token` (required): JWT token obtained from AuthChannel
  
  ## Example
  
      # JavaScript client
      const socket = new Socket("/socket", {
        params: {token: jwtToken}
      })
  """
  
  use Phoenix.Socket

  require Logger

  # Channels - AuthChannel moved to AuthSocket
  channel("code:*", RubberDuckWeb.CodeChannel)
  channel("analysis:*", RubberDuckWeb.AnalysisChannel)
  channel("workspace:*", RubberDuckWeb.WorkspaceChannel)
  channel("conversation:*", RubberDuckWeb.ConversationChannel)
  channel("mcp:*", RubberDuckWeb.MCPChannel)
  channel("status:*", RubberDuckWeb.StatusChannel)
  channel("api_keys:*", RubberDuckWeb.ApiKeyChannel)
  channel("planning:*", RubberDuckWeb.PlanningChannel)

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error` or `{:error, term}`. To control the
  # response the client receives in that case, [define an error handler in the
  # websocket
  # configuration](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html#socket/3-websocket-configuration).
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  @impl true
  def connect(params, socket, _connect_info) do
    # Log connection without sensitive data
    safe_params = Map.drop(params, ["token"])
    Logger.info("WebSocket connection attempt with params: #{inspect(safe_params)}")

    case authenticate(params) do
      {:ok, user_id} ->
        socket =
          socket
          |> assign(:user_id, user_id)
          |> assign(:joined_at, DateTime.utc_now())

        Logger.info("User #{user_id} connected to socket")
        {:ok, socket}

      {:error, reason} ->
        Logger.warning("Socket connection denied: #{reason}")
        :error
    end
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     Elixir.RubberDuckWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  # Private functions

  defp authenticate(%{"token" => token}) when is_binary(token) and byte_size(token) > 0 do
    # Verify JWT token using Ash Authentication
    case AshAuthentication.Jwt.verify(token, RubberDuck.Accounts.User) do
      {:ok, claims, _resource} ->
        # Extract user_id from the subject claim
        # The subject is in format "user?id=UUID", so we need to extract the UUID
        subject = claims["sub"]
        user_id = extract_user_id_from_subject(subject)
        {:ok, user_id}

      {:error, :token_expired} ->
        {:error, "Token expired"}

      {:error, :token_revoked} ->
        {:error, "Token revoked"}

      {:error, reason} ->
        Logger.debug("Token verification failed: #{inspect(reason)}")
        {:error, "Invalid token"}
        
      :error ->
        # Handle malformed tokens
        {:error, "Invalid token format"}
    end
  end

  defp authenticate(_params) do
    {:error, "No authentication credentials provided. Please use a JWT token."}
  end
  
  defp extract_user_id_from_subject(subject) when is_binary(subject) do
    # Handle subject format "user?id=UUID"
    case String.split(subject, "id=") do
      [_, user_id] -> user_id
      _ -> subject  # Fallback to original subject if format is different
    end
  end
  
  defp extract_user_id_from_subject(subject), do: subject
end

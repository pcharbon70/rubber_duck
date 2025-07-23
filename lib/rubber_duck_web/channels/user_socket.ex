defmodule RubberDuckWeb.UserSocket do
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
  def connect(params, socket, connect_info) do
    # Log connection without sensitive data
    safe_params = Map.drop(params, ["api_key", "token"])
    Logger.info("WebSocket connection attempt with params: #{inspect(safe_params)}")

    # Try to get API key from query params if not in params
    auth_params =
      case get_api_key_from_uri(connect_info) do
        {:ok, api_key} -> Map.put(params, "api_key", api_key)
        _ -> params
      end

    case authenticate(auth_params) do
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

  defp authenticate(%{"token" => token}) when is_binary(token) do
    # Verify JWT token using Ash Authentication
    case AshAuthentication.Jwt.verify(token, RubberDuck.Accounts.User) do
      {:ok, claims, _resource} ->
        # Extract user_id from the subject claim
        user_id = claims["sub"]
        {:ok, user_id}

      {:error, :token_expired} ->
        {:error, "Token expired"}

      {:error, :token_revoked} ->
        {:error, "Token revoked"}

      {:error, reason} ->
        Logger.debug("Token verification failed: #{inspect(reason)}")
        {:error, "Invalid token"}
    end
  end

  defp authenticate(%{"api_key" => api_key}) when is_binary(api_key) do
    # Authenticate using Ash Authentication API key strategy
    case authenticate_api_key(api_key) do
      {:ok, user} ->
        # Convert UUID to string
        {:ok, to_string(user.id)}

      {:error, _reason} ->
        {:error, "Invalid API key"}
    end
  end

  defp authenticate(_params) do
    {:error, "No authentication credentials provided"}
  end

  defp authenticate_api_key(api_key) do
    # Use the sign_in_with_api_key action to authenticate
    case Ash.read_one(RubberDuck.Accounts.User,
           action: :sign_in_with_api_key,
           input: %{api_key: api_key}
         ) do
      {:ok, user} -> {:ok, user}
      {:error, _} -> {:error, :invalid_api_key}
    end
  end

  defp get_api_key_from_uri(%{uri: %{query: query}}) when is_binary(query) do
    case URI.decode_query(query) do
      %{"api_key" => api_key} when is_binary(api_key) and api_key != "" ->
        {:ok, api_key}

      _ ->
        :error
    end
  end

  defp get_api_key_from_uri(_), do: :error
end

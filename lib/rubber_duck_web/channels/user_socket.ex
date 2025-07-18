defmodule RubberDuckWeb.UserSocket do
  use Phoenix.Socket

  require Logger

  # Channels
  channel("code:*", RubberDuckWeb.CodeChannel)
  channel("analysis:*", RubberDuckWeb.AnalysisChannel)
  channel("workspace:*", RubberDuckWeb.WorkspaceChannel)
  channel("conversation:*", RubberDuckWeb.ConversationChannel)
  channel("mcp:*", RubberDuckWeb.MCPChannel)

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
    auth_params = case get_api_key_from_uri(connect_info) do
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
    # Verify the token with a max age of 1 day (86400 seconds)
    case Phoenix.Token.verify(RubberDuckWeb.Endpoint, "user socket", token, max_age: 86400) do
      {:ok, user_id} ->
        {:ok, user_id}

      {:error, :expired} ->
        {:error, "Token expired"}

      {:error, :invalid} ->
        {:error, "Invalid token"}

      {:error, _} ->
        {:error, "Authentication failed"}
    end
  end

  defp authenticate(%{"api_key" => api_key}) when is_binary(api_key) do
    # TODO: Implement API key authentication
    # This would check the API key against your database
    # For now, we'll use a simple check
    if valid_api_key?(api_key) do
      # Generate a stable UUID from the API key for development
      user_id = generate_user_uuid_from_api_key(api_key)
      {:ok, user_id}
    else
      {:error, "Invalid API key"}
    end
  end

  defp authenticate(_params) do
    {:error, "No authentication credentials provided"}
  end

  defp valid_api_key?(api_key) do
    # TODO: Implement real API key validation
    # This is a placeholder - in production, check against database
    # For development, accept "test_key"
    api_key == "test_key" || byte_size(api_key) >= 32
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
  
  defp generate_user_uuid_from_api_key(api_key) do
    # Generate a stable UUID from the API key
    # This ensures the same API key always maps to the same user_id
    # For development, use a fixed UUID for test_key
    if api_key == "test_key" do
      "00000000-0000-0000-0000-000000000001"
    else
      # For other keys, generate a UUID v4-like string from the hash
      hash_hex = :crypto.hash(:md5, "rubber_duck_" <> api_key)
                |> Base.encode16(case: :lower)
      
      String.slice(hash_hex, 0..7) <> "-" <>
      "0000-4000-8000-" <>  # Version 4 UUID markers
      String.slice(hash_hex, 8..19)
    end
  end
end

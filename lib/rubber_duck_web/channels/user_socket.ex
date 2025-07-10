defmodule RubberDuckWeb.UserSocket do
  use Phoenix.Socket

  require Logger

  # Channels
  channel("code:*", RubberDuckWeb.CodeChannel)
  channel("analysis:*", RubberDuckWeb.AnalysisChannel)
  channel("workspace:*", RubberDuckWeb.WorkspaceChannel)
  channel("cli:*", RubberDuckWeb.CLIChannel)

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
      {:ok, "api_user_#{api_key}"}
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
    byte_size(api_key) >= 32
  end
end

defmodule RubberDuckWeb.UserSocket do
  @moduledoc """
  UserSocket for WebSocket connections to RubberDuck system.
  
  Handles authentication and channel routing for real-time
  communication with coding assistant clients.
  """

  use Phoenix.Socket

  # A Socket handler
  #
  # It's possible to control the websocket connection and
  # assign values that can be accessed by your channel topics.

  ## Channels
  channel "coding:*", RubberDuckWeb.CodingChannel

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error` or `{:error, term}`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  @impl true
  def connect(_params, socket, _connect_info) do
    # For now, allow anonymous connections for development
    # TODO: Implement proper authentication
    {:ok, assign(socket, :user_id, generate_anonymous_id())}
  end

  # Socket IDs are topics that allow you to identify all sockets for a given user:
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

  defp generate_anonymous_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end
defmodule RubberDuckWeb.AuthSocket do
  @moduledoc """
  Socket specifically for authentication operations.
  
  This socket allows unauthenticated connections and only handles
  the AuthChannel. All other channels require authentication and
  use the UserSocket.
  """
  
  use Phoenix.Socket
  
  require Logger
  
  # Only handle authentication channel
  channel "auth:*", RubberDuckWeb.AuthChannel
  
  @impl true
  def connect(_params, socket, _connect_info) do
    Logger.info("Unauthenticated socket connection for auth operations")
    
    # Allow all connections - no authentication required
    socket = socket
      |> assign(:joined_at, DateTime.utc_now())
      |> assign(:authenticated, false)
    
    {:ok, socket}
  end
  
  @impl true
  def id(_socket) do
    # Return nil for anonymous connections
    nil
  end
end
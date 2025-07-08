defmodule RubberDuckWeb.Presence do
  @moduledoc """
  Provides presence tracking for channels to enable collaborative features.

  This module tracks:
  - Active users in projects/files
  - Cursor positions for collaborative editing
  - User activity status
  """

  use Phoenix.Presence,
    otp_app: :rubber_duck,
    pubsub_server: RubberDuck.PubSub
end

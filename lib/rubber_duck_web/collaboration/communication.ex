defmodule RubberDuckWeb.Collaboration.Communication do
  @moduledoc """
  Handles real-time communication features for collaborative sessions.

  Features:
  - Emoji reactions
  - Pointer/cursor sharing
  - Quick messages
  - Activity notifications
  """

  use GenServer
  alias Phoenix.PubSub
  require Logger

  # milliseconds between reactions
  @reaction_cooldown 500
  # milliseconds between pointer updates
  @pointer_update_rate 50

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Send an emoji reaction.
  """
  def send_reaction(project_id, user_id, emoji, location \\ nil) do
    GenServer.cast(__MODULE__, {:send_reaction, project_id, user_id, emoji, location})
  end

  @doc """
  Update pointer position.
  """
  def update_pointer(project_id, user_id, position) do
    GenServer.cast(__MODULE__, {:update_pointer, project_id, user_id, position})
  end

  @doc """
  Send a quick message.
  """
  def send_quick_message(project_id, user_id, message) do
    GenServer.cast(__MODULE__, {:send_quick_message, project_id, user_id, message})
  end

  @doc """
  Notify activity (typing, reading, etc).
  """
  def notify_activity(project_id, user_id, activity) do
    GenServer.cast(__MODULE__, {:notify_activity, project_id, user_id, activity})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      # Rate limiting for reactions
      reaction_timestamps: %{},
      # Pointer positions
      pointers: %{},
      # Pointer update throttling
      pointer_timers: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:send_reaction, project_id, user_id, emoji, location}, state) do
    # Check rate limit
    now = System.system_time(:millisecond)
    last_reaction = get_in(state, [:reaction_timestamps, {project_id, user_id}]) || 0

    state =
      if now - last_reaction >= @reaction_cooldown do
        # Valid emoji check
        if valid_emoji?(emoji) do
          reaction = %{
            user_id: user_id,
            emoji: emoji,
            location: location,
            timestamp: DateTime.utc_now()
          }

          # Broadcast reaction
          PubSub.broadcast(
            RubberDuck.PubSub,
            "project:#{project_id}:communication",
            {:reaction, reaction}
          )

          # Update rate limit
          put_in(state, [:reaction_timestamps, {project_id, user_id}], now)
        else
          state
        end
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:update_pointer, project_id, user_id, position}, state) do
    # Throttle pointer updates per user
    timer_key = {project_id, user_id}

    case get_in(state, [:pointer_timers, timer_key]) do
      nil ->
        # No timer, send immediately and start timer
        broadcast_pointer(project_id, user_id, position)

        timer_ref =
          Process.send_after(
            self(),
            {:clear_pointer_timer, timer_key},
            @pointer_update_rate
          )

        state =
          state
          |> put_in([:pointers, timer_key], position)
          |> put_in([:pointer_timers, timer_key], timer_ref)

        {:noreply, state}

      _timer ->
        # Timer exists, just update position
        state = put_in(state, [:pointers, timer_key], position)
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:send_quick_message, project_id, user_id, message}, state) do
    if valid_quick_message?(message) do
      quick_msg = %{
        user_id: user_id,
        # Limit length
        message: String.slice(message, 0, 100),
        timestamp: DateTime.utc_now()
      }

      PubSub.broadcast(
        RubberDuck.PubSub,
        "project:#{project_id}:communication",
        {:quick_message, quick_msg}
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:notify_activity, project_id, user_id, activity}, state) do
    if valid_activity?(activity) do
      notification = %{
        user_id: user_id,
        activity: activity,
        timestamp: DateTime.utc_now()
      }

      PubSub.broadcast(
        RubberDuck.PubSub,
        "project:#{project_id}:communication",
        {:activity_notification, notification}
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:clear_pointer_timer, timer_key}, state) do
    # Send any pending pointer update
    case get_in(state, [:pointers, timer_key]) do
      nil ->
        :ok

      position ->
        {project_id, user_id} = timer_key
        broadcast_pointer(project_id, user_id, position)
    end

    # Clear timer and position
    state =
      state
      |> update_in([:pointer_timers], &Map.delete(&1, timer_key))
      |> update_in([:pointers], &Map.delete(&1, timer_key))

    {:noreply, state}
  end

  # Private Functions

  defp valid_emoji?(emoji) do
    # List of allowed emojis for reactions
    allowed = ["👍", "👎", "❤️", "🎉", "🤔", "👀", "🚀", "💡", "🐛", "✅", "❌", "⚡"]
    emoji in allowed
  end

  defp valid_quick_message?(message) do
    message != nil &&
      String.length(String.trim(message)) > 0 &&
      String.length(message) <= 100
  end

  defp valid_activity?(activity) do
    activity in [:typing, :reading, :debugging, :testing, :reviewing]
  end

  defp broadcast_pointer(project_id, user_id, position) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:communication",
      {:pointer_update,
       %{
         user_id: user_id,
         position: position,
         timestamp: DateTime.utc_now()
       }}
    )
  end
end

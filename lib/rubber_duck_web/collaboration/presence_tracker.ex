defmodule RubberDuckWeb.Collaboration.PresenceTracker do
  @moduledoc """
  Enhanced presence tracking for real-time collaboration.
  
  Tracks user presence with detailed activity information including:
  - Cursor positions in editor
  - Current file and line
  - Active selections
  - User status (typing, idle, etc.)
  """
  
  use GenServer
  alias Phoenix.PubSub
  alias RubberDuckWeb.Presence
  
  require Logger
  
  @update_interval 1000  # Update presence every second
  @idle_threshold 30_000 # Mark as idle after 30 seconds
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Track a user's presence in a project.
  """
  def track_user(project_id, user_id, user_data) do
    GenServer.cast(__MODULE__, {:track_user, project_id, user_id, user_data})
  end
  
  @doc """
  Update user's cursor position.
  """
  def update_cursor(project_id, user_id, file_path, position) do
    GenServer.cast(__MODULE__, {:update_cursor, project_id, user_id, file_path, position})
  end
  
  @doc """
  Update user's selection.
  """
  def update_selection(project_id, user_id, file_path, selection) do
    GenServer.cast(__MODULE__, {:update_selection, project_id, user_id, file_path, selection})
  end
  
  @doc """
  Update user activity status.
  """
  def update_activity(project_id, user_id, activity) do
    GenServer.cast(__MODULE__, {:update_activity, project_id, user_id, activity})
  end
  
  @doc """
  Get all active users in a project.
  """
  def get_users(project_id) do
    GenServer.call(__MODULE__, {:get_users, project_id})
  end
  
  @doc """
  Get detailed presence info for a user.
  """
  def get_user_info(project_id, user_id) do
    GenServer.call(__MODULE__, {:get_user_info, project_id, user_id})
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Schedule periodic presence updates
    :timer.send_interval(@update_interval, :update_presence)
    
    state = %{
      # project_id => %{user_id => presence_data}
      projects: %{},
      # Track last activity time for idle detection
      last_activity: %{}
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:track_user, project_id, user_id, user_data}, state) do
    presence_data = %{
      user_id: user_id,
      username: user_data.username,
      email: user_data.email,
      avatar_url: user_data.avatar_url || generate_avatar_url(user_data.email),
      color: assign_user_color(user_id),
      status: :active,
      current_file: nil,
      cursor: %{
        file: nil,
        line: nil,
        column: nil
      },
      selection: nil,
      activity: %{
        type: :idle,
        since: DateTime.utc_now()
      },
      joined_at: DateTime.utc_now()
    }
    
    # Track in Phoenix Presence
    topic = "project:#{project_id}"
    Presence.track(
      self(),
      topic,
      user_id,
      presence_data
    )
    
    # Update local state
    state = 
      state
      |> put_in([:projects, project_id, user_id], presence_data)
      |> put_in([:last_activity, {project_id, user_id}], System.system_time(:millisecond))
    
    # Broadcast user joined
    broadcast_presence_update(project_id, :user_joined, presence_data)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:update_cursor, project_id, user_id, file_path, position}, state) do
    case get_in(state, [:projects, project_id, user_id]) do
      nil -> 
        {:noreply, state}
        
      user_data ->
        updated_data = 
          user_data
          |> Map.put(:current_file, file_path)
          |> put_in([:cursor], %{
            file: file_path,
            line: position.line,
            column: position.column
          })
          |> Map.put(:status, :active)
        
        state = 
          state
          |> put_in([:projects, project_id, user_id], updated_data)
          |> put_in([:last_activity, {project_id, user_id}], System.system_time(:millisecond))
        
        # Broadcast cursor update
        broadcast_presence_update(project_id, :cursor_moved, %{
          user_id: user_id,
          cursor: updated_data.cursor,
          color: updated_data.color
        })
        
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_cast({:update_selection, project_id, user_id, file_path, selection}, state) do
    case get_in(state, [:projects, project_id, user_id]) do
      nil -> 
        {:noreply, state}
        
      user_data ->
        updated_data = Map.put(user_data, :selection, %{
          file: file_path,
          start_line: selection.start_line,
          start_column: selection.start_column,
          end_line: selection.end_line,
          end_column: selection.end_column
        })
        
        state = 
          state
          |> put_in([:projects, project_id, user_id], updated_data)
          |> put_in([:last_activity, {project_id, user_id}], System.system_time(:millisecond))
        
        # Broadcast selection update
        broadcast_presence_update(project_id, :selection_changed, %{
          user_id: user_id,
          selection: updated_data.selection,
          color: updated_data.color
        })
        
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_cast({:update_activity, project_id, user_id, activity}, state) do
    case get_in(state, [:projects, project_id, user_id]) do
      nil -> 
        {:noreply, state}
        
      user_data ->
        updated_data = 
          user_data
          |> Map.put(:activity, %{
            type: activity,
            since: DateTime.utc_now()
          })
          |> Map.put(:status, activity_to_status(activity))
        
        state = 
          state
          |> put_in([:projects, project_id, user_id], updated_data)
          |> put_in([:last_activity, {project_id, user_id}], System.system_time(:millisecond))
        
        # Update Phoenix Presence
        Presence.update(
          self(),
          "project:#{project_id}",
          user_id,
          updated_data
        )
        
        # Broadcast activity update
        broadcast_presence_update(project_id, :activity_changed, %{
          user_id: user_id,
          activity: updated_data.activity,
          status: updated_data.status
        })
        
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_call({:get_users, project_id}, _from, state) do
    users = 
      state.projects
      |> Map.get(project_id, %{})
      |> Map.values()
      |> Enum.map(&format_user_for_display/1)
    
    {:reply, users, state}
  end
  
  @impl true
  def handle_call({:get_user_info, project_id, user_id}, _from, state) do
    user_info = get_in(state, [:projects, project_id, user_id])
    {:reply, user_info, state}
  end
  
  @impl true
  def handle_info(:update_presence, state) do
    # Check for idle users
    now = System.system_time(:millisecond)
    
    state = 
      Enum.reduce(state.last_activity, state, fn {{project_id, user_id}, last_active}, acc ->
        if now - last_active > @idle_threshold do
          case get_in(acc, [:projects, project_id, user_id]) do
            nil -> 
              acc
              
            user_data ->
              if user_data.status != :idle do
                updated_data = Map.put(user_data, :status, :idle)
                
                # Update Phoenix Presence
                Presence.update(
                  self(),
                  "project:#{project_id}",
                  user_id,
                  updated_data
                )
                
                # Broadcast idle status
                broadcast_presence_update(project_id, :user_idle, %{
                  user_id: user_id,
                  status: :idle
                })
                
                put_in(acc, [:projects, project_id, user_id], updated_data)
              else
                acc
              end
          end
        else
          acc
        end
      end)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Handle process termination
    # Phoenix Presence will handle cleanup
    {:noreply, state}
  end
  
  # Private Functions
  
  defp generate_avatar_url(email) do
    # Generate Gravatar URL or use UI Avatars service
    hash = 
      :crypto.hash(:md5, String.downcase(email))
      |> Base.encode16(case: :lower)
    
    "https://www.gravatar.com/avatar/#{hash}?d=identicon&s=200"
  end
  
  defp assign_user_color(user_id) do
    # Assign a consistent color based on user ID
    colors = [
      "#FF6B6B", # Red
      "#4ECDC4", # Teal
      "#45B7D1", # Blue
      "#96CEB4", # Green
      "#FFEAA7", # Yellow
      "#DDA0DD", # Plum
      "#98D8C8", # Mint
      "#F7DC6F", # Gold
      "#BB8FCE", # Purple
      "#85C1E2"  # Sky Blue
    ]
    
    # Use hash to consistently assign same color to same user
    index = :erlang.phash2(user_id, length(colors))
    Enum.at(colors, index)
  end
  
  defp activity_to_status(:typing), do: :active
  defp activity_to_status(:reading), do: :active
  defp activity_to_status(:debugging), do: :active
  defp activity_to_status(:idle), do: :idle
  defp activity_to_status(:away), do: :away
  defp activity_to_status(_), do: :active
  
  defp format_user_for_display(user_data) do
    %{
      id: user_data.user_id,
      username: user_data.username,
      avatar_url: user_data.avatar_url,
      color: user_data.color,
      status: user_data.status,
      current_file: user_data.current_file,
      activity: user_data.activity.type,
      cursor_position: format_cursor_position(user_data.cursor),
      has_selection: user_data.selection != nil
    }
  end
  
  defp format_cursor_position(%{line: nil}), do: nil
  defp format_cursor_position(cursor) do
    "#{cursor.line}:#{cursor.column}"
  end
  
  defp broadcast_presence_update(project_id, event, data) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:presence",
      {event, data}
    )
  end
end
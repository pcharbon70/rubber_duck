defmodule RubberDuckWeb.Collaboration.SessionManager do
  @moduledoc """
  Manages collaborative coding sessions.

  Features:
  - Session creation and joining
  - Permission controls (owner, editor, viewer)
  - Session recording and replay
  - Invite management
  """

  use GenServer
  alias Phoenix.PubSub
  require Logger

  defmodule Session do
    @moduledoc """
    Represents a collaborative session.
    """
    defstruct [
      :id,
      :project_id,
      :name,
      :description,
      :owner_id,
      :created_at,
      :started_at,
      :ended_at,
      :is_recording,
      :recording_id,
      :participants,
      :settings,
      :state
    ]
  end

  defmodule Participant do
    @moduledoc """
    Represents a session participant.
    """
    defstruct [
      :user_id,
      :username,
      # :owner | :editor | :viewer
      :role,
      :joined_at,
      :left_at,
      :is_active,
      :permissions
    ]
  end

  defmodule SessionRecording do
    @moduledoc """
    Stores session recording data.
    """
    defstruct [
      :id,
      :session_id,
      :events,
      :duration,
      :file_snapshots,
      :created_at
    ]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a new collaborative session.
  """
  def create_session(project_id, owner_id, params) do
    GenServer.call(__MODULE__, {:create_session, project_id, owner_id, params})
  end

  @doc """
  Join an existing session.
  """
  def join_session(session_id, user_id, role \\ :viewer) do
    GenServer.call(__MODULE__, {:join_session, session_id, user_id, role})
  end

  @doc """
  Leave a session.
  """
  def leave_session(session_id, user_id) do
    GenServer.cast(__MODULE__, {:leave_session, session_id, user_id})
  end

  @doc """
  Update participant role.
  """
  def update_participant_role(session_id, user_id, new_role) do
    GenServer.call(__MODULE__, {:update_role, session_id, user_id, new_role})
  end

  @doc """
  Start recording a session.
  """
  def start_recording(session_id) do
    GenServer.call(__MODULE__, {:start_recording, session_id})
  end

  @doc """
  Stop recording a session.
  """
  def stop_recording(session_id) do
    GenServer.call(__MODULE__, {:stop_recording, session_id})
  end

  @doc """
  Get session details.
  """
  def get_session(session_id) do
    GenServer.call(__MODULE__, {:get_session, session_id})
  end

  @doc """
  List active sessions for a project.
  """
  def list_project_sessions(project_id) do
    GenServer.call(__MODULE__, {:list_project_sessions, project_id})
  end

  @doc """
  Generate a shareable invite link.
  """
  def generate_invite_link(session_id, role \\ :viewer, expires_in \\ 3600) do
    GenServer.call(__MODULE__, {:generate_invite, session_id, role, expires_in})
  end

  @doc """
  Join session via invite token.
  """
  def join_via_invite(invite_token, user_id) do
    GenServer.call(__MODULE__, {:join_via_invite, invite_token, user_id})
  end

  @doc """
  End a session.
  """
  def end_session(session_id, user_id) do
    GenServer.call(__MODULE__, {:end_session, session_id, user_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      # session_id => Session
      sessions: %{},
      # project_id => [session_ids]
      project_sessions: %{},
      # user_id => [session_ids]
      user_sessions: %{},
      # Recording data
      recordings: %{},
      # Invite tokens
      invites: %{},
      # Session event buffers for recording
      event_buffers: %{}
    }

    # Schedule cleanup of ended sessions
    # 5 minutes
    :timer.send_interval(300_000, :cleanup_ended_sessions)

    {:ok, state}
  end

  @impl true
  def handle_call({:create_session, project_id, owner_id, params}, _from, state) do
    session_id = generate_session_id()

    session = %Session{
      id: session_id,
      project_id: project_id,
      name: params[:name] || "Collaborative Session",
      description: params[:description],
      owner_id: owner_id,
      created_at: DateTime.utc_now(),
      started_at: DateTime.utc_now(),
      is_recording: params[:record] || false,
      participants: %{
        owner_id => %Participant{
          user_id: owner_id,
          username: get_username(owner_id),
          role: :owner,
          joined_at: DateTime.utc_now(),
          is_active: true,
          permissions: [:all]
        }
      },
      settings: %{
        max_participants: params[:max_participants] || 10,
        allow_guests: params[:allow_guests] || false,
        default_role: params[:default_role] || :viewer,
        enable_voice: params[:enable_voice] || false,
        enable_screen_share: params[:enable_screen_share] || false
      },
      state: :active
    }

    # Start recording if requested
    recording_id =
      if session.is_recording do
        start_session_recording(session_id)
      end

    session = %{session | recording_id: recording_id}

    # Update state
    state =
      state
      |> put_in([:sessions, session_id], session)
      |> update_in([:project_sessions, project_id], fn
        nil -> [session_id]
        ids -> [session_id | ids]
      end)
      |> update_in([:user_sessions, owner_id], fn
        nil -> [session_id]
        ids -> [session_id | ids]
      end)

    # Start collaboration services
    start_collaboration_services(session)

    # Broadcast session created
    broadcast_session_created(project_id, session)

    {:reply, {:ok, session}, state}
  end

  @impl true
  def handle_call({:join_session, session_id, user_id, role}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      %{state: :ended} ->
        {:reply, {:error, :session_ended}, state}

      session ->
        # Check if user can join
        case can_join_session?(session, user_id, role) do
          {:ok, final_role} ->
            participant = %Participant{
              user_id: user_id,
              username: get_username(user_id),
              role: final_role,
              joined_at: DateTime.utc_now(),
              is_active: true,
              permissions: role_permissions(final_role)
            }

            # Update session
            updated_session = put_in(session.participants[user_id], participant)

            state =
              state
              |> put_in([:sessions, session_id], updated_session)
              |> update_in([:user_sessions, user_id], fn
                nil -> [session_id]
                ids -> [session_id | ids] |> Enum.uniq()
              end)

            # Record join event
            record_event(state, session_id, :user_joined, %{
              user_id: user_id,
              role: final_role
            })

            # Broadcast user joined
            broadcast_user_joined(session.project_id, session_id, participant)

            {:reply, {:ok, updated_session}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:update_role, session_id, user_id, new_role}, {caller_pid, _}, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session ->
        # Get caller user_id from process metadata
        caller_user_id = get_caller_user_id(caller_pid)

        # Check permissions
        case can_update_role?(session, caller_user_id, user_id, new_role) do
          :ok ->
            # Update participant role
            participant = get_in(session, [:participants, user_id])
            updated_participant = %{participant | role: new_role, permissions: role_permissions(new_role)}

            updated_session = put_in(session.participants[user_id], updated_participant)
            state = put_in(state.sessions[session_id], updated_session)

            # Record event
            record_event(state, session_id, :role_updated, %{
              user_id: user_id,
              old_role: participant.role,
              new_role: new_role,
              updated_by: caller_user_id
            })

            # Broadcast role change
            broadcast_role_updated(session.project_id, session_id, user_id, new_role)

            {:reply, :ok, state}

          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:start_recording, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      %{is_recording: true} ->
        {:reply, {:error, :already_recording}, state}

      session ->
        recording_id = start_session_recording(session_id)

        updated_session = %{session | is_recording: true, recording_id: recording_id}

        state =
          state
          |> put_in([:sessions, session_id], updated_session)
          |> put_in([:event_buffers, session_id], [])

        # Broadcast recording started
        broadcast_recording_started(session.project_id, session_id)

        {:reply, {:ok, recording_id}, state}
    end
  end

  @impl true
  def handle_call({:stop_recording, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      %{is_recording: false} ->
        {:reply, {:error, :not_recording}, state}

      session ->
        # Save recording
        recording = save_session_recording(session, state)

        updated_session = %{session | is_recording: false}

        state =
          state
          |> put_in([:sessions, session_id], updated_session)
          |> update_in([:recordings], &Map.put(&1, recording.id, recording))
          |> update_in([:event_buffers], &Map.delete(&1, session_id))

        # Broadcast recording stopped
        broadcast_recording_stopped(session.project_id, session_id, recording.id)

        {:reply, {:ok, recording}, state}
    end
  end

  @impl true
  def handle_call({:generate_invite, session_id, role, expires_in}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      _session ->
        # Generate invite token
        token = generate_invite_token()
        expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

        invite = %{
          token: token,
          session_id: session_id,
          role: role,
          expires_at: expires_at,
          created_at: DateTime.utc_now()
        }

        state = put_in(state.invites[token], invite)

        # Generate link
        link = generate_invite_url(token)

        {:reply, {:ok, %{token: token, link: link, expires_at: expires_at}}, state}
    end
  end

  @impl true
  def handle_call({:join_via_invite, token, user_id}, _from, state) do
    case Map.get(state.invites, token) do
      nil ->
        {:reply, {:error, :invalid_invite}, state}

      %{expires_at: expires_at} = invite ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :gt do
          # Invite expired, remove it
          state = update_in(state.invites, &Map.delete(&1, token))
          {:reply, {:error, :invite_expired}, state}
        else
          # Join with invite role
          case handle_call({:join_session, invite.session_id, user_id, invite.role}, nil, state) do
            {:reply, {:ok, session}, new_state} ->
              # Remove single-use invite
              final_state = update_in(new_state.invites, &Map.delete(&1, token))
              {:reply, {:ok, session}, final_state}

            other ->
              other
          end
        end
    end
  end

  @impl true
  def handle_call({:get_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        {:reply, {:ok, format_session_for_display(session)}, state}
    end
  end

  @impl true
  def handle_call({:list_project_sessions, project_id}, _from, state) do
    session_ids = Map.get(state.project_sessions, project_id, [])

    sessions =
      session_ids
      |> Enum.map(fn id -> Map.get(state.sessions, id) end)
      |> Enum.filter(&(&1 != nil && &1.state == :active))
      |> Enum.map(&format_session_for_display/1)

    {:reply, {:ok, sessions}, state}
  end

  @impl true
  def handle_call({:end_session, session_id, user_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session ->
        # Check if user can end session
        if session.owner_id == user_id do
          # Stop recording if active
          {final_session, state} =
            if session.is_recording do
              {:reply, {:ok, _recording}, new_state} =
                handle_call({:stop_recording, session_id}, nil, state)

              {get_in(new_state, [:sessions, session_id]), new_state}
            else
              {session, state}
            end

          # Mark session as ended
          ended_session = %{final_session | state: :ended, ended_at: DateTime.utc_now()}

          state = put_in(state.sessions[session_id], ended_session)

          # Stop collaboration services
          stop_collaboration_services(session_id)

          # Broadcast session ended
          broadcast_session_ended(session.project_id, session_id)

          {:reply, :ok, state}
        else
          {:reply, {:error, :unauthorized}, state}
        end
    end
  end

  @impl true
  def handle_cast({:leave_session, session_id, user_id}, state) do
    case get_in(state, [:sessions, session_id, :participants, user_id]) do
      nil ->
        {:noreply, state}

      participant ->
        # Mark participant as inactive
        updated_participant = %{participant | is_active: false, left_at: DateTime.utc_now()}

        state = put_in(state, [:sessions, session_id, :participants, user_id], updated_participant)

        # Record leave event
        record_event(state, session_id, :user_left, %{user_id: user_id})

        # Get session for broadcast
        session = get_in(state, [:sessions, session_id])

        # Broadcast user left
        broadcast_user_left(session.project_id, session_id, user_id)

        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cleanup_ended_sessions, state) do
    # Remove sessions that ended more than 1 hour ago
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)

    {active_sessions, ended_sessions} =
      Enum.split_with(state.sessions, fn {_id, session} ->
        session.state != :ended ||
          DateTime.compare(session.ended_at || DateTime.utc_now(), cutoff) == :gt
      end)

    # Clean up ended sessions
    state = %{state | sessions: Map.new(active_sessions)}

    # Log cleanup
    if length(ended_sessions) > 0 do
      Logger.info("Cleaned up #{length(ended_sessions)} ended sessions")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:record_event, session_id, event}, state) do
    # Add event to buffer if recording
    case get_in(state, [:sessions, session_id]) do
      %{is_recording: true} ->
        state =
          update_in(state, [:event_buffers, session_id], fn
            nil -> [event]
            buffer -> [event | buffer]
          end)

        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  # Private Functions

  defp generate_session_id do
    "session_" <> Ecto.UUID.generate()
  end

  defp generate_invite_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64()
  end

  defp generate_invite_url(token) do
    base_url = Application.get_env(:rubber_duck, :base_url, "http://localhost:4000")
    "#{base_url}/collaborate/join?token=#{token}"
  end

  defp get_username(user_id) do
    # In real implementation, would fetch from database
    "User #{user_id}"
  end

  defp get_caller_user_id(_pid) do
    # In real implementation, would get from process metadata
    # For now, return a placeholder
    "system"
  end

  defp can_join_session?(session, user_id, requested_role) do
    cond do
      # Already in session
      Map.has_key?(session.participants, user_id) ->
        {:error, :already_in_session}

      # Session full
      map_size(session.participants) >= session.settings.max_participants ->
        {:error, :session_full}

      # Valid join
      true ->
        {:ok, requested_role}
    end
  end

  defp can_update_role?(session, caller_id, target_id, _new_role) do
    caller = get_in(session, [:participants, caller_id])

    cond do
      # Caller not in session
      caller == nil ->
        {:error, :not_in_session}

      # Only owner can change roles
      caller.role != :owner ->
        {:error, :unauthorized}

      # Can't change owner role
      target_id == session.owner_id ->
        {:error, :cannot_change_owner_role}

      # Valid role change
      true ->
        :ok
    end
  end

  defp role_permissions(:owner), do: [:all]
  defp role_permissions(:editor), do: [:read, :write, :chat, :voice]
  defp role_permissions(:viewer), do: [:read, :chat]

  defp start_collaboration_services(session) do
    # Start presence tracking
    RubberDuckWeb.Collaboration.PresenceTracker.track_user(
      session.project_id,
      session.owner_id,
      %{
        username: get_username(session.owner_id),
        # Would get from user data
        email: "owner@example.com",
        session_id: session.id
      }
    )

    # Additional service initialization would go here
  end

  defp stop_collaboration_services(session_id) do
    # Clean up collaboration services
    Logger.info("Stopping collaboration services for session #{session_id}")
  end

  defp start_session_recording(_session_id) do
    recording_id = Ecto.UUID.generate()
    # In real implementation, would initialize recording infrastructure
    recording_id
  end

  defp save_session_recording(session, state) do
    events = get_in(state, [:event_buffers, session.id]) || []

    %SessionRecording{
      id: session.recording_id || Ecto.UUID.generate(),
      session_id: session.id,
      # Restore chronological order
      events: Enum.reverse(events),
      duration:
        if(session.ended_at && session.started_at) do
          DateTime.diff(session.ended_at, session.started_at)
        else
          DateTime.diff(DateTime.utc_now(), session.started_at)
        end,
      created_at: DateTime.utc_now()
    }
  end

  defp record_event(state, session_id, event_type, data) do
    if get_in(state, [:sessions, session_id, :is_recording]) do
      event = %{
        type: event_type,
        data: data,
        timestamp: DateTime.utc_now()
      }

      send(self(), {:record_event, session_id, event})
    end
  end

  defp format_session_for_display(session) do
    %{
      id: session.id,
      name: session.name,
      description: session.description,
      owner_id: session.owner_id,
      participant_count: Enum.count(session.participants, fn {_, p} -> p.is_active end),
      participants: format_participants(session.participants),
      started_at: session.started_at,
      is_recording: session.is_recording,
      settings: session.settings,
      state: session.state
    }
  end

  defp format_participants(participants) do
    participants
    |> Enum.filter(fn {_, p} -> p.is_active end)
    |> Enum.map(fn {_, p} ->
      %{
        user_id: p.user_id,
        username: p.username,
        role: p.role,
        joined_at: p.joined_at
      }
    end)
  end

  # Broadcasting Functions

  defp broadcast_session_created(project_id, session) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:sessions",
      {:session_created, format_session_for_display(session)}
    )
  end

  defp broadcast_user_joined(_project_id, session_id, participant) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "session:#{session_id}",
      {:user_joined,
       %{
         user_id: participant.user_id,
         username: participant.username,
         role: participant.role
       }}
    )
  end

  defp broadcast_user_left(_project_id, session_id, user_id) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "session:#{session_id}",
      {:user_left, user_id}
    )
  end

  defp broadcast_role_updated(_project_id, session_id, user_id, new_role) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "session:#{session_id}",
      {:role_updated, %{user_id: user_id, role: new_role}}
    )
  end

  defp broadcast_recording_started(_project_id, session_id) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "session:#{session_id}",
      :recording_started
    )
  end

  defp broadcast_recording_stopped(_project_id, session_id, recording_id) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "session:#{session_id}",
      {:recording_stopped, recording_id}
    )
  end

  defp broadcast_session_ended(_project_id, session_id) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "session:#{session_id}",
      :session_ended
    )
  end
end

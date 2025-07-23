defmodule RubberDuckWeb.Collaboration.CollaborativeEditor do
  @moduledoc """
  Manages collaborative editing sessions with operational transformation.

  Implements a simplified OT algorithm for real-time collaborative text editing
  with conflict resolution and change attribution.
  """

  use GenServer
  alias Phoenix.PubSub
  require Logger

  @max_history_size 1000
  @snapshot_interval 100

  defmodule Operation do
    @moduledoc """
    Represents a text operation.
    """
    defstruct [
      :id,
      :user_id,
      # :insert | :delete
      :type,
      :position,
      # For insert
      :content,
      # For delete
      :length,
      :version,
      :timestamp
    ]
  end

  defmodule EditorState do
    @moduledoc """
    Represents the state of a collaborative document.
    """
    defstruct [
      :project_id,
      :file_path,
      :content,
      :version,
      :operations,
      :snapshots,
      :active_users,
      :pending_operations
    ]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Start a collaborative editing session for a file.
  """
  def start_session(project_id, file_path, initial_content) do
    spec = {
      __MODULE__,
      project_id: project_id,
      file_path: file_path,
      initial_content: initial_content,
      name: via_tuple(project_id, file_path)
    }

    DynamicSupervisor.start_child(
      RubberDuckWeb.Collaboration.EditorSupervisor,
      spec
    )
  end

  @doc """
  Apply an operation from a user.
  """
  def apply_operation(project_id, file_path, operation) do
    GenServer.call(
      via_tuple(project_id, file_path),
      {:apply_operation, operation}
    )
  end

  @doc """
  Get the current document state.
  """
  def get_document(project_id, file_path) do
    GenServer.call(
      via_tuple(project_id, file_path),
      :get_document
    )
  end

  @doc """
  Join a collaborative session.
  """
  def join_session(project_id, file_path, user_id) do
    GenServer.call(
      via_tuple(project_id, file_path),
      {:join_session, user_id}
    )
  end

  @doc """
  Leave a collaborative session.
  """
  def leave_session(project_id, file_path, user_id) do
    GenServer.cast(
      via_tuple(project_id, file_path),
      {:leave_session, user_id}
    )
  end

  @doc """
  Get operation history.
  """
  def get_history(project_id, file_path, limit \\ 50) do
    GenServer.call(
      via_tuple(project_id, file_path),
      {:get_history, limit}
    )
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    file_path = Keyword.fetch!(opts, :file_path)
    initial_content = Keyword.fetch!(opts, :initial_content)

    state = %EditorState{
      project_id: project_id,
      file_path: file_path,
      content: initial_content,
      version: 0,
      operations: [],
      snapshots: [%{version: 0, content: initial_content}],
      active_users: MapSet.new(),
      pending_operations: %{}
    }

    # Subscribe to presence updates
    PubSub.subscribe(RubberDuck.PubSub, "project:#{project_id}:presence")

    {:ok, state}
  end

  @impl true
  def handle_call({:apply_operation, operation}, _from, state) do
    case validate_operation(operation, state) do
      {:ok, validated_op} ->
        # Transform operation against concurrent operations
        transformed_op = transform_operation(validated_op, state)

        # Apply the operation
        new_content = apply_to_content(transformed_op, state.content)
        new_version = state.version + 1

        # Update operation with version
        final_op = %{transformed_op | version: new_version}

        # Update state
        new_state = %{
          state
          | content: new_content,
            version: new_version,
            operations: [final_op | state.operations] |> Enum.take(@max_history_size)
        }

        # Maybe create snapshot
        new_state = maybe_create_snapshot(new_state)

        # Broadcast to other users
        broadcast_operation(state.project_id, state.file_path, final_op)

        {:reply, {:ok, final_op}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_document, _from, state) do
    document = %{
      content: state.content,
      version: state.version,
      active_users: MapSet.to_list(state.active_users)
    }

    {:reply, {:ok, document}, state}
  end

  @impl true
  def handle_call({:join_session, user_id}, _from, state) do
    new_state = %{state | active_users: MapSet.put(state.active_users, user_id)}

    # Send current state to joining user
    join_data = %{
      content: state.content,
      version: state.version,
      active_users: MapSet.to_list(new_state.active_users)
    }

    broadcast_user_joined(state.project_id, state.file_path, user_id)

    {:reply, {:ok, join_data}, new_state}
  end

  @impl true
  def handle_call({:get_history, limit}, _from, state) do
    history =
      state.operations
      |> Enum.take(limit)
      |> Enum.map(&format_operation_for_display/1)

    {:reply, {:ok, history}, state}
  end

  @impl true
  def handle_cast({:leave_session, user_id}, state) do
    new_state = %{state | active_users: MapSet.delete(state.active_users, user_id)}

    broadcast_user_left(state.project_id, state.file_path, user_id)

    # If no users left, schedule cleanup
    if MapSet.size(new_state.active_users) == 0 do
      # 1 minute
      Process.send_after(self(), :maybe_cleanup, 60_000)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:maybe_cleanup, state) do
    if MapSet.size(state.active_users) == 0 do
      # Save final state before stopping
      save_document_state(state)
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:user_left, %{user_id: user_id}}, state) do
    # Handle user disconnection
    new_state = %{state | active_users: MapSet.delete(state.active_users, user_id)}

    {:noreply, new_state}
  end

  # Operational Transformation Functions

  defp validate_operation(operation, state) do
    cond do
      operation.type not in [:insert, :delete] ->
        {:error, :invalid_operation_type}

      operation.position < 0 or operation.position > String.length(state.content) ->
        {:error, :invalid_position}

      operation.type == :delete and operation.length <= 0 ->
        {:error, :invalid_delete_length}

      operation.type == :insert and (is_nil(operation.content) or operation.content == "") ->
        {:error, :empty_insert}

      true ->
        {:ok, operation}
    end
  end

  defp transform_operation(operation, state) do
    # Get operations that happened after the client's last known version
    concurrent_ops =
      state.operations
      |> Enum.take_while(fn op -> op.version > operation.version end)
      |> Enum.reverse()

    # Transform the operation against each concurrent operation
    Enum.reduce(concurrent_ops, operation, fn concurrent_op, op ->
      transform_pair(op, concurrent_op)
    end)
  end

  defp transform_pair(op1, op2) do
    # Simplified operational transformation
    # In a real implementation, this would be more complex

    case {op1.type, op2.type} do
      {:insert, :insert} ->
        if op2.position <= op1.position do
          %{op1 | position: op1.position + String.length(op2.content)}
        else
          op1
        end

      {:insert, :delete} ->
        if op2.position < op1.position do
          if op2.position + op2.length <= op1.position do
            %{op1 | position: op1.position - op2.length}
          else
            %{op1 | position: op2.position}
          end
        else
          op1
        end

      {:delete, :insert} ->
        if op2.position <= op1.position do
          %{op1 | position: op1.position + String.length(op2.content)}
        else
          op1
        end

      {:delete, :delete} ->
        if op2.position <= op1.position do
          %{op1 | position: max(op2.position, op1.position - op2.length)}
        else
          op1
        end
    end
  end

  defp apply_to_content(operation, content) do
    case operation.type do
      :insert ->
        {before, after_} = String.split_at(content, operation.position)
        before <> operation.content <> after_

      :delete ->
        {before, rest} = String.split_at(content, operation.position)
        {_deleted, after_} = String.split_at(rest, operation.length)
        before <> after_
    end
  end

  defp maybe_create_snapshot(state) do
    if rem(state.version, @snapshot_interval) == 0 do
      snapshot = %{
        version: state.version,
        content: state.content,
        timestamp: DateTime.utc_now()
      }

      %{state | snapshots: [snapshot | state.snapshots] |> Enum.take(10)}
    else
      state
    end
  end

  defp format_operation_for_display(operation) do
    %{
      id: operation.id,
      user_id: operation.user_id,
      type: operation.type,
      position: operation.position,
      content: operation.content,
      length: operation.length,
      version: operation.version,
      timestamp: operation.timestamp
    }
  end

  defp save_document_state(state) do
    # In a real implementation, this would save to database
    Logger.info("Saving document state for #{state.file_path}")
  end

  # Broadcasting Functions

  defp broadcast_operation(project_id, file_path, operation) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:editor:#{file_path}",
      {:operation_applied, operation}
    )
  end

  defp broadcast_user_joined(project_id, file_path, user_id) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:editor:#{file_path}",
      {:user_joined_editor, user_id}
    )
  end

  defp broadcast_user_left(project_id, file_path, user_id) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:editor:#{file_path}",
      {:user_left_editor, user_id}
    )
  end

  # Registry Functions

  defp via_tuple(project_id, file_path) do
    {:via, Registry, {RubberDuckWeb.Collaboration.EditorRegistry, {project_id, file_path}}}
  end
end

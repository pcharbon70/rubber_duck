defmodule RubberDuckWeb.Collaboration.SharedSelections do
  @moduledoc """
  Manages shared text selections and annotations in collaborative sessions.

  Features:
  - Multi-user selection display with user colors
  - Annotation threads on selections
  - Highlighting coordination
  - Comment management
  """

  use GenServer
  alias Phoenix.PubSub
  require Logger

  defmodule Selection do
    @moduledoc """
    Represents a user's text selection.
    """
    defstruct [
      :id,
      :user_id,
      :file_path,
      :start_line,
      :start_column,
      :end_line,
      :end_column,
      :text,
      :color,
      :created_at,
      :annotations
    ]
  end

  defmodule Annotation do
    @moduledoc """
    Represents a comment or note on a selection.
    """
    defstruct [
      :id,
      :selection_id,
      :user_id,
      :content,
      # :comment | :suggestion | :question
      :type,
      :resolved,
      :created_at,
      :updated_at,
      :replies
    ]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a new selection.
  """
  def create_selection(project_id, user_id, selection_params) do
    GenServer.call(__MODULE__, {:create_selection, project_id, user_id, selection_params})
  end

  @doc """
  Update an existing selection.
  """
  def update_selection(project_id, selection_id, updates) do
    GenServer.call(__MODULE__, {:update_selection, project_id, selection_id, updates})
  end

  @doc """
  Remove a selection.
  """
  def remove_selection(project_id, selection_id) do
    GenServer.cast(__MODULE__, {:remove_selection, project_id, selection_id})
  end

  @doc """
  Add an annotation to a selection.
  """
  def add_annotation(project_id, selection_id, user_id, annotation_params) do
    GenServer.call(__MODULE__, {:add_annotation, project_id, selection_id, user_id, annotation_params})
  end

  @doc """
  Reply to an annotation.
  """
  def reply_to_annotation(project_id, annotation_id, user_id, content) do
    GenServer.call(__MODULE__, {:reply_to_annotation, project_id, annotation_id, user_id, content})
  end

  @doc """
  Resolve an annotation thread.
  """
  def resolve_annotation(project_id, annotation_id) do
    GenServer.cast(__MODULE__, {:resolve_annotation, project_id, annotation_id})
  end

  @doc """
  Get all selections for a file.
  """
  def get_file_selections(project_id, file_path) do
    GenServer.call(__MODULE__, {:get_file_selections, project_id, file_path})
  end

  @doc """
  Get selections by user.
  """
  def get_user_selections(project_id, user_id) do
    GenServer.call(__MODULE__, {:get_user_selections, project_id, user_id})
  end

  @doc """
  Clear all selections for a user (e.g., on disconnect).
  """
  def clear_user_selections(project_id, user_id) do
    GenServer.cast(__MODULE__, {:clear_user_selections, project_id, user_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      # project_id => %{selection_id => Selection}
      selections: %{},
      # project_id => %{annotation_id => Annotation}
      annotations: %{},
      # Quick lookup indices
      # {project_id, user_id} => [selection_ids]
      user_selections: %{},
      # {project_id, file_path} => [selection_ids]
      file_selections: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:create_selection, project_id, user_id, params}, _from, state) do
    selection_id = generate_id()

    # Get user color from presence
    color = get_user_color(project_id, user_id)

    selection = %Selection{
      id: selection_id,
      user_id: user_id,
      file_path: params.file_path,
      start_line: params.start_line,
      start_column: params.start_column,
      end_line: params.end_line,
      end_column: params.end_column,
      text: params.text,
      color: color,
      created_at: DateTime.utc_now(),
      annotations: []
    }

    # Update state
    state =
      state
      |> put_in([:selections, project_id, selection_id], selection)
      |> update_in([:user_selections, {project_id, user_id}], fn
        nil -> [selection_id]
        ids -> [selection_id | ids]
      end)
      |> update_in([:file_selections, {project_id, params.file_path}], fn
        nil -> [selection_id]
        ids -> [selection_id | ids]
      end)

    # Broadcast new selection
    broadcast_selection_created(project_id, selection)

    {:reply, {:ok, selection}, state}
  end

  @impl true
  def handle_call({:update_selection, project_id, selection_id, updates}, _from, state) do
    case get_in(state, [:selections, project_id, selection_id]) do
      nil ->
        {:reply, {:error, :not_found}, state}

      selection ->
        # Update selection
        updated_selection = struct(selection, updates)

        state = put_in(state, [:selections, project_id, selection_id], updated_selection)

        # Broadcast update
        broadcast_selection_updated(project_id, updated_selection)

        {:reply, {:ok, updated_selection}, state}
    end
  end

  @impl true
  def handle_call({:add_annotation, project_id, selection_id, user_id, params}, _from, state) do
    case get_in(state, [:selections, project_id, selection_id]) do
      nil ->
        {:reply, {:error, :selection_not_found}, state}

      _selection ->
        annotation_id = generate_id()

        annotation = %Annotation{
          id: annotation_id,
          selection_id: selection_id,
          user_id: user_id,
          content: params.content,
          type: params[:type] || :comment,
          resolved: false,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          replies: []
        }

        # Update state
        state =
          state
          |> put_in([:annotations, project_id, annotation_id], annotation)
          |> update_in([:selections, project_id, selection_id, :annotations], fn annotations ->
            [annotation_id | annotations]
          end)

        # Broadcast new annotation
        broadcast_annotation_added(project_id, selection_id, annotation)

        {:reply, {:ok, annotation}, state}
    end
  end

  @impl true
  def handle_call({:reply_to_annotation, project_id, annotation_id, user_id, content}, _from, state) do
    case get_in(state, [:annotations, project_id, annotation_id]) do
      nil ->
        {:reply, {:error, :annotation_not_found}, state}

      annotation ->
        reply = %{
          id: generate_id(),
          user_id: user_id,
          content: content,
          created_at: DateTime.utc_now()
        }

        # Add reply
        updated_annotation = update_in(annotation.replies, &(&1 ++ [reply]))

        state = put_in(state, [:annotations, project_id, annotation_id], updated_annotation)

        # Broadcast reply
        broadcast_annotation_reply(project_id, annotation_id, reply)

        {:reply, {:ok, reply}, state}
    end
  end

  @impl true
  def handle_call({:get_file_selections, project_id, file_path}, _from, state) do
    selection_ids = get_in(state, [:file_selections, {project_id, file_path}]) || []

    selections =
      selection_ids
      |> Enum.map(fn id -> get_in(state, [:selections, project_id, id]) end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.map(&enrich_selection_with_annotations(&1, state, project_id))

    {:reply, {:ok, selections}, state}
  end

  @impl true
  def handle_call({:get_user_selections, project_id, user_id}, _from, state) do
    selection_ids = get_in(state, [:user_selections, {project_id, user_id}]) || []

    selections =
      selection_ids
      |> Enum.map(fn id -> get_in(state, [:selections, project_id, id]) end)
      |> Enum.filter(&(&1 != nil))

    {:reply, {:ok, selections}, state}
  end

  @impl true
  def handle_cast({:remove_selection, project_id, selection_id}, state) do
    case get_in(state, [:selections, project_id, selection_id]) do
      nil ->
        {:noreply, state}

      selection ->
        # Remove from all indices
        state =
          state
          |> update_in([:selections, project_id], &Map.delete(&1, selection_id))
          |> update_in([:user_selections, {project_id, selection.user_id}], fn ids ->
            List.delete(ids || [], selection_id)
          end)
          |> update_in([:file_selections, {project_id, selection.file_path}], fn ids ->
            List.delete(ids || [], selection_id)
          end)

        # Also remove associated annotations
        state =
          Enum.reduce(selection.annotations, state, fn annotation_id, acc ->
            update_in(acc, [:annotations, project_id], &Map.delete(&1 || %{}, annotation_id))
          end)

        # Broadcast removal
        broadcast_selection_removed(project_id, selection_id)

        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:resolve_annotation, project_id, annotation_id}, state) do
    case get_in(state, [:annotations, project_id, annotation_id]) do
      nil ->
        {:noreply, state}

      annotation ->
        updated_annotation = %{annotation | resolved: true, updated_at: DateTime.utc_now()}

        state = put_in(state, [:annotations, project_id, annotation_id], updated_annotation)

        # Broadcast resolution
        broadcast_annotation_resolved(project_id, annotation_id)

        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:clear_user_selections, project_id, user_id}, state) do
    selection_ids = get_in(state, [:user_selections, {project_id, user_id}]) || []

    # Remove each selection
    state =
      Enum.reduce(selection_ids, state, fn selection_id, acc ->
        case get_in(acc, [:selections, project_id, selection_id]) do
          nil ->
            acc

          selection ->
            acc
            |> update_in([:selections, project_id], &Map.delete(&1, selection_id))
            |> update_in([:file_selections, {project_id, selection.file_path}], fn ids ->
              List.delete(ids || [], selection_id)
            end)
        end
      end)
      |> put_in([:user_selections, {project_id, user_id}], [])

    # Broadcast user selections cleared
    broadcast_user_selections_cleared(project_id, user_id)

    {:noreply, state}
  end

  # Private Functions

  defp generate_id do
    Ecto.UUID.generate()
  end

  defp get_user_color(_project_id, _user_id) do
    # In real implementation, would get from presence tracker
    # For now, return a default
    "#4ECDC4"
  end

  defp enrich_selection_with_annotations(selection, state, project_id) do
    annotations =
      selection.annotations
      |> Enum.map(fn ann_id -> get_in(state, [:annotations, project_id, ann_id]) end)
      |> Enum.filter(&(&1 != nil))

    %{selection | annotations: annotations}
  end

  # Broadcasting Functions

  defp broadcast_selection_created(project_id, selection) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:selections",
      {:selection_created, selection}
    )
  end

  defp broadcast_selection_updated(project_id, selection) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:selections",
      {:selection_updated, selection}
    )
  end

  defp broadcast_selection_removed(project_id, selection_id) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:selections",
      {:selection_removed, selection_id}
    )
  end

  defp broadcast_annotation_added(project_id, selection_id, annotation) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:selections",
      {:annotation_added, selection_id, annotation}
    )
  end

  defp broadcast_annotation_reply(project_id, annotation_id, reply) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:selections",
      {:annotation_reply, annotation_id, reply}
    )
  end

  defp broadcast_annotation_resolved(project_id, annotation_id) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:selections",
      {:annotation_resolved, annotation_id}
    )
  end

  defp broadcast_user_selections_cleared(project_id, user_id) do
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{project_id}:selections",
      {:user_selections_cleared, user_id}
    )
  end
end

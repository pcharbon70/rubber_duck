defmodule RubberDuck.Jido.Agents.WorkflowPersistence do
  @moduledoc """
  Persistence layer for workflow state management.
  
  This module provides:
  - Workflow state serialization/deserialization
  - Checkpoint management during workflow execution
  - Recovery mechanisms for halted workflows
  - Version management for workflow definitions
  - Integration with agent state persistence
  
  ## Storage Backends
  
  The persistence layer supports multiple storage backends:
  - ETS (default, in-memory)
  - DETS (file-based)
  - PostgreSQL (via Ecto, future)
  
  ## Example
  
      # Save workflow state
      {:ok, checkpoint_id} = WorkflowPersistence.save_checkpoint(
        workflow_id,
        reactor_state,
        metadata
      )
      
      # Load workflow state
      {:ok, state} = WorkflowPersistence.load_checkpoint(workflow_id)
      
      # List checkpoints
      {:ok, checkpoints} = WorkflowPersistence.list_checkpoints(workflow_id)
  """
  
  use GenServer
  require Logger
  
  @table_name :workflow_persistence
  @checkpoint_table :workflow_checkpoints
  @version_table :workflow_versions
  
  @type workflow_id :: String.t()
  @type checkpoint_id :: String.t()
  @type version_id :: String.t()
  
  @type workflow_state :: %{
          workflow_id: workflow_id(),
          module: module(),
          reactor_state: any(),
          context: map(),
          metadata: map(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }
  
  @type checkpoint :: %{
          id: checkpoint_id(),
          workflow_id: workflow_id(),
          step_name: String.t(),
          state: any(),
          metadata: map(),
          created_at: DateTime.t()
        }
  
  # Client API
  
  @doc """
  Starts the persistence service.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Saves the current workflow state.
  """
  def save_workflow_state(workflow_id, module, reactor_state, context, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:save_state, workflow_id, module, reactor_state, context, metadata})
  end
  
  @doc """
  Loads a workflow state.
  """
  def load_workflow_state(workflow_id) do
    GenServer.call(__MODULE__, {:load_state, workflow_id})
  end
  
  @doc """
  Deletes a workflow state.
  """
  def delete_workflow_state(workflow_id) do
    GenServer.call(__MODULE__, {:delete_state, workflow_id})
  end
  
  @doc """
  Creates a checkpoint during workflow execution.
  """
  def save_checkpoint(workflow_id, step_name, state, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:save_checkpoint, workflow_id, step_name, state, metadata})
  end
  
  @doc """
  Loads the latest checkpoint for a workflow.
  """
  def load_checkpoint(workflow_id) do
    GenServer.call(__MODULE__, {:load_checkpoint, workflow_id})
  end
  
  @doc """
  Loads a specific checkpoint.
  """
  def load_checkpoint(workflow_id, checkpoint_id) do
    GenServer.call(__MODULE__, {:load_checkpoint, workflow_id, checkpoint_id})
  end
  
  @doc """
  Lists all checkpoints for a workflow.
  """
  def list_checkpoints(workflow_id) do
    GenServer.call(__MODULE__, {:list_checkpoints, workflow_id})
  end
  
  @doc """
  Saves a workflow version.
  """
  def save_version(module, version, definition) do
    GenServer.call(__MODULE__, {:save_version, module, version, definition})
  end
  
  @doc """
  Gets the current version of a workflow module.
  """
  def get_current_version(module) do
    GenServer.call(__MODULE__, {:get_version, module})
  end
  
  @doc """
  Lists all persisted workflows.
  """
  def list_workflows(opts \\ []) do
    GenServer.call(__MODULE__, {:list_workflows, opts})
  end
  
  @doc """
  Cleans up old workflow states and checkpoints.
  """
  def cleanup(older_than_days \\ 7) do
    GenServer.call(__MODULE__, {:cleanup, older_than_days})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Create ETS tables
    :ets.new(@table_name, [:set, :protected, :named_table])
    :ets.new(@checkpoint_table, [:ordered_set, :protected, :named_table])
    :ets.new(@version_table, [:set, :protected, :named_table])
    
    # Schedule periodic cleanup if configured
    if opts[:auto_cleanup] do
      schedule_cleanup(opts[:cleanup_interval] || :timer.hours(24))
    end
    
    state = %{
      backend: opts[:backend] || :ets,
      auto_cleanup: opts[:auto_cleanup] || false,
      cleanup_interval: opts[:cleanup_interval],
      compression: opts[:compression] || false
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:save_state, workflow_id, module, reactor_state, context, metadata}, _from, state) do
    workflow_state = %{
      workflow_id: workflow_id,
      module: module,
      reactor_state: reactor_state,
      context: context,
      metadata: metadata,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
    
    # Serialize if needed
    serialized = if state.compression do
      compress_state(workflow_state)
    else
      workflow_state
    end
    
    # Save to backend
    result = case state.backend do
      :ets ->
        :ets.insert(@table_name, {workflow_id, serialized})
        {:ok, workflow_id}
        
      :dets ->
        # TODO: Implement DETS backend
        {:error, :not_implemented}
        
      _ ->
        {:error, :unknown_backend}
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:load_state, workflow_id}, _from, state) do
    result = case state.backend do
      :ets ->
        case :ets.lookup(@table_name, workflow_id) do
          [{^workflow_id, serialized}] ->
            workflow_state = if state.compression do
              decompress_state(serialized)
            else
              serialized
            end
            {:ok, workflow_state}
            
          [] ->
            {:error, :not_found}
        end
        
      _ ->
        {:error, :unknown_backend}
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:delete_state, workflow_id}, _from, state) do
    # Delete workflow state
    :ets.delete(@table_name, workflow_id)
    
    # Delete associated checkpoints
    checkpoints = :ets.match(@checkpoint_table, {{workflow_id, :_}, :_})
    Enum.each(checkpoints, fn [{key, _}] ->
      :ets.delete(@checkpoint_table, key)
    end)
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:save_checkpoint, workflow_id, step_name, checkpoint_state, metadata}, _from, state) do
    checkpoint_id = generate_checkpoint_id()
    
    checkpoint = %{
      id: checkpoint_id,
      workflow_id: workflow_id,
      step_name: step_name,
      state: checkpoint_state,
      metadata: metadata,
      created_at: DateTime.utc_now()
    }
    
    # Use composite key for ordering
    key = {workflow_id, DateTime.utc_now()}
    
    :ets.insert(@checkpoint_table, {key, checkpoint})
    
    {:reply, {:ok, checkpoint_id}, state}
  end
  
  @impl true
  def handle_call({:load_checkpoint, workflow_id}, _from, state) do
    # Get the latest checkpoint
    checkpoints = :ets.match_object(@checkpoint_table, {{workflow_id, :_}, :_})
    
    result = case checkpoints do
      [] ->
        {:error, :no_checkpoints}
        
      points ->
        # Sort by timestamp (in key) and get the latest
        {_key, latest} = points
        |> Enum.sort_by(fn {{_wid, timestamp}, _} -> timestamp end, {:desc, DateTime})
        |> List.first()
        
        {:ok, latest}
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:load_checkpoint, workflow_id, checkpoint_id}, _from, state) do
    # Find specific checkpoint
    checkpoints = :ets.match_object(@checkpoint_table, {{workflow_id, :_}, :_})
    
    result = checkpoints
    |> Enum.find(fn {_key, checkpoint} -> checkpoint.id == checkpoint_id end)
    |> case do
      nil -> {:error, :not_found}
      {_key, checkpoint} -> {:ok, checkpoint}
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:list_checkpoints, workflow_id}, _from, state) do
    checkpoints = :ets.match_object(@checkpoint_table, {{workflow_id, :_}, :_})
    |> Enum.map(fn {_key, checkpoint} -> checkpoint end)
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    
    {:reply, {:ok, checkpoints}, state}
  end
  
  @impl true
  def handle_call({:save_version, module, version, definition}, _from, state) do
    version_info = %{
      module: module,
      version: version,
      definition: definition,
      created_at: DateTime.utc_now()
    }
    
    :ets.insert(@version_table, {module, version_info})
    
    {:reply, {:ok, version}, state}
  end
  
  @impl true
  def handle_call({:get_version, module}, _from, state) do
    result = case :ets.lookup(@version_table, module) do
      [{^module, version_info}] -> {:ok, version_info}
      [] -> {:error, :no_version}
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:list_workflows, opts}, _from, state) do
    # Get all workflows
    workflows = :ets.tab2list(@table_name)
    |> Enum.map(fn {_id, workflow} -> workflow end)
    
    # Apply filters
    filtered = workflows
    |> filter_by_status(opts[:status])
    |> filter_by_module(opts[:module])
    |> filter_by_date(opts[:since], opts[:until])
    
    # Sort
    sorted = case opts[:order_by] do
      :created_at -> Enum.sort_by(filtered, & &1.created_at, {:desc, DateTime})
      :updated_at -> Enum.sort_by(filtered, & &1.updated_at, {:desc, DateTime})
      _ -> filtered
    end
    
    # Paginate
    paginated = if opts[:limit] do
      Enum.take(sorted, opts[:limit])
    else
      sorted
    end
    
    {:reply, {:ok, paginated}, state}
  end
  
  @impl true
  def handle_call({:cleanup, days}, _from, state) do
    cutoff_date = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)
    
    # Clean up old workflow states
    old_workflows = :ets.select(@table_name, [
      {
        {:_, %{updated_at: :"$1", _: :_}},
        [{:<, :"$1", cutoff_date}],
        [:"$_"]
      }
    ])
    
    deleted_count = length(old_workflows)
    Enum.each(old_workflows, fn {id, _} ->
      :ets.delete(@table_name, id)
    end)
    
    # Clean up old checkpoints
    old_checkpoints = :ets.select(@checkpoint_table, [
      {
        {{:_, :"$1"}, %{created_at: :"$2", _: :_}},
        [{:<, :"$2", cutoff_date}],
        [:"$_"]
      }
    ])
    
    checkpoint_count = length(old_checkpoints)
    Enum.each(old_checkpoints, fn {key, _} ->
      :ets.delete(@checkpoint_table, key)
    end)
    
    Logger.info("Cleaned up #{deleted_count} workflows and #{checkpoint_count} checkpoints")
    
    {:reply, {:ok, %{workflows: deleted_count, checkpoints: checkpoint_count}}, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Perform automatic cleanup
    {:ok, _} = cleanup()
    
    # Schedule next cleanup
    schedule_cleanup(state.cleanup_interval)
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp generate_checkpoint_id do
    "cp_" <> :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end
  
  defp compress_state(state) do
    # Simple compression using :erlang.term_to_binary with compression
    :erlang.term_to_binary(state, [:compressed])
  end
  
  defp decompress_state(compressed) do
    :erlang.binary_to_term(compressed)
  end
  
  defp filter_by_status(workflows, nil), do: workflows
  defp filter_by_status(workflows, status) do
    Enum.filter(workflows, & &1.metadata[:status] == status)
  end
  
  defp filter_by_module(workflows, nil), do: workflows
  defp filter_by_module(workflows, module) do
    Enum.filter(workflows, & &1.module == module)
  end
  
  defp filter_by_date(workflows, nil, nil), do: workflows
  defp filter_by_date(workflows, since, until) do
    workflows
    |> then(fn wfs ->
      if since do
        Enum.filter(wfs, &DateTime.compare(&1.created_at, since) != :lt)
      else
        wfs
      end
    end)
    |> then(fn wfs ->
      if until do
        Enum.filter(wfs, &DateTime.compare(&1.created_at, until) != :gt)
      else
        wfs
      end
    end)
  end
end
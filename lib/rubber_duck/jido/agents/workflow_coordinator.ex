defmodule RubberDuck.Jido.Agents.WorkflowCoordinator do
  @moduledoc """
  Coordinates the execution of Reactor workflows with the Jido agent system.
  
  This module acts as the bridge between Reactor's workflow engine and our
  agent infrastructure, handling:
  
  - Workflow execution with agent context
  - State persistence and recovery
  - Telemetry integration
  - Signal translation between workflows and agents
  
  ## Example
  
      # Execute a simple workflow
      {:ok, result} = WorkflowCoordinator.execute_workflow(
        SimplePipeline,
        %{data: %{items: [1, 2, 3]}},
        context: %{user_id: "123"}
      )
      
      # Execute with persistence
      {:ok, workflow_id} = WorkflowCoordinator.start_workflow(
        TransactionalWorkflow,
        %{transaction_data: data},
        persist: true
      )
      
      # Resume a halted workflow
      {:ok, result} = WorkflowCoordinator.resume_workflow(workflow_id)
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Jido.Agents.WorkflowPersistenceAsh, as: WorkflowPersistence
  alias RubberDuck.Workflows.Workflow
  
  
  @type workflow_id :: String.t()
  @type workflow_state :: %{
          id: workflow_id(),
          module: module(),
          status: :running | :completed | :halted | :failed,
          reactor_state: any(),
          context: map(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          error: any() | nil
        }
  
  # Client API
  
  @doc """
  Starts the workflow coordinator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Executes a workflow synchronously.
  
  ## Options
  
  - `:context` - Additional context to pass to the workflow
  - `:timeout` - Maximum execution time (default: 30000ms)
  - `:telemetry` - Whether to emit telemetry events (default: true)
  """
  def execute_workflow(workflow_module, inputs, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_workflow, workflow_module, inputs, opts}, 
      Keyword.get(opts, :timeout, 30_000))
  end
  
  @doc """
  Starts a workflow asynchronously.
  
  ## Options
  
  - `:context` - Additional context to pass to the workflow
  - `:persist` - Whether to persist workflow state (default: false)
  - `:telemetry` - Whether to emit telemetry events (default: true)
  """
  def start_workflow(workflow_module, inputs, opts \\ []) do
    GenServer.call(__MODULE__, {:start_workflow, workflow_module, inputs, opts})
  end
  
  @doc """
  Gets the status of a running workflow.
  """
  def get_workflow_status(workflow_id) do
    GenServer.call(__MODULE__, {:get_status, workflow_id})
  end
  
  @doc """
  Resumes a halted workflow.
  """
  def resume_workflow(workflow_id, additional_inputs \\ %{}) do
    GenServer.call(__MODULE__, {:resume_workflow, workflow_id, additional_inputs})
  end
  
  @doc """
  Cancels a running workflow.
  """
  def cancel_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:cancel_workflow, workflow_id})
  end
  
  @doc """
  Lists all active workflows.
  """
  def list_workflows do
    GenServer.call(__MODULE__, :list_workflows)
  end
  
  @doc """
  Update workflow parameters for running workflows.
  """
  def update_workflow(workflow_id, updates) do
    GenServer.call(__MODULE__, {:update_workflow, workflow_id, updates})
  end
  
  @doc """
  Get workflow execution logs.
  """
  def get_workflow_logs(workflow_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_workflow_logs, workflow_id, opts})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Persistence is now handled by Ash resources, no need to start a service
    
    # Start periodic cleanup
    if opts[:cleanup_interval] do
      Process.send_after(self(), :cleanup, opts[:cleanup_interval])
    end
    
    state = %{
      persist_enabled: Keyword.get(opts, :persist, true), # Default to true now
      telemetry_enabled: Keyword.get(opts, :telemetry, true),
      cleanup_interval: opts[:cleanup_interval]
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:execute_workflow, module, inputs, opts}, _from, state) do
    workflow_id = generate_workflow_id()
    context = build_context(workflow_id, opts)
    
    # Emit start event
    if state.telemetry_enabled do
      :telemetry.execute(
        [:rubber_duck, :workflow, :start],
        %{count: 1},
        %{workflow_id: workflow_id, module: module}
      )
    end
    
    # Execute workflow
    start_time = System.monotonic_time(:microsecond)
    
    result = case Reactor.run(module, inputs, context, opts) do
      {:ok, result} ->
        duration = System.monotonic_time(:microsecond) - start_time
        
        if state.telemetry_enabled do
          :telemetry.execute(
            [:rubber_duck, :workflow, :complete],
            %{duration: duration},
            %{workflow_id: workflow_id, module: module, status: :success}
          )
        end
        
        {:ok, result}
        
      {:halted, reactor_state} ->
        duration = System.monotonic_time(:microsecond) - start_time
        
        # Store halted state if persistence is enabled
        if state.persist_enabled do
          WorkflowPersistence.save_workflow_state(
            workflow_id, 
            module, 
            reactor_state, 
            context,
            %{status: :halted}
          )
        end
        
        if state.telemetry_enabled do
          :telemetry.execute(
            [:rubber_duck, :workflow, :halt],
            %{duration: duration},
            %{workflow_id: workflow_id, module: module}
          )
        end
        
        {:halted, workflow_id}
        
      {:error, errors} ->
        duration = System.monotonic_time(:microsecond) - start_time
        
        if state.telemetry_enabled do
          :telemetry.execute(
            [:rubber_duck, :workflow, :error],
            %{duration: duration, error_count: length(errors)},
            %{workflow_id: workflow_id, module: module, errors: errors}
          )
        end
        
        {:error, errors}
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:start_workflow, module, inputs, opts}, _from, state) do
    workflow_id = generate_workflow_id()
    
    # Create workflow record in database
    case create_workflow_record(workflow_id, module, inputs, opts) do
      {:ok, _workflow} ->
        # Start workflow asynchronously
        Task.start_link(fn ->
          execute_workflow_async(workflow_id, module, inputs, opts, state)
        end)
        
        {:reply, {:ok, workflow_id}, state}
        
      {:error, error} ->
        Logger.error("Failed to create workflow record: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end
  
  @impl true
  def handle_call({:get_status, workflow_id}, _from, state) do
    status = case WorkflowPersistence.load_workflow_state(workflow_id) do
      {:ok, workflow} -> 
        {:ok, %{
          id: workflow.workflow_id,
          module: workflow.module,
          status: workflow.status,
          started_at: workflow.created_at,
          completed_at: workflow.completed_at,
          error: workflow.error,
          metadata: workflow.metadata
        }}
      {:error, _} -> 
        {:error, :not_found}
    end
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_call({:resume_workflow, workflow_id, additional_inputs}, _from, state) do
    if state.persist_enabled do
      case WorkflowPersistence.load_workflow_state(workflow_id) do
        {:ok, %{metadata: %{status: :halted}, reactor_state: reactor_state, context: context}} ->
          # Resume execution
          Task.start_link(fn ->
            resume_workflow_async(workflow_id, reactor_state, additional_inputs, context, state)
          end)
          
          # Update status in database
          update_workflow_status(workflow_id, :running, %{
            resumed_at: DateTime.utc_now()
          })
          
          {:reply, :ok, state}
          
        {:ok, %{metadata: %{status: status}}} ->
          {:reply, {:error, {:invalid_status, status}}, state}
          
        {:error, _} ->
          {:reply, {:error, :not_found}, state}
      end
    else
      {:reply, {:error, :persistence_not_enabled}, state}
    end
  end
  
  @impl true
  def handle_call({:cancel_workflow, _workflow_id}, _from, state) do
    # TODO: Implement workflow cancellation
    # This would require Reactor to support cancellation
    {:reply, {:error, :not_implemented}, state}
  end
  
  @impl true
  def handle_call(:list_workflows, _from, state) do
    workflows = case Workflow
                     |> Ash.read() do
      {:ok, workflows} ->
        workflows
        |> Enum.filter(fn w -> w.status in [:running, :halted] end)
        |> Enum.map(fn w ->
          %{
            id: w.workflow_id,
            module: w.module,
            status: w.status,
            started_at: w.created_at,
            metadata: w.metadata
          }
        end)
      {:error, _} -> []
    end
    
    {:reply, workflows, state}
  end
  
  @impl true
  def handle_call({:update_workflow, workflow_id, updates}, _from, state) do
    case WorkflowPersistence.load_workflow_state(workflow_id) do
      {:ok, workflow} ->
        # Update workflow in database
        attrs = %{
          context: Map.merge(workflow.context, Map.get(updates, :context, %{})),
          metadata: Map.merge(workflow.metadata, Map.get(updates, :metadata, %{}))
        }
        
        case workflow
             |> Ash.Changeset.for_update(:update, attrs)
             |> Ash.update() do
          {:ok, updated_workflow} ->
            {:reply, {:ok, format_workflow(updated_workflow)}, state}
          {:error, error} ->
            {:reply, {:error, error}, state}
        end
        
      {:error, _} ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:get_workflow_logs, workflow_id, opts}, _from, state) do
    case WorkflowPersistence.load_workflow_state(workflow_id) do
      {:ok, _workflow} ->
        # Fetch logs from telemetry or logging system
        # For now, return mock logs
        limit = Keyword.get(opts, :limit, 100)
        offset = Keyword.get(opts, :offset, 0)
        level = Keyword.get(opts, :level, "info")
        
        logs = generate_mock_logs(workflow_id, limit, offset, level)
        {:reply, {:ok, logs}, state}
        
      {:error, _} ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Clean up completed workflows older than configured time
    days_old = div(state.cleanup_interval || :timer.hours(24), :timer.hours(24))
    
    # Use Ash action to cleanup old workflows
    case Workflow
         |> Ash.bulk_destroy(:cleanup_old, %{days_old: days_old}) do
      {:ok, _result} ->
        Logger.info("Cleaned up workflows older than #{days_old} days")
      {:error, error} ->
        Logger.error("Failed to cleanup old workflows: #{inspect(error)}")
    end
    
    # Schedule next cleanup
    if state.cleanup_interval do
      Process.send_after(self(), :cleanup, state.cleanup_interval)
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:workflow_completed, workflow_id, _result}, state) do
    # This is now handled in execute_workflow_async
    Logger.debug("Workflow #{workflow_id} completed notification received")
    {:noreply, state}
  end
  
  # Private functions
  
  defp create_workflow_record(workflow_id, module, inputs, opts) do
    context = build_context(workflow_id, opts)
    
    attrs = %{
      workflow_id: workflow_id,
      module: module,
      status: :running,
      reactor_state: %{inputs: inputs},
      context: context,
      metadata: %{
        opts: opts,
        started_at: DateTime.utc_now()
      }
    }
    
    Workflow
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end
  
  defp format_workflow(workflow) do
    %{
      id: workflow.workflow_id,
      module: workflow.module,
      status: workflow.status,
      started_at: workflow.created_at,
      completed_at: workflow.completed_at,
      error: workflow.error,
      context: workflow.context,
      metadata: workflow.metadata
    }
  end
  
  defp generate_workflow_id do
    "wf_" <> :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp build_context(workflow_id, opts) do
    base_context = %{
      workflow_id: workflow_id,
      started_at: System.system_time(:microsecond),
      coordinator_pid: self() |> :erlang.term_to_binary() |> Base.encode64()
    }
    
    Map.merge(base_context, Keyword.get(opts, :context, %{}))
  end
  
  defp execute_workflow_async(workflow_id, module, inputs, opts, state) do
    context = build_context(workflow_id, opts)
    
    # Execute workflow
    start_time = System.monotonic_time(:microsecond)
    
    result = case Reactor.run(module, inputs, context, opts) do
      {:ok, result} ->
        duration = System.monotonic_time(:microsecond) - start_time
        
        # Update workflow state in database
        update_workflow_status(workflow_id, :completed, %{
          result: result,
          duration: duration
        })
        
        if state.telemetry_enabled do
          :telemetry.execute(
            [:rubber_duck, :workflow, :complete],
            %{duration: duration},
            %{workflow_id: workflow_id, module: module, status: :success}
          )
        end
        
        {:ok, result}
        
      {:halted, reactor_state} ->
        duration = System.monotonic_time(:microsecond) - start_time
        
        # Update workflow state in database
        update_workflow_status(workflow_id, :halted, %{
          reactor_state: reactor_state,
          duration: duration
        })
        
        if state.telemetry_enabled do
          :telemetry.execute(
            [:rubber_duck, :workflow, :halt],
            %{duration: duration},
            %{workflow_id: workflow_id, module: module}
          )
        end
        
        {:halted, workflow_id}
        
      {:error, errors} ->
        duration = System.monotonic_time(:microsecond) - start_time
        
        # Update workflow state in database
        update_workflow_status(workflow_id, :failed, %{
          error: %{errors: errors},
          duration: duration
        })
        
        if state.telemetry_enabled do
          :telemetry.execute(
            [:rubber_duck, :workflow, :error],
            %{duration: duration, error_count: length(errors)},
            %{workflow_id: workflow_id, module: module, errors: errors}
          )
        end
        
        {:error, errors}
    end
    
    result
  end
  
  defp update_workflow_status(workflow_id, status, metadata) do
    case WorkflowPersistence.load_workflow_state(workflow_id) do
      {:ok, workflow} ->
        attrs = %{
          status: status,
          metadata: Map.merge(workflow.metadata || %{}, metadata)
        }
        
        # Add error if present
        attrs = if error = metadata[:error] do
          Map.put(attrs, :error, error)
        else
          attrs
        end
        
        # Update reactor state if present
        attrs = if reactor_state = metadata[:reactor_state] do
          Map.put(attrs, :reactor_state, reactor_state)
        else
          attrs
        end
        
        workflow
        |> Ash.Changeset.for_update(:update_status, attrs)
        |> Ash.update()
        
      {:error, error} ->
        Logger.error("Failed to update workflow status: #{inspect(error)}")
        {:error, error}
    end
  end
  
  defp resume_workflow_async(workflow_id, reactor_state, additional_inputs, context, _state) do
    # Resume reactor execution
    result = Reactor.run(reactor_state, additional_inputs, context)
    
    # Notify coordinator
    send(self(), {:workflow_completed, workflow_id, result})
  end
  
  
  # Telemetry helpers
  
  defp generate_mock_logs(workflow_id, limit, offset, level) do
    # Generate mock log entries for demo purposes
    # In a real implementation, this would query the logging system
    base_logs = [
      %{
        timestamp: DateTime.utc_now() |> DateTime.add(-300, :second),
        level: "info",
        message: "Workflow #{workflow_id} started",
        metadata: %{workflow_id: workflow_id, step: "initialization"}
      },
      %{
        timestamp: DateTime.utc_now() |> DateTime.add(-280, :second),
        level: "debug",
        message: "Agent selection for step 'validate_input'",
        metadata: %{workflow_id: workflow_id, step: "validate_input", agent_id: "agent_123"}
      },
      %{
        timestamp: DateTime.utc_now() |> DateTime.add(-260, :second),
        level: "info",
        message: "Step 'validate_input' completed successfully",
        metadata: %{workflow_id: workflow_id, step: "validate_input", duration: 1200}
      }
    ]
    
    # Filter by level if specified
    filtered_logs = if level != "info" do
      Enum.filter(base_logs, fn log -> log.level == level end)
    else
      base_logs
    end
    
    # Apply pagination
    filtered_logs
    |> Enum.drop(offset)
    |> Enum.take(limit)
  end
end
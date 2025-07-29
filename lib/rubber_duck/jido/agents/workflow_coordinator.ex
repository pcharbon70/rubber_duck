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
      workflows: %{},
      persist_enabled: Keyword.get(opts, :persist, false),
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
    
    # Start workflow asynchronously
    Task.start_link(fn ->
      execute_workflow_async(workflow_id, module, inputs, opts, state)
    end)
    
    # Track workflow
    new_workflows = Map.put(state.workflows, workflow_id, %{
      module: module,
      status: :running,
      started_at: DateTime.utc_now()
    })
    
    {:reply, {:ok, workflow_id}, %{state | workflows: new_workflows}}
  end
  
  @impl true
  def handle_call({:get_status, workflow_id}, _from, state) do
    status = case Map.get(state.workflows, workflow_id) do
      nil ->
        # Check persisted state
        if state.persist_enabled do
          case WorkflowPersistence.load_workflow_state(workflow_id) do
            {:ok, workflow_state} -> {:ok, workflow_state}
            {:error, _} -> {:error, :not_found}
          end
        else
          {:error, :not_found}
        end
        
      workflow ->
        {:ok, workflow}
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
          
          # Update tracking
          new_workflows = Map.put(state.workflows, workflow_id, %{
            status: :running,
            resumed_at: DateTime.utc_now()
          })
          
          {:reply, :ok, %{state | workflows: new_workflows}}
          
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
    workflows = Enum.map(state.workflows, fn {id, info} ->
      Map.put(info, :id, id)
    end)
    
    {:reply, workflows, state}
  end
  
  @impl true
  def handle_call({:update_workflow, workflow_id, updates}, _from, state) do
    case Map.get(state.workflows, workflow_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      workflow_state ->
        # Basic validation - only allow updating certain fields
        allowed_updates = [:context, :metadata, :timeout]
        filtered_updates = Map.take(updates, allowed_updates)
        
        updated_workflow = Map.merge(workflow_state, filtered_updates)
        updated_workflows = Map.put(state.workflows, workflow_id, updated_workflow)
        new_state = %{state | workflows: updated_workflows}
        
        {:reply, {:ok, updated_workflow}, new_state}
    end
  end
  
  @impl true
  def handle_call({:get_workflow_logs, workflow_id, opts}, _from, state) do
    case Map.get(state.workflows, workflow_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      _workflow_state ->
        # Fetch logs from telemetry or logging system
        # For now, return mock logs
        limit = Keyword.get(opts, :limit, 100)
        offset = Keyword.get(opts, :offset, 0)
        level = Keyword.get(opts, :level, "info")
        
        logs = generate_mock_logs(workflow_id, limit, offset, level)
        {:reply, {:ok, logs}, state}
    end
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Clean up completed workflows older than 1 hour
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)
    
    new_workflows = state.workflows
    |> Enum.reject(fn {_id, workflow} ->
      workflow.status in [:completed, :failed] and
      DateTime.compare(workflow.completed_at || workflow.started_at, cutoff) == :lt
    end)
    |> Map.new()
    
    # Schedule next cleanup
    if state.cleanup_interval do
      Process.send_after(self(), :cleanup, state.cleanup_interval)
    end
    
    {:noreply, %{state | workflows: new_workflows}}
  end
  
  @impl true
  def handle_info({:workflow_completed, workflow_id, result}, state) do
    # Update workflow status
    new_workflows = Map.update(state.workflows, workflow_id, nil, fn workflow ->
      %{workflow | 
        status: if(match?({:ok, _}, result), do: :completed, else: :failed),
        completed_at: DateTime.utc_now(),
        result: result
      }
    end)
    
    {:noreply, %{state | workflows: new_workflows}}
  end
  
  # Private functions
  
  defp generate_workflow_id do
    "wf_" <> :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp build_context(workflow_id, opts) do
    base_context = %{
      workflow_id: workflow_id,
      started_at: System.system_time(:microsecond),
      coordinator_pid: self()
    }
    
    Map.merge(base_context, Keyword.get(opts, :context, %{}))
  end
  
  defp execute_workflow_async(workflow_id, module, inputs, opts, state) do
    context = build_context(workflow_id, opts)
    
    result = execute_workflow(module, inputs, Keyword.put(opts, :context, context))
    
    # Notify coordinator
    send(state.coordinator_pid || self(), {:workflow_completed, workflow_id, result})
  end
  
  defp resume_workflow_async(workflow_id, reactor_state, additional_inputs, context, state) do
    # Resume reactor execution
    result = Reactor.run(reactor_state, additional_inputs, context)
    
    # Notify coordinator
    send(state.coordinator_pid || self(), {:workflow_completed, workflow_id, result})
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
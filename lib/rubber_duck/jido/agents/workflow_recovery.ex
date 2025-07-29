defmodule RubberDuck.Jido.Agents.WorkflowRecovery do
  @moduledoc """
  Recovery mechanisms for failed or interrupted workflows.
  
  This module provides:
  - Automatic recovery of halted workflows
  - Checkpoint-based resumption
  - Version compatibility checking
  - Recovery strategies (retry, skip, compensate)
  - Integration with agent recovery mechanisms
  
  ## Recovery Strategies
  
  - **Retry**: Re-execute from the last checkpoint
  - **Skip**: Skip the failed step and continue
  - **Compensate**: Run compensation logic and halt
  - **Resume**: Resume from exact state (for halted workflows)
  
  ## Example
  
      # Recover a failed workflow
      {:ok, result} = WorkflowRecovery.recover_workflow(
        workflow_id,
        strategy: :retry,
        max_attempts: 3
      )
      
      # Recover all halted workflows
      {:ok, recovered} = WorkflowRecovery.recover_all_halted()
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Jido.Agents.{WorkflowCoordinator}
  alias RubberDuck.Jido.Agents.WorkflowPersistenceAsh, as: WorkflowPersistence
  
  @type recovery_strategy :: :retry | :skip | :compensate | :resume
  @type recovery_result :: {:ok, any()} | {:error, any()} | {:partial, any()}
  
  # Client API
  
  @doc """
  Starts the recovery service.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Recovers a specific workflow.
  """
  def recover_workflow(workflow_id, opts \\ []) do
    GenServer.call(__MODULE__, {:recover, workflow_id, opts}, :infinity)
  end
  
  @doc """
  Recovers all halted workflows.
  """
  def recover_all_halted(opts \\ []) do
    GenServer.call(__MODULE__, {:recover_all_halted, opts}, :infinity)
  end
  
  @doc """
  Sets up automatic recovery for new failures.
  """
  def enable_auto_recovery(opts \\ []) do
    GenServer.call(__MODULE__, {:enable_auto_recovery, opts})
  end
  
  @doc """
  Disables automatic recovery.
  """
  def disable_auto_recovery do
    GenServer.call(__MODULE__, :disable_auto_recovery)
  end
  
  @doc """
  Gets recovery statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    state = %{
      auto_recovery: opts[:auto_recovery] || false,
      recovery_interval: opts[:recovery_interval] || :timer.minutes(5),
      max_attempts: opts[:max_attempts] || 3,
      default_strategy: opts[:default_strategy] || :retry,
      stats: %{
        total_recoveries: 0,
        successful: 0,
        failed: 0,
        partial: 0,
        by_strategy: %{}
      },
      recovery_attempts: %{}  # workflow_id => attempt_count
    }
    
    # Start auto-recovery if enabled
    if state.auto_recovery do
      schedule_recovery_check(state.recovery_interval)
    end
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:recover, workflow_id, opts}, _from, state) do
    strategy = opts[:strategy] || state.default_strategy
    max_attempts = opts[:max_attempts] || state.max_attempts
    
    # Check attempt count
    attempts = Map.get(state.recovery_attempts, workflow_id, 0)
    
    if attempts >= max_attempts do
      {:reply, {:error, :max_attempts_exceeded}, state}
    else
      # Load workflow state
      case WorkflowPersistence.load_workflow_state(workflow_id) do
        {:ok, workflow_state} ->
          # Attempt recovery
          result = perform_recovery(workflow_state, strategy, opts)
          
          # Update stats
          new_state = update_stats(state, result, strategy)
          |> update_attempts(workflow_id, attempts + 1)
          
          {:reply, result, new_state}
          
        {:error, reason} ->
          {:reply, {:error, {:load_failed, reason}}, state}
      end
    end
  end
  
  @impl true
  def handle_call({:recover_all_halted, opts}, _from, state) do
    # Get all halted workflows
    case WorkflowPersistence.list_workflows(status: :halted) do
      {:ok, workflows} ->
        # Recover each workflow
        results = Enum.map(workflows, fn workflow ->
          workflow_id = workflow.workflow_id
          
          case recover_workflow(workflow_id, opts) do
            {:ok, result} -> {workflow_id, {:ok, result}}
            error -> {workflow_id, error}
          end
        end)
        
        # Summarize results
        summary = summarize_recovery_results(results)
        
        {:reply, {:ok, summary}, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:enable_auto_recovery, opts}, _from, state) do
    new_state = %{state |
      auto_recovery: true,
      recovery_interval: opts[:interval] || state.recovery_interval,
      default_strategy: opts[:strategy] || state.default_strategy
    }
    
    # Schedule first check
    schedule_recovery_check(new_state.recovery_interval)
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:disable_auto_recovery, _from, state) do
    {:reply, :ok, %{state | auto_recovery: false}}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end
  
  @impl true
  def handle_info(:recovery_check, state) do
    if state.auto_recovery do
      # Perform recovery check
      Task.start(fn ->
        recover_all_halted()
      end)
      
      # Schedule next check
      schedule_recovery_check(state.recovery_interval)
    end
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp perform_recovery(workflow_state, strategy, opts) do
    case strategy do
      :retry ->
        retry_from_checkpoint(workflow_state, opts)
        
      :skip ->
        skip_failed_step(workflow_state, opts)
        
      :compensate ->
        run_compensation(workflow_state, opts)
        
      :resume ->
        resume_workflow(workflow_state, opts)
        
      _ ->
        {:error, :unknown_strategy}
    end
  end
  
  defp retry_from_checkpoint(workflow_state, opts) do
    workflow_id = workflow_state.workflow_id
    
    # Load latest checkpoint
    case WorkflowPersistence.load_checkpoint(workflow_id) do
      {:ok, checkpoint} ->
        Logger.info("Retrying workflow #{workflow_id} from checkpoint #{checkpoint.id}")
        
        # Reconstruct inputs from checkpoint
        inputs = reconstruct_inputs(checkpoint, workflow_state)
        
        # Re-execute workflow from checkpoint
        case WorkflowCoordinator.execute_workflow(
          workflow_state.module,
          inputs,
          Keyword.merge(opts, [
            context: Map.merge(workflow_state.context, %{
              recovery: true,
              checkpoint_id: checkpoint.id,
              retry_attempt: true
            })
          ])
        ) do
          {:ok, result} ->
            # Clean up old state
            WorkflowPersistence.delete_workflow_state(workflow_id)
            {:ok, result}
            
          error ->
            error
        end
        
      {:error, :no_checkpoints} ->
        # Retry from beginning
        Logger.info("No checkpoints found, retrying workflow #{workflow_id} from start")
        
        inputs = workflow_state.context[:original_inputs] || %{}
        
        WorkflowCoordinator.execute_workflow(
          workflow_state.module,
          inputs,
          Keyword.merge(opts, [
            context: Map.merge(workflow_state.context, %{recovery: true})
          ])
        )
        
      error ->
        error
    end
  end
  
  defp skip_failed_step(_workflow_state, _opts) do
    # This requires more complex manipulation of reactor state
    # For now, return an error
    {:error, :skip_not_implemented}
  end
  
  defp run_compensation(_workflow_state, _opts) do
    # This would trigger compensation logic in the workflow
    # For now, return an error
    {:error, :compensation_not_implemented}
  end
  
  defp resume_workflow(workflow_state, _opts) do
    workflow_id = workflow_state.workflow_id
    
    Logger.info("Resuming halted workflow #{workflow_id}")
    
    # Resume with the saved reactor state
    case WorkflowCoordinator.resume_workflow(workflow_id, %{}) do
      :ok ->
        # Wait for completion (this is simplified)
        Process.sleep(100)
        
        case WorkflowCoordinator.get_workflow_status(workflow_id) do
          {:ok, %{status: :completed, result: result}} ->
            WorkflowPersistence.delete_workflow_state(workflow_id)
            {:ok, result}
            
          {:ok, %{status: :failed, error: error}} ->
            {:error, error}
            
          _ ->
            {:partial, :resumed_but_not_completed}
        end
        
      error ->
        error
    end
  end
  
  defp reconstruct_inputs(checkpoint, workflow_state) do
    # Reconstruct inputs from checkpoint and workflow state
    base_inputs = workflow_state.context[:original_inputs] || %{}
    
    # Merge with checkpoint state if available
    if checkpoint.state[:inputs] do
      Map.merge(base_inputs, checkpoint.state[:inputs])
    else
      base_inputs
    end
  end
  
  defp update_stats(state, result, strategy) do
    stats = state.stats
    
    new_stats = %{stats |
      total_recoveries: stats.total_recoveries + 1,
      by_strategy: Map.update(stats.by_strategy, strategy, 1, &(&1 + 1))
    }
    
    new_stats = case result do
      {:ok, _} ->
        %{new_stats | successful: new_stats.successful + 1}
        
      {:error, _} ->
        %{new_stats | failed: new_stats.failed + 1}
        
      {:partial, _} ->
        %{new_stats | partial: new_stats.partial + 1}
    end
    
    %{state | stats: new_stats}
  end
  
  defp update_attempts(state, workflow_id, attempts) do
    %{state | 
      recovery_attempts: Map.put(state.recovery_attempts, workflow_id, attempts)
    }
  end
  
  defp schedule_recovery_check(interval) do
    Process.send_after(self(), :recovery_check, interval)
  end
  
  defp summarize_recovery_results(results) do
    total = length(results)
    successful = Enum.count(results, fn {_, r} -> match?({:ok, _}, r) end)
    failed = Enum.count(results, fn {_, r} -> match?({:error, _}, r) end)
    
    %{
      total: total,
      successful: successful,
      failed: failed,
      results: Map.new(results)
    }
  end
end
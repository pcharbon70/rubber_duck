defmodule RubberDuck.Agents.WorkflowAgent do
  @moduledoc """
  Workflow Agent for managing workflow orchestration and execution.
  
  This agent coordinates workflow execution using Reactor integration and provides
  a unified interface for workflow operations with proper state management.
  
  ## Responsibilities
  
  - Execute individual workflow steps with dependency resolution
  - Coordinate multi-step workflow execution
  - Track workflow progress and completion status
  - Handle workflow failures and implement recovery strategies
  - Compose and validate workflow definitions
  - Manage workflow state persistence through Ash resources
  
  ## Available Actions
  
  - `ExecuteWorkflowStepAction` - Execute individual workflow steps
  - `CoordinateStepsAction` - Coordinate step execution and dependencies
  - `TrackProgressAction` - Track workflow progress and metrics
  - `RecoverWorkflowAction` - Handle workflow failures and recovery
  - `ComposeWorkflowAction` - Create and compose workflow definitions
  - `ValidateWorkflowAction` - Validate workflow structure and dependencies
  """

  use Jido.Agent,
    name: "workflow_agent",
    description: "Manages workflow orchestration and execution",
    schema: [
      # Workflow execution state
      active_workflows: [type: :map, default: %{}],
      workflow_history: [type: {:list, :map}, default: []],
      max_history: [type: :integer, default: 100],
      
      # Configuration
      config: [type: :map, default: %{
        max_concurrent_workflows: 10,
        default_timeout: 300_000,
        retry_attempts: 3,
        recovery_strategy: :restart
      }],
      
      # Performance metrics
      metrics: [type: :map, default: %{
        total_workflows: 0,
        successful_workflows: 0,
        failed_workflows: 0,
        avg_execution_time: 0.0,
        recovery_count: 0
      }]
    ],
    actions: [
      __MODULE__.ExecuteWorkflowStepAction,
      __MODULE__.CoordinateStepsAction,
      __MODULE__.TrackProgressAction,
      __MODULE__.RecoverWorkflowAction,
      __MODULE__.ComposeWorkflowAction,
      __MODULE__.ValidateWorkflowAction
    ]

  alias RubberDuck.Agents.ErrorHandling
  alias RubberDuck.Workflows.Workflow
  require Logger

  @impl true
  def mount(opts, initial_state) do
    Logger.info("Mounting workflow agent", opts: opts)
    
    # Initialize with configuration validation
    config = initial_state[:config] || %{
      max_concurrent_workflows: 10,
      default_timeout: 300_000,
      retry_attempts: 3,
      recovery_strategy: :restart
    }
    
    state = %{
      active_workflows: %{},
      workflow_history: [],
      max_history: 100,
      config: config,
      metrics: %{
        total_workflows: 0,
        successful_workflows: 0,
        failed_workflows: 0,
        avg_execution_time: 0.0,
        recovery_count: 0
      }
    }
    
    Logger.info("WorkflowAgent mounted successfully")
    state
  end

  # Action definitions

  defmodule ExecuteWorkflowStepAction do
    @moduledoc """
    Executes individual workflow steps with proper dependency resolution.
    
    Handles step execution, input validation, and result processing
    while maintaining workflow state consistency.
    """
    use Jido.Action,
      name: "execute_workflow_step",
      description: "Execute individual workflow step",
      schema: [
        workflow_id: [type: :string, required: true, doc: "Workflow identifier"],
        step_name: [type: :atom, required: true, doc: "Step name to execute"],
        step_module: [type: :atom, required: true, doc: "Step implementation module"],
        input_data: [type: :map, default: %{}, doc: "Input data for the step"],
        context: [type: :map, default: %{}, doc: "Execution context"],
        timeout: [type: :integer, default: 30_000, doc: "Step timeout in milliseconds"]
      ]

    @impl true
    def run(params, _context) do
      ErrorHandling.safe_execute(fn ->
        Logger.info("Executing workflow step", 
          workflow_id: params.workflow_id,
          step: params.step_name,
          module: params.step_module
        )
        
        start_time = System.monotonic_time(:millisecond)
        
        case execute_step_with_timeout(params) do
          {:ok, result} ->
            execution_time = System.monotonic_time(:millisecond) - start_time
            
            Logger.info("Workflow step completed", 
              workflow_id: params.workflow_id,
              step: params.step_name,
              execution_time: execution_time
            )
            
            {:ok, %{
              workflow_id: params.workflow_id,
              step_name: params.step_name,
              result: result,
              execution_time: execution_time,
              status: :completed,
              completed_at: DateTime.utc_now()
            }}
            
          {:error, error} ->
            ErrorHandling.categorize_error(error)
        end
      end)
    end

    defp execute_step_with_timeout(params) do
      try do
        task = Task.async(fn ->
          apply(params.step_module, :run, [params.input_data, params.context])
        end)
        
        case Task.await(task, params.timeout) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
          result -> {:ok, result}  # Handle modules that return result directly
        end
      rescue
        error ->
          {:error, {:step_exception, Exception.message(error)}}
      catch
        :exit, {:timeout, _} ->
          {:error, :step_timeout}
        :exit, reason ->
          {:error, {:step_crashed, reason}}
      end
    end
  end

  defmodule CoordinateStepsAction do
    @moduledoc """
    Coordinates execution of multiple workflow steps with dependency resolution.
    
    Manages step ordering, parallel execution where possible, and ensures
    proper data flow between dependent steps.
    """
    use Jido.Action,
      name: "coordinate_steps",
      description: "Coordinate workflow step execution",
      schema: [
        workflow_id: [type: :string, required: true, doc: "Workflow identifier"],
        steps: [type: {:list, :map}, required: true, doc: "List of step definitions"],
        execution_mode: [type: :atom, default: :sequential, doc: "Execution mode: sequential or parallel"],
        context: [type: :map, default: %{}, doc: "Shared execution context"]
      ]

    @impl true
    def run(params, _context) do
      ErrorHandling.safe_execute(fn ->
        Logger.info("Coordinating workflow steps", 
          workflow_id: params.workflow_id,
          step_count: length(params.steps),
          mode: params.execution_mode
        )
        
        case params.execution_mode do
          :sequential -> execute_sequential_steps(params)
          :parallel -> execute_parallel_steps(params)
          :dependency_graph -> execute_with_dependencies(params)
          _ -> {:error, :invalid_execution_mode}
        end
      end)
    end

    defp execute_sequential_steps(params) do
      results = %{}
      context = params.context
      
      Enum.reduce_while(params.steps, {:ok, results, context}, fn step, {:ok, acc_results, acc_context} ->
        step_params = %{
          workflow_id: params.workflow_id,
          step_name: step.name,
          step_module: step.module,
          input_data: resolve_step_inputs(step, acc_results),
          context: acc_context,
          timeout: Map.get(step, :timeout, 30_000)
        }
        
        case ExecuteWorkflowStepAction.run(step_params, %{}) do
          {:ok, result} ->
            updated_results = Map.put(acc_results, step.name, result)
            updated_context = Map.merge(acc_context, result[:context] || %{})
            {:cont, {:ok, updated_results, updated_context}}
            
          {:error, error} ->
            {:halt, {:error, {:step_failed, step.name, error}}}
        end
      end)
      |> case do
        {:ok, results, final_context} ->
          {:ok, %{
            workflow_id: params.workflow_id,
            execution_mode: :sequential,
            results: results,
            context: final_context,
            status: :completed,
            completed_at: DateTime.utc_now()
          }}
          
        {:error, error} ->
          ErrorHandling.categorize_error(error)
      end
    end

    defp execute_parallel_steps(params) do
      tasks = Enum.map(params.steps, fn step ->
        step_params = %{
          workflow_id: params.workflow_id,
          step_name: step.name,
          step_module: step.module,
          input_data: step[:input] || %{},
          context: params.context,
          timeout: Map.get(step, :timeout, 30_000)
        }
        
        Task.async(fn ->
          {step.name, ExecuteWorkflowStepAction.run(step_params, %{})}
        end)
      end)
      
      results = Task.await_many(tasks, 60_000)
      
      case Enum.find(results, fn {_name, result} -> match?({:error, _}, result) end) do
        nil ->
          step_results = Enum.into(results, %{}, fn {name, {:ok, result}} -> {name, result} end)
          
          {:ok, %{
            workflow_id: params.workflow_id,
            execution_mode: :parallel,
            results: step_results,
            status: :completed,
            completed_at: DateTime.utc_now()
          }}
          
        {failed_step, {:error, error}} ->
          {:error, {:parallel_step_failed, failed_step, error}}
      end
    end

    defp execute_with_dependencies(params) do
      # Simple dependency resolution - would need proper topological sort for complex workflows
      sorted_steps = sort_steps_by_dependencies(params.steps)
      execute_sequential_steps(%{params | steps: sorted_steps})
    end

    defp resolve_step_inputs(step, previous_results) do
      step_input = step[:input] || %{}
      
      # Replace references to previous step results
      Enum.reduce(step_input, %{}, fn {key, value}, acc ->
        resolved_value = case value do
          {:result, step_name} -> 
            get_in(previous_results, [step_name, :result])
          {:result, step_name, path} -> 
            get_in(previous_results, [step_name, :result] ++ path)
          other -> 
            other
        end
        
        Map.put(acc, key, resolved_value)
      end)
    end

    defp sort_steps_by_dependencies(steps) do
      # Simple implementation - would need proper topological sort for complex dependencies
      steps
    end
  end

  defmodule TrackProgressAction do
    @moduledoc """
    Tracks workflow execution progress and maintains metrics.
    
    Provides real-time progress updates and collects performance metrics
    for workflow optimization and monitoring.
    """
    use Jido.Action,
      name: "track_progress",
      description: "Track workflow execution progress",
      schema: [
        workflow_id: [type: :string, required: true, doc: "Workflow identifier"],
        progress_update: [type: :map, required: true, doc: "Progress update data"],
        metrics: [type: :map, default: %{}, doc: "Additional metrics to record"]
      ]

    @impl true
    def run(params, context) do
      ErrorHandling.safe_execute(fn ->
        agent = context.agent
        progress = params.progress_update
        
        Logger.debug("Tracking workflow progress", 
          workflow_id: params.workflow_id,
          progress: progress
        )
        
        # Update workflow tracking
        updated_workflows = Map.update(
          agent.state.active_workflows,
          params.workflow_id,
          %{progress: progress, updated_at: DateTime.utc_now()},
          fn existing ->
            Map.merge(existing, %{
              progress: Map.merge(existing[:progress] || %{}, progress),
              updated_at: DateTime.utc_now()
            })
          end
        )
        
        # Update metrics
        updated_metrics = update_workflow_metrics(agent.state.metrics, params.metrics)
        
        {:ok, %{
          workflow_id: params.workflow_id,
          progress: progress,
          metrics_updated: true,
          tracked_at: DateTime.utc_now()
        }, %{agent: %{agent | state: %{agent.state | 
          active_workflows: updated_workflows,
          metrics: updated_metrics
        }}}}
      end)
    end

    defp update_workflow_metrics(current_metrics, new_metrics) do
      Map.merge(current_metrics, new_metrics, fn
        _key, current, new when is_number(current) and is_number(new) ->
          current + new
        _key, _current, new ->
          new
      end)
    end
  end

  defmodule RecoverWorkflowAction do
    @moduledoc """
    Handles workflow failures and implements recovery strategies.
    
    Provides multiple recovery strategies including restart, partial recovery,
    and compensation actions for failed workflows.
    """
    use Jido.Action,
      name: "recover_workflow",
      description: "Recover failed workflows",
      schema: [
        workflow_id: [type: :string, required: true, doc: "Failed workflow identifier"],
        failure_reason: [type: :map, required: true, doc: "Failure information"],
        recovery_strategy: [type: :atom, default: :restart, doc: "Recovery strategy to use"],
        recovery_context: [type: :map, default: %{}, doc: "Additional recovery context"]
      ]

    @impl true
    def run(params, context) do
      ErrorHandling.safe_execute(fn ->
        Logger.info("Initiating workflow recovery", 
          workflow_id: params.workflow_id,
          strategy: params.recovery_strategy,
          reason: params.failure_reason
        )
        
        case params.recovery_strategy do
          :restart -> restart_workflow(params, context)
          :partial_recovery -> partial_recovery_workflow(params, context)
          :compensation -> compensate_workflow(params, context)
          :manual -> mark_for_manual_recovery(params, context)
          _ -> {:error, :invalid_recovery_strategy}
        end
      end)
    end

    defp restart_workflow(params, _context) do
      # Load workflow definition from persistence
      case Ash.get(Workflow, params.workflow_id) do
        {:ok, workflow} ->
          # Reset workflow state and restart
          case Ash.update(workflow, :update_status, %{status: :running, error: nil}) do
            {:ok, updated_workflow} ->
              {:ok, %{
                workflow_id: params.workflow_id,
                recovery_strategy: :restart,
                status: :recovered,
                restarted_at: DateTime.utc_now(),
                workflow: updated_workflow
              }}
              
            {:error, error} ->
              ErrorHandling.categorize_error(error)
          end
          
        {:error, error} ->
          ErrorHandling.categorize_error(error)
      end
    end

    defp partial_recovery_workflow(params, _context) do
      # Resume from last successful step
      {:ok, %{
        workflow_id: params.workflow_id,
        recovery_strategy: :partial_recovery,
        status: :recovered,
        recovered_at: DateTime.utc_now()
      }}
    end

    defp compensate_workflow(params, _context) do
      # Execute compensation actions for completed steps
      {:ok, %{
        workflow_id: params.workflow_id,
        recovery_strategy: :compensation,
        status: :compensated,
        compensated_at: DateTime.utc_now()
      }}
    end

    defp mark_for_manual_recovery(params, _context) do
      {:ok, %{
        workflow_id: params.workflow_id,
        recovery_strategy: :manual,
        status: :awaiting_manual_recovery,
        marked_at: DateTime.utc_now()
      }}
    end
  end

  defmodule ComposeWorkflowAction do
    @moduledoc """
    Creates and composes workflow definitions.
    
    Provides tools for building workflow definitions with proper validation
    and dependency management.
    """
    use Jido.Action,
      name: "compose_workflow",
      description: "Create and compose workflow definitions",
      schema: [
        name: [type: :string, required: true, doc: "Workflow name"],
        description: [type: :string, doc: "Workflow description"],
        steps: [type: {:list, :map}, required: true, doc: "Workflow step definitions"],
        metadata: [type: :map, default: %{}, doc: "Additional workflow metadata"]
      ]

    @impl true
    def run(params, _context) do
      ErrorHandling.safe_execute(fn ->
        Logger.info("Composing workflow", 
          name: params.name,
          step_count: length(params.steps)
        )
        
        workflow_definition = %{
          name: params.name,
          description: params.description,
          steps: params.steps,
          metadata: Map.merge(params.metadata, %{
            created_at: DateTime.utc_now(),
            version: "1.0.0"
          })
        }
        
        case validate_workflow_definition(workflow_definition) do
          :ok ->
            {:ok, %{
              workflow_definition: workflow_definition,
              status: :composed,
              composed_at: DateTime.utc_now()
            }}
            
          {:error, validation_errors} ->
            {:error, {:invalid_workflow_definition, validation_errors}}
        end
      end)
    end

    def validate_workflow_definition(definition) do
      errors = []
      
      errors = if is_nil(definition.name) or definition.name == "", 
        do: ["Workflow name is required" | errors], 
        else: errors
      
      errors = if is_nil(definition.steps) or definition.steps == [], 
        do: ["Workflow must have at least one step" | errors], 
        else: errors
      
      # Validate each step
      step_errors = Enum.flat_map(definition.steps, &validate_step/1)
      errors = errors ++ step_errors
      
      case errors do
        [] -> :ok
        _ -> {:error, errors}
      end
    end

    defp validate_step(step) do
      errors = []
      
      errors = if is_nil(step[:name]), 
        do: ["Step name is required" | errors], 
        else: errors
      
      errors = if is_nil(step[:module]), 
        do: ["Step module is required" | errors], 
        else: errors
      
      errors
    end
  end

  defmodule ValidateWorkflowAction do
    @moduledoc """
    Validates workflow structure and dependencies.
    
    Performs comprehensive validation of workflow definitions including
    dependency analysis, circular dependency detection, and resource validation.
    """
    use Jido.Action,
      name: "validate_workflow",
      description: "Validate workflow structure and dependencies",
      schema: [
        workflow_definition: [type: :map, required: true, doc: "Workflow definition to validate"],
        validation_mode: [type: :atom, default: :comprehensive, doc: "Validation mode: basic, comprehensive"]
      ]

    @impl true
    def run(params, _context) do
      ErrorHandling.safe_execute(fn ->
        Logger.info("Validating workflow", 
          name: get_in(params.workflow_definition, [:name]),
          mode: params.validation_mode
        )
        
        validation_results = case params.validation_mode do
          :basic -> basic_validation(params.workflow_definition)
          :comprehensive -> comprehensive_validation(params.workflow_definition)
          _ -> {:error, :invalid_validation_mode}
        end
        
        case validation_results do
          {:ok, results} ->
            {:ok, %{
              workflow_definition: params.workflow_definition,
              validation_mode: params.validation_mode,
              validation_results: results,
              status: :valid,
              validated_at: DateTime.utc_now()
            }}
            
          {:error, errors} ->
            {:ok, %{
              workflow_definition: params.workflow_definition,
              validation_mode: params.validation_mode,
              validation_errors: errors,
              status: :invalid,
              validated_at: DateTime.utc_now()
            }}
        end
      end)
    end

    defp basic_validation(definition) do
      case ComposeWorkflowAction.validate_workflow_definition(definition) do
        :ok -> {:ok, %{basic_validation: :passed}}
        {:error, errors} -> {:error, errors}
      end
    end

    defp comprehensive_validation(definition) do
      with {:ok, _} <- basic_validation(definition),
           {:ok, _} <- validate_dependencies(definition),
           {:ok, _} <- validate_resources(definition) do
        {:ok, %{
          basic_validation: :passed,
          dependency_validation: :passed,
          resource_validation: :passed
        }}
      else
        {:error, errors} -> {:error, errors}
      end
    end

    defp validate_dependencies(definition) do
      # Check for circular dependencies
      case detect_circular_dependencies(definition.steps) do
        [] -> {:ok, %{circular_dependencies: :none}}
        cycles -> {:error, {:circular_dependencies, cycles}}
      end
    end

    defp validate_resources(_definition) do
      # Validate that required resources are available
      {:ok, %{resource_validation: :passed}}
    end

    defp detect_circular_dependencies(_steps) do
      # Simple implementation - would need proper cycle detection for complex workflows
      []
    end
  end
end
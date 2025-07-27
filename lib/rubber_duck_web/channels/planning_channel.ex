defmodule RubberDuckWeb.PlanningChannel do
  @moduledoc """
  Channel for handling AI-driven planning operations.

  This channel manages planning interactions including:
  - Plan creation and management
  - Task decomposition
  - Plan execution monitoring
  - Validation results
  - Real-time progress updates

  ## Message Types

  ### Incoming
  - `"create_plan"` - Create a new plan (automatically validates unless skip_validation=true)
    - Params: `%{"name" => "...", "description" => "...", "type" => "feature|refactor|bugfix|analysis|migration", "context" => %{}, "skip_validation" => false}`
  - `"execute_plan"` - Execute a plan (checks validation status unless force=true)
    - Params: `%{"plan_id" => "uuid", "options" => %{}, "force" => false}`
  - `"validate_plan"` - Run critics on a plan
    - Params: `%{"plan_id" => "uuid", "validation_type" => "all|hard|soft"}`
  - `"get_plan"` - Get plan details
    - Params: `%{"plan_id" => "uuid"}`
  - `"list_plans"` - List plans with filters
    - Params: `%{"status" => "draft|ready|executing|completed|failed", "type" => "...", "limit" => 20}`
  - `"pause_execution"` - Pause plan execution
    - Params: `%{"execution_id" => "..."}`
  - `"resume_execution"` - Resume paused execution
    - Params: `%{"execution_id" => "..."}`
  - `"cancel_execution"` - Cancel plan execution
    - Params: `%{"execution_id" => "...", "reason" => "..."}`
  - `"decompose_task"` - Decompose a task into subtasks
    - Params: `%{"description" => "...", "context" => %{}}`

  ### Outgoing
  - `"plan_created"` - Plan successfully created
  - `"plan_updated"` - Plan state updated
  - `"validation_complete"` - Validation results ready
  - `"execution_started"` - Plan execution began
  - `"execution_progress"` - Execution progress update
  - `"execution_complete"` - Plan execution finished
  - `"task_status"` - Individual task status update
  - `"error"` - Error occurred
  """

  use RubberDuckWeb, :channel
  require Logger

  alias RubberDuck.Planning.Plan
  alias RubberDuck.Planning.Critics.Orchestrator
  alias RubberDuck.Planning.Execution.PlanExecutor
  alias RubberDuck.Planning.Decomposer

  @default_limit 20
  @max_limit 100

  @impl true
  def join("planning:lobby", _params, socket) do
    Logger.info("User #{socket.assigns.user_id} joining planning channel")

    # Subscribe to planning-related status updates
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "planning:updates")
    
    {:ok, %{status: "connected"}, socket}
  end

  def join("planning:" <> plan_id, _params, socket) do
    # Join a specific plan's channel for focused updates
    case authorize_plan_access(plan_id, socket.assigns.user_id) do
      :ok ->
        Phoenix.PubSub.subscribe(RubberDuck.PubSub, "planning:#{plan_id}")
        {:ok, %{plan_id: plan_id}, socket}
      
      {:error, :unauthorized} ->
        {:error, %{reason: "Unauthorized access to plan"}}
    end
  end

  # Handle plan creation
  @impl true
  def handle_in("create_plan", params, socket) do
    with {:ok, validated} <- validate_plan_params(params),
         {:ok, plan} <- create_plan(validated, socket),
         {:ok, validation_results} <- auto_validate_plan(plan, params["skip_validation"]) do
      
      # Update plan with validation results
      plan = %{plan | validation_results: validation_results}
      
      # Broadcast plan creation with validation status
      broadcast!(socket, "plan_created", %{
        plan: serialize_plan(plan),
        validation_summary: validation_results[:summary],
        created_by: socket.assigns.user_id
      })

      # Send detailed response including validation
      response = %{
        plan: serialize_plan(plan),
        validation: validation_results,
        ready_for_execution: validation_results[:summary] != :failed
      }

      {:reply, {:ok, response}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{message: format_error(reason)}}, socket}
    end
  end

  # Handle plan execution
  def handle_in("execute_plan", %{"plan_id" => plan_id} = params, socket) do
    with {:ok, plan} <- get_plan(plan_id, socket),
         :ok <- validate_plan_ready(plan),
         :ok <- check_validation_status(plan, params["force"]),
         {:ok, execution_id} <- start_plan_execution(plan, params["options"] || %{}, socket) do
      
      {:reply, {:ok, %{execution_id: execution_id, status: "started"}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{message: format_error(reason)}}, socket}
    end
  end

  # Handle plan validation
  def handle_in("validate_plan", %{"plan_id" => plan_id} = params, socket) do
    validation_type = params["validation_type"] || "all"
    
    with {:ok, plan} <- get_plan(plan_id, socket),
         {:ok, results} <- validate_plan(plan, validation_type) do
      
      push(socket, "validation_complete", %{
        plan_id: plan_id,
        results: results,
        summary: results.summary
      })

      {:reply, {:ok, %{status: "validation_complete"}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{message: format_error(reason)}}, socket}
    end
  end

  # Get plan details
  def handle_in("get_plan", %{"plan_id" => plan_id}, socket) do
    case get_plan_with_details(plan_id, socket) do
      {:ok, plan} ->
        {:reply, {:ok, %{plan: serialize_plan_with_details(plan)}}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{message: format_error(reason)}}, socket}
    end
  end

  # List plans
  def handle_in("list_plans", params, socket) do
    filters = build_plan_filters(params)
    limit = min(params["limit"] || @default_limit, @max_limit)
    
    case list_user_plans(socket.assigns.user_id, filters, limit) do
      {:ok, plans} ->
        {:reply, {:ok, %{plans: Enum.map(plans, &serialize_plan/1)}}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{message: format_error(reason)}}, socket}
    end
  end

  # Handle task decomposition
  def handle_in("decompose_task", params, socket) do
    with {:ok, validated} <- validate_decompose_params(params),
         {:ok, tasks} <- decompose_task(validated, socket) do
      
      {:reply, {:ok, %{tasks: Enum.map(tasks, &serialize_task/1)}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{message: format_error(reason)}}, socket}
    end
  end

  # Execution control
  def handle_in("pause_execution", %{"execution_id" => execution_id}, socket) do
    case PlanExecutor.pause(via_tuple(execution_id)) do
      :ok ->
        {:reply, {:ok, %{status: "paused"}}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{message: format_error(reason)}}, socket}
    end
  end

  def handle_in("resume_execution", %{"execution_id" => execution_id}, socket) do
    case PlanExecutor.resume(via_tuple(execution_id)) do
      :ok ->
        {:reply, {:ok, %{status: "resumed"}}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{message: format_error(reason)}}, socket}
    end
  end

  def handle_in("cancel_execution", %{"execution_id" => execution_id} = params, socket) do
    reason = params["reason"] || "User requested cancellation"
    
    case PlanExecutor.cancel(via_tuple(execution_id), reason) do
      :ok ->
        {:reply, {:ok, %{status: "cancelled"}}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{message: format_error(reason)}}, socket}
    end
  end

  # Handle PubSub messages
  @impl true
  def handle_info({:execution_progress, update}, socket) do
    push(socket, "execution_progress", update)
    {:noreply, socket}
  end

  def handle_info({:task_status_update, update}, socket) do
    push(socket, "task_status", update)
    {:noreply, socket}
  end

  def handle_info({:execution_complete, result}, socket) do
    push(socket, "execution_complete", result)
    {:noreply, socket}
  end

  # Private functions

  defp validate_plan_params(params) do
    required = ["name", "type"]
    
    case validate_required_fields(params, required) do
      :ok ->
        type = String.to_existing_atom(params["type"])
        
        if type in [:feature, :refactor, :bugfix, :analysis, :migration] do
          {:ok, %{
            name: params["name"],
            description: params["description"],
            type: type,
            context: params["context"] || %{},
            metadata: params["metadata"] || %{}
          }}
        else
          {:error, "Invalid plan type"}
        end
      
      {:error, field} ->
        {:error, "Missing required field: #{field}"}
    end
  end

  defp validate_decompose_params(params) do
    case params["description"] do
      nil -> {:error, "Missing required field: description"}
      desc -> {:ok, %{
        description: desc,
        context: params["context"] || %{},
        constraints: params["constraints"] || %{}
      }}
    end
  end

  defp validate_required_fields(params, fields) do
    case Enum.find(fields, fn field -> is_nil(params[field]) end) do
      nil -> :ok
      field -> {:error, field}
    end
  end

  defp create_plan(attrs, socket) do
    # Add user context
    attrs = Map.put(attrs, :metadata, Map.merge(attrs.metadata, %{
      created_by: socket.assigns.user_id,
      created_via: "planning_channel"
    }))

    Plan
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  defp get_plan(plan_id, socket) do
    case Ash.get(Plan, plan_id) do
      {:ok, plan} ->
        if authorized_for_plan?(plan, socket.assigns.user_id) do
          {:ok, plan}
        else
          {:error, :unauthorized}
        end
      
      error -> error
    end
  end

  defp get_plan_with_details(plan_id, socket) do
    case get_plan(plan_id, socket) do
      {:ok, plan} ->
        # Load relationships
        plan = Ash.load!(plan, [:tasks, :constraints, :validations])
        {:ok, plan}
      
      error -> error
    end
  end

  defp validate_plan_ready(%Plan{status: :ready}), do: :ok
  defp validate_plan_ready(%Plan{status: :executing}), do: {:error, "Plan is already executing"}
  defp validate_plan_ready(%Plan{status: status}), do: {:error, "Plan is not ready for execution (status: #{status})"}

  defp start_plan_execution(plan, options, socket) do
    execution_id = generate_execution_id()
    
    # Start the executor process
    {:ok, _pid} = PlanExecutor.start_link(execution_id: execution_id)
    
    # Subscribe to execution updates
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "execution:#{execution_id}")
    
    # Start execution asynchronously
    Task.Supervisor.start_child(RubberDuck.TaskSupervisor, fn ->
      result = PlanExecutor.execute_plan(via_tuple(execution_id), plan, options)
      
      # Broadcast completion
      Phoenix.PubSub.broadcast(
        RubberDuck.PubSub,
        "planning:#{plan.id}",
        {:execution_complete, %{
          execution_id: execution_id,
          plan_id: plan.id,
          result: result
        }}
      )
    end)
    
    # Update plan status
    {:ok, _} = Plan
      |> Ash.Changeset.for_update(:transition_status, %{new_status: :executing})
      |> Ash.update()
    
    # Broadcast execution start
    broadcast!(socket, "execution_started", %{
      plan_id: plan.id,
      execution_id: execution_id,
      started_by: socket.assigns.user_id
    })
    
    {:ok, execution_id}
  end

  defp validate_plan(plan, validation_type) do
    orchestrator = Orchestrator.new()
    
    # Run validation based on type
    validation_results = case validation_type do
      "hard" -> Orchestrator.validate_hard(orchestrator, plan)
      "soft" -> Orchestrator.validate_soft(orchestrator, plan)
      _ -> Orchestrator.validate(orchestrator, plan)
    end
    
    case validation_results do
      {:ok, results} ->
        # Aggregate and persist results
        aggregated = Orchestrator.aggregate_results(results)
        {:ok, _} = Orchestrator.persist_results(plan, results)
        
        # Update plan validation results
        {:ok, _} = plan
          |> Ash.Changeset.for_update(:add_validation_result, %{
            validation_results: %{validation_type => aggregated}
          })
          |> Ash.update()
        
        {:ok, aggregated}
      
      error -> error
    end
  end

  defp decompose_task(params, socket) do
    # Use TaskDecomposer to break down the task
    context = Map.merge(params.context, %{
      user_id: socket.assigns.user_id,
      constraints: params.constraints
    })
    
    # Use the public API module to decompose the task
    case Decomposer.decompose(params.description, context) do
      {:ok, tasks} ->
        {:ok, tasks}
      
      {:error, reason} ->
        Logger.error("Task decomposition failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp list_user_plans(user_id, filters, limit) do
    # Build query based on filters
    query = Plan
    
    query = if filters[:status] do
      query |> Ash.Query.for_read(:list_by_status, %{status: filters[:status]})
    else
      query
    end
    
    query = if filters[:type] do
      query |> Ash.Query.for_read(:list_by_type, %{type: filters[:type]})
    else
      query
    end
    
    # For now, skip user filter as metadata filtering is complex
    # TODO: Add proper user filtering once we understand Ash's JSON field filtering
    _ = user_id
    
    # Apply limit and ordering
    query
    |> Ash.Query.limit(limit)
    |> Ash.Query.sort(created_at: :desc)
    |> Ash.read()
  end

  defp build_plan_filters(params) do
    filters = %{}
    
    filters = if params["status"] do
      Map.put(filters, :status, String.to_existing_atom(params["status"]))
    else
      filters
    end
    
    if params["type"] do
      Map.put(filters, :type, String.to_existing_atom(params["type"]))
    else
      filters
    end
  end

  defp authorize_plan_access(plan_id, user_id) do
    case Ash.get(Plan, plan_id) do
      {:ok, plan} ->
        if authorized_for_plan?(plan, user_id) do
          :ok
        else
          {:error, :unauthorized}
        end
      
      _ ->
        {:error, :unauthorized}
    end
  end

  defp authorized_for_plan?(%Plan{metadata: %{"created_by" => creator}}, user_id) do
    creator == user_id
  end
  defp authorized_for_plan?(_, _), do: false

  defp serialize_plan(plan) do
    %{
      id: plan.id,
      name: plan.name,
      description: plan.description,
      type: plan.type,
      status: plan.status,
      created_at: plan.created_at,
      updated_at: plan.updated_at,
      metadata: plan.metadata
    }
  end

  defp serialize_plan_with_details(plan) do
    base = serialize_plan(plan)
    
    Map.merge(base, %{
      tasks: Enum.map(plan.tasks || [], &serialize_task/1),
      constraints: plan.constraints || [],
      validations: plan.validations || [],
      validation_results: plan.validation_results || %{},
      execution_history: plan.execution_history || []
    })
  end

  defp serialize_task(task) do
    # Handle both Ash resource tasks and decomposer output tasks
    case task do
      %{id: id} ->
        # Ash resource with ID
        %{
          id: id,
          name: task.name,
          description: task.description,
          complexity: task.complexity,
          status: task.status,
          position: task.position,
          dependencies: task.dependencies || []
        }
      
      %{} ->
        # Decomposer output without ID (new task)
        %{
          name: task[:name] || task["name"],
          description: task[:description] || task["description"],
          complexity: task[:complexity] || task["complexity"],
          position: task[:position] || task["position"],
          success_criteria: task[:success_criteria] || task["success_criteria"],
          validation_rules: task[:validation_rules] || task["validation_rules"],
          metadata: task[:metadata] || task["metadata"] || %{}
        }
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(:unauthorized), do: "Unauthorized access"
  defp format_error({:error, changeset}) when is_struct(changeset, Ash.Changeset) do
    # Format Ash changeset errors
    # Format Ash changeset errors
    changeset.errors
    |> Enum.map(&Exception.message/1)
    |> Enum.join(", ")
  end
  defp format_error(error), do: inspect(error)

  defp generate_execution_id do
    "exec_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp via_tuple(execution_id) do
    {:via, Registry, {RubberDuck.ExecutorRegistry, execution_id}}
  end

  defp auto_validate_plan(plan, skip_validation) do
    # Skip validation if explicitly requested
    if skip_validation == true do
      {:ok, %{summary: :skipped, blocking_issues: [], suggestions: []}}
    else
      # Run both hard and soft critics
      orchestrator = Orchestrator.new()
      
      case Orchestrator.validate(orchestrator, plan) do
        {:ok, results} ->
          # Aggregate results
          aggregated = Orchestrator.aggregate_results(results)
          
          # Persist validation results
          {:ok, _} = Orchestrator.persist_results(plan, results)
          
          # Update plan with initial validation
          {:ok, _} = plan
            |> Ash.Changeset.for_update(:add_validation_result, %{
              validation_results: %{"initial" => aggregated}
            })
            |> Ash.update()
          
          # Log validation summary
          Logger.info("Plan #{plan.id} validation: #{aggregated.summary}")
          
          {:ok, aggregated}
        
        error ->
          Logger.error("Failed to validate plan #{plan.id}: #{inspect(error)}")
          error
      end
    end
  end

  defp check_validation_status(plan, force) do
    # Allow force execution to bypass validation checks
    if force == true do
      :ok
    else
      # Check if plan has been validated
      case plan.validation_results do
        %{"initial" => %{summary: :failed, blocking_issues: issues}} when issues != [] ->
          {:error, "Plan has blocking validation issues. Use force=true to execute anyway."}
        
        %{"initial" => %{summary: :warning}} ->
          # Warnings don't block execution but we log them
          Logger.warning("Executing plan #{plan.id} with validation warnings")
          :ok
        
        %{"initial" => %{summary: :passed}} ->
          :ok
        
        %{} ->
          # No validation results, run validation now
          case auto_validate_plan(plan, false) do
            {:ok, %{summary: :failed, blocking_issues: issues}} when issues != [] ->
              {:error, "Plan validation failed with blocking issues. Use force=true to execute anyway."}
            
            {:ok, _} ->
              :ok
            
            error ->
              error
          end
        
        _ ->
          {:error, "Invalid validation state"}
      end
    end
  end
end
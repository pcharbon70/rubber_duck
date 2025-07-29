defmodule RubberDuckWeb.WorkflowChannel do
  @moduledoc """
  RESTful Workflow API via Phoenix Channel.
  
  Provides a complete RESTful API for workflow management through WebSocket 
  messages, combining real-time events with request/response patterns.
  
  ## Channel Topics
  
  - `workflows:api` - Main API channel for workflow operations
  - `workflows:events` - Event-only channel for real-time updates
  - `agents:api` - Agent management API
  - `agents:events` - Agent status events
  
  ## API Operations (Request/Response)
  
  ### Workflow Management
  - `create_workflow` - Create and start a new workflow
  - `get_workflow` - Get workflow details and status
  - `list_workflows` - List workflows with filtering/pagination
  - `update_workflow` - Update workflow parameters
  - `cancel_workflow` - Cancel/stop a running workflow
  - `resume_workflow` - Resume a paused workflow
  - `get_workflow_logs` - Retrieve workflow execution logs
  
  ### Workflow Templates
  - `list_templates` - List available workflow templates
  - `get_template` - Get template details and schema
  - `create_from_template` - Create workflow from template
  - `get_template_schema` - Get template input schema
  
  ### Agent Management
  - `list_agents` - List available agents
  - `get_agent` - Get agent details
  - `get_agent_status` - Get current agent status
  - `get_agent_metrics` - Get agent performance metrics
  - `list_capabilities` - List available capabilities
  - `find_agents_by_capability` - Find agents with specific capabilities
  
  ## Real-time Events (Push)
  
  - `workflow:started` - Workflow execution initiated
  - `workflow:step:completed` - Step completion
  - `workflow:step:failed` - Step failure
  - `workflow:completed` - Workflow finished
  - `workflow:failed` - Workflow failed
  - `agent:selected` - Agent selected for task
  - `agent:status:changed` - Agent status update
  
  ## Example Usage
  
      // JavaScript client
      const socket = new Socket("/socket", {params: {token: jwtToken}})
      const channel = socket.channel("workflows:api", {})
      
      // API request/response
      channel.push("create_workflow", {
        workflow_module: "RubberDuck.Jido.Workflows.SimplePipeline",
        inputs: {data: {items: [1, 2, 3]}},
        options: {persist: true}
      })
      .receive("ok", response => console.log("Workflow created:", response))
      .receive("error", error => console.log("Error:", error))
      
      // Real-time events
      channel.on("workflow:started", payload => {
        console.log("Workflow started:", payload)
      })
      
      channel.join()
  """
  
  use RubberDuckWeb, :channel
  
  require Logger
  
  alias RubberDuck.Jido.Agents.{WorkflowCoordinator, Registry}
  alias RubberDuck.Jido.Workflows.Library
  alias RubberDuck.Workflows.Workflow
  
  @impl true
  def join("workflows:api", _params, socket) do
    # Subscribe to workflow telemetry for real-time events
    subscribe_to_telemetry(socket, "workflow_api")
    
    Logger.info("Client joined workflow API channel: #{socket.id}")
    {:ok, socket}
  end
  
  @impl true
  def join("workflows:events", _params, socket) do
    # Subscribe to workflow telemetry events
    :telemetry.attach_many(
      "workflow_channel_#{socket.id}",
      [
        [:workflow, :started],
        [:workflow, :completed],
        [:workflow, :failed],
        [:workflow, :step, :completed],
        [:workflow, :step, :failed],
        [:workflow, :paused],
        [:workflow, :resumed],
        [:agent, :selected],
        [:agent, :status, :changed]
      ],
      &handle_telemetry_event/4,
      %{socket: socket}
    )
    
    Logger.info("Client joined workflow events channel: #{socket.id}")
    
    {:ok, socket}
  end
  
  @impl true
  def join("workflows:" <> workflow_id, _params, socket) do
    # Subscribe to events for a specific workflow
    socket = assign(socket, :workflow_id, workflow_id)
    
    :telemetry.attach_many(
      "workflow_channel_#{socket.id}_#{workflow_id}",
      [
        [:workflow, :started],
        [:workflow, :completed],
        [:workflow, :failed],
        [:workflow, :step, :completed],
        [:workflow, :step, :failed],
        [:workflow, :paused],
        [:workflow, :resumed]
      ],
      &handle_workflow_telemetry_event/4,
      %{socket: socket, workflow_id: workflow_id}
    )
    
    Logger.info("Client joined workflow channel for #{workflow_id}: #{socket.id}")
    
    {:ok, socket}
  end
  
  @impl true
  def join("agents:api", _params, socket) do
    # Subscribe to agent telemetry for real-time events
    subscribe_to_telemetry(socket, "agent_api")
    
    Logger.info("Client joined agent API channel: #{socket.id}")
    {:ok, socket}
  end
  
  @impl true
  def join("agents:events", _params, socket) do
    # Subscribe to agent status events only
    subscribe_to_telemetry(socket, "agent_events")
    
    Logger.info("Client joined agent events channel: #{socket.id}")
    {:ok, socket}
  end
  
  # =============================================================================
  # RESTful API Operations (Request/Response via WebSocket messages)
  # =============================================================================
  
  # Workflow Management API
  
  @impl true
  def handle_in("create_workflow", %{"workflow_module" => module_name, "inputs" => inputs} = params, socket) do
    options = Map.get(params, "options", %{})
    
    with {:ok, workflow_module} <- resolve_workflow_module(module_name),
         {:ok, workflow_id} <- WorkflowCoordinator.start_workflow(
           workflow_module,
           inputs,
           atomize_options(options)
         ) do
      
      {:reply, {:ok, %{
        status: "created",
        workflow_id: workflow_id,
        message: "Workflow started successfully"
      }}, socket}
    else
      {:error, reason} ->
        Logger.warning("Workflow creation failed: #{inspect(reason)}")
        {:reply, {:error, %{
          error: format_error(reason),
          message: "Failed to create workflow"
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("get_workflow", %{"workflow_id" => workflow_id}, socket) do
    case Workflow
         |> Ash.Query.for_read(:get_by_workflow_id, %{workflow_id: workflow_id})
         |> Ash.read_one() do
      {:ok, nil} ->
        {:reply, {:error, %{
          error: "not_found",
          message: "Workflow not found"
        }}, socket}
        
      {:ok, workflow} ->
        {:reply, {:ok, format_workflow_details_from_resource(workflow)}, socket}
        
      {:error, error} ->
        Logger.error("Failed to get workflow: #{inspect(error)}")
        {:reply, {:error, %{
          error: "query_failed",
          message: "Failed to retrieve workflow"
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("list_workflows", params, socket) do
    filters = build_filters(params)
    pagination = build_pagination(params)
    
    # Build Ash query
    query = Workflow
    |> apply_ash_filters(filters)
    |> apply_ash_pagination(pagination)
    
    case Ash.read(query) do
      {:ok, workflows} ->
        # Get total count
        count_query = Workflow |> apply_ash_filters(filters)
        {:ok, total_count} = Ash.count(count_query)
        
        formatted_workflows = workflows
        |> Enum.map(&format_workflow_from_resource/1)
        
        {:reply, {:ok, %{
          workflows: formatted_workflows,
          pagination: %{
            total: total_count,
            limit: pagination.limit,
            offset: pagination.offset,
            has_more: length(formatted_workflows) == pagination.limit
          }
        }}, socket}
        
      {:error, error} ->
        Logger.error("Failed to list workflows: #{inspect(error)}")
        {:reply, {:error, %{
          error: "query_failed",
          message: "Failed to retrieve workflows"
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("update_workflow", %{"workflow_id" => workflow_id, "updates" => updates}, socket) do
    case WorkflowCoordinator.update_workflow(workflow_id, updates) do
      {:ok, updated_workflow} ->
        {:reply, {:ok, %{
          workflow: format_workflow_details(updated_workflow),
          message: "Workflow updated successfully"
        }}, socket}
      
      {:error, :not_found} ->
        {:reply, {:error, %{
          error: "not_found",
          message: "Workflow not found"
        }}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{
          error: format_error(reason),
          message: "Failed to update workflow"
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("cancel_workflow", %{"workflow_id" => workflow_id}, socket) do
    case WorkflowCoordinator.cancel_workflow(workflow_id) do
      :ok ->
        {:reply, {:ok, %{message: "Workflow cancelled successfully"}}, socket}
      
      {:error, :not_found} ->
        {:reply, {:error, %{
          error: "not_found",
          message: "Workflow not found"
        }}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{
          error: format_error(reason),
          message: "Failed to cancel workflow"
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("resume_workflow", %{"workflow_id" => workflow_id} = params, socket) do
    resume_inputs = Map.get(params, "inputs", %{})
    
    case WorkflowCoordinator.resume_workflow(workflow_id, resume_inputs) do
      :ok ->
        {:reply, {:ok, %{message: "Workflow resumed successfully"}}, socket}
      
      {:error, :not_found} ->
        {:reply, {:error, %{
          error: "not_found",
          message: "Workflow not found"
        }}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{
          error: format_error(reason),
          message: "Failed to resume workflow"
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("get_workflow_logs", %{"workflow_id" => workflow_id} = params, socket) do
    limit = Map.get(params, "limit", 100)
    offset = Map.get(params, "offset", 0)
    level = Map.get(params, "level", "info")
    
    case WorkflowCoordinator.get_workflow_logs(workflow_id, limit: limit, offset: offset, level: level) do
      {:ok, logs} ->
        {:reply, {:ok, %{
          logs: logs,
          pagination: %{
            limit: limit,
            offset: offset,
            has_more: length(logs) == limit
          }
        }}, socket}
      
      {:error, :not_found} ->
        {:reply, {:error, %{
          error: "not_found",
          message: "Workflow not found"
        }}, socket}
    end
  end
  
  # Workflow Template API
  
  @impl true
  def handle_in("list_templates", params, socket) do
    filters = build_template_filters(params)
    
    templates = Library.list_templates()
    |> apply_template_filters(filters)
    |> Enum.map(&format_template_summary/1)
    
    {:reply, {:ok, %{
      templates: templates,
      total: length(templates)
    }}, socket}
  end
  
  @impl true
  def handle_in("get_template", %{"name" => template_name}, socket) do
    case Library.get_template(template_name) do
      {:ok, template} ->
        {:reply, {:ok, format_template_details(template)}, socket}
      
      {:error, :not_found} ->
        {:reply, {:error, %{
          error: "not_found",
          message: "Template not found"
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("create_from_template", %{"name" => template_name} = params, socket) do
    inputs = Map.get(params, "inputs", %{})
    options = Map.get(params, "options", %{})
    
    with {:ok, template} <- Library.get_template(template_name),
         {:ok, validated_inputs} <- validate_template_inputs(template, inputs),
         {:ok, workflow_id} <- WorkflowCoordinator.start_workflow(
           template.module,
           validated_inputs,
           atomize_options(options)
         ) do
      
      {:reply, {:ok, %{
        status: "created",
        workflow_id: workflow_id,
        template: template_name,
        message: "Workflow created from template successfully"
      }}, socket}
    else
      {:error, :not_found} ->
        {:reply, {:error, %{
          error: "template_not_found",
          message: "Template not found"
        }}, socket}
      
      {:error, {:validation_failed, errors}} ->
        {:reply, {:error, %{
          error: "validation_failed",
          validation_errors: errors,
          message: "Input validation failed"
        }}, socket}
      
      {:error, reason} ->
        Logger.warning("Template workflow creation failed: #{inspect(reason)}")
        {:reply, {:error, %{
          error: format_error(reason),
          message: "Failed to create workflow from template"
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("get_template_schema", %{"name" => template_name}, socket) do
    case Library.get_template_schema(template_name) do
      {:ok, schema} ->
        {:reply, {:ok, %{
          template: template_name,
          schema: schema,
          examples: Library.get_template_examples(template_name)
        }}, socket}
      
      {:error, :not_found} ->
        {:reply, {:error, %{
          error: "not_found",
          message: "Template not found"
        }}, socket}
    end
  end
  
  # Agent Management API
  
  @impl true
  def handle_in("list_agents", params, socket) do
    filters = build_agent_filters(params)
    
    agents = Registry.list_agents()
    |> apply_agent_filters(filters)
    |> Enum.map(&format_agent_summary/1)
    
    {:reply, {:ok, %{
      agents: agents,
      total: length(agents)
    }}, socket}
  end
  
  @impl true
  def handle_in("get_agent", %{"agent_id" => agent_id}, socket) do
    case Registry.get_agent(agent_id) do
      {:ok, agent} ->
        {:reply, {:ok, format_agent_details(agent)}, socket}
      
      {:error, :not_found} ->
        {:reply, {:error, %{
          error: "not_found",
          message: "Agent not found"
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("subscribe_workflow", %{"workflow_id" => workflow_id}, socket) do
    # Add workflow to subscription list
    subscriptions = socket.assigns[:workflow_subscriptions] || MapSet.new()
    updated_subscriptions = MapSet.put(subscriptions, workflow_id)
    socket = assign(socket, :workflow_subscriptions, updated_subscriptions)
    
    {:reply, {:ok, %{subscribed: workflow_id}}, socket}
  end
  
  @impl true
  def handle_in("unsubscribe_workflow", %{"workflow_id" => workflow_id}, socket) do
    # Remove workflow from subscription list
    subscriptions = socket.assigns[:workflow_subscriptions] || MapSet.new()
    updated_subscriptions = MapSet.delete(subscriptions, workflow_id)
    socket = assign(socket, :workflow_subscriptions, updated_subscriptions)
    
    {:reply, {:ok, %{unsubscribed: workflow_id}}, socket}
  end
  
  @impl true
  def handle_in("get_workflow_status", %{"workflow_id" => workflow_id}, socket) do
    case WorkflowCoordinator.get_workflow_status(workflow_id) do
      {:ok, status} ->
        {:reply, {:ok, format_workflow_status(status)}, socket}
      
      {:error, :not_found} ->
        {:reply, {:error, %{message: "Workflow not found"}}, socket}
    end
  end
  
  @impl true
  def handle_in("list_active_workflows", _params, socket) do
    workflows = WorkflowCoordinator.list_workflows()
    |> Enum.filter(& &1.status == :running)
    |> Enum.map(&format_workflow_summary/1)
    
    {:reply, {:ok, %{workflows: workflows}}, socket}
  end
  
  @impl true  
  def handle_in("get_agent_status", %{"agent_id" => agent_id}, socket) do
    case Registry.get_agent_status(agent_id) do
      {:ok, status} ->
        {:reply, {:ok, status}, socket}
      
      {:error, :not_found} ->
        {:reply, {:error, %{message: "Agent not found"}}, socket}
    end
  end
  
  @impl true
  def handle_in("get_agent_metrics", %{"agent_id" => agent_id} = params, socket) do
    opts = build_metrics_options(params)
    
    case Registry.get_agent_metrics(agent_id, opts) do
      {:ok, metrics} ->
        {:reply, {:ok, metrics}, socket}
      
      {:error, :not_found} ->
        {:reply, {:error, %{message: "Agent not found"}}, socket}
    end
  end
  
  @impl true
  def handle_in("list_capabilities", _params, socket) do
    capabilities = Registry.list_agents()
    |> Enum.flat_map(fn agent -> Map.get(agent, :capabilities, []) end)
    |> Enum.uniq()
    |> Enum.map(&format_capability/1)
    
    {:reply, {:ok, %{capabilities: capabilities}}, socket}
  end
  
  @impl true
  def handle_in("find_agents_by_capability", %{"capability" => capability} = params, socket) do
    capability_atom = String.to_existing_atom(capability)
    opts = build_capability_search_options(params)
    
    case Registry.find_agents_by_capability(capability_atom, opts) do
      {:ok, agents} ->
        formatted_agents = Enum.map(agents, &format_agent_summary/1)
        {:reply, {:ok, %{
          capability: capability,
          agents: formatted_agents,
          total: length(formatted_agents)
        }}, socket}
      
      {:error, :no_agents_found} ->
        {:reply, {:ok, %{
          capability: capability,
          agents: [],
          total: 0
        }}, socket}
    end
  rescue
    ArgumentError ->
      {:reply, {:error, %{message: "Invalid capability: #{capability}"}}, socket}
  end
  
  @impl true
  def terminate(reason, socket) do
    # Clean up telemetry attachments
    :telemetry.detach("workflow_channel_#{socket.id}")
    :telemetry.detach("agent_channel_#{socket.id}")
    
    # Detach specific workflow subscriptions
    if workflow_id = socket.assigns[:workflow_id] do
      :telemetry.detach("workflow_channel_#{socket.id}_#{workflow_id}")
    end
    
    Logger.info("Client disconnected from workflow channel: #{socket.id}, reason: #{inspect(reason)}")
    
    :ok
  end
  
  # Telemetry event handlers
  
  defp handle_telemetry_event(event_name, measurements, metadata, %{socket: socket}) do
    event_type = format_event_name(event_name)
    
    # Check if client is subscribed to this workflow (if applicable)
    if should_send_event?(socket, metadata) do
      payload = format_event_payload(event_type, measurements, metadata)
      push(socket, event_type, payload)
    end
  end
  
  defp handle_workflow_telemetry_event(event_name, measurements, metadata, %{socket: socket, workflow_id: workflow_id}) do
    # Only send events for the subscribed workflow
    if metadata[:workflow_id] == workflow_id do
      event_type = format_event_name(event_name)
      payload = format_event_payload(event_type, measurements, metadata)
      push(socket, event_type, payload)
    end
  end
  
  
  # Helper functions
  
  defp should_send_event?(socket, metadata) do
    workflow_id = metadata[:workflow_id]
    subscriptions = socket.assigns[:workflow_subscriptions]
    
    # Send if no specific subscriptions (global events) or if subscribed to this workflow
    is_nil(subscriptions) or is_nil(workflow_id) or MapSet.member?(subscriptions, workflow_id)
  end
  
  defp format_event_name([:workflow, :started]), do: "workflow.started"
  defp format_event_name([:workflow, :completed]), do: "workflow.completed"
  defp format_event_name([:workflow, :failed]), do: "workflow.failed"
  defp format_event_name([:workflow, :step, :completed]), do: "workflow.step.completed"
  defp format_event_name([:workflow, :step, :failed]), do: "workflow.step.failed"
  defp format_event_name([:workflow, :paused]), do: "workflow.paused"
  defp format_event_name([:workflow, :resumed]), do: "workflow.resumed"
  defp format_event_name([:agent, :selected]), do: "agent.selected"
  defp format_event_name([:agent, :status, :changed]), do: "agent.status.changed"
  defp format_event_name([:agent, :registered]), do: "agent.registered"
  defp format_event_name([:agent, :unregistered]), do: "agent.unregistered"
  defp format_event_name([:agent, :load, :updated]), do: "agent.load.updated"
  defp format_event_name(event), do: Enum.join(event, ".")
  
  defp format_event_payload(event_type, measurements, metadata) do
    %{
      event: event_type,
      timestamp: DateTime.utc_now(),
      measurements: measurements,
      metadata: metadata
    }
  end
  
  defp format_workflow_status(status) do
    %{
      id: status.id,
      module: to_string(status.module),
      status: status.status,
      started_at: status.started_at,
      completed_at: status[:completed_at],
      progress: status[:progress] || %{},
      error: status[:error]
    }
  end
  
  defp format_workflow_summary(workflow) do
    %{
      id: workflow.id,
      module: to_string(workflow.module),
      status: workflow.status,
      started_at: workflow.started_at,
      progress: workflow[:progress] || %{}
    }
  end
  
  defp format_workflow_from_resource(workflow) do
    %{
      id: workflow.workflow_id,
      module: to_string(workflow.module),
      status: workflow.status,
      started_at: workflow.created_at,
      completed_at: workflow.completed_at,
      progress: workflow.metadata[:progress] || %{},
      error: workflow.error
    }
  end
  
  defp format_workflow_details_from_resource(workflow) do
    %{
      id: workflow.workflow_id,
      module: to_string(workflow.module),
      status: workflow.status,
      started_at: workflow.created_at,
      completed_at: workflow.completed_at,
      progress: workflow.metadata[:progress] || %{},
      context: workflow.context || %{},
      error: workflow.error,
      metadata: workflow.metadata || %{}
    }
  end
  
  defp apply_ash_filters(query, filters) do
    require Ash.Query
    
    Enum.reduce(filters, query, fn
      {:status, filter_status}, q -> 
        Ash.Query.filter(q, status == ^filter_status)
      {:module, filter_module}, q -> 
        Ash.Query.filter(q, module == ^filter_module)
      {:created_after, _datetime}, q -> 
        # TODO: Add date filtering when Ash filter syntax is clarified
        q
      {:created_before, _datetime}, q -> 
        # TODO: Add date filtering when Ash filter syntax is clarified
        q
      _, q -> q
    end)
  end
  
  defp apply_ash_pagination(query, %{limit: limit, offset: offset}) do
    query
    |> Ash.Query.limit(limit)
    |> Ash.Query.offset(offset)
  end
  
  # Helper functions for API operations
  
  defp resolve_workflow_module(module_name) when is_binary(module_name) do
    try do
      module = String.to_existing_atom("Elixir." <> module_name)
      if Code.ensure_loaded?(module) do
        {:ok, module}
      else
        {:error, :module_not_found}
      end
    rescue
      ArgumentError ->
        {:error, :invalid_module_name}
    end
  end
  
  defp atomize_options(options) when is_map(options) do
    Enum.map(options, fn
      {key, value} when is_binary(key) ->
        {String.to_atom(key), value}
      {key, value} ->
        {key, value}
    end)
    |> Enum.into(%{})
  end
  
  defp format_error(:module_not_found), do: "workflow_module_not_found"
  defp format_error(:invalid_module_name), do: "invalid_workflow_module_name"
  defp format_error(:timeout), do: "workflow_timeout"
  defp format_error(:invalid_inputs), do: "invalid_workflow_inputs"
  defp format_error(error) when is_atom(error), do: to_string(error)
  defp format_error(error), do: inspect(error)
  
  defp format_workflow_details(workflow) do
    %{
      id: workflow.id,
      module: to_string(workflow.module),
      status: workflow.status,
      started_at: workflow.started_at,
      completed_at: workflow[:completed_at],
      progress: workflow[:progress] || %{},
      context: workflow[:context] || %{},
      error: workflow[:error],
      metadata: workflow[:metadata] || %{}
    }
  end
  
  defp build_filters(params) do
    %{
      status: params["status"],
      module: params["module"],
      created_after: parse_datetime(params["created_after"]),
      created_before: parse_datetime(params["created_before"])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end
  
  defp build_pagination(params) do
    %{
      limit: parse_integer(params["limit"], 50),
      offset: parse_integer(params["offset"], 0)
    }
  end
  
  
  defp build_template_filters(params) do
    %{
      category: params["category"],
      tag: params["tag"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end
  
  defp apply_template_filters(templates, filters) when filters == %{}, do: templates
  defp apply_template_filters(templates, filters) do
    Enum.filter(templates, fn template ->
      Enum.all?(filters, fn
        {:category, category} -> template.category == category
        {:tag, tag} -> tag in Map.get(template, :tags, [])
        _ -> true
      end)
    end)
  end
  
  defp format_template_summary(template) do
    %{
      name: template.name,
      description: template.description,
      category: template.category,
      tags: template.tags || [],
      version: template.version || "1.0.0"
    }
  end
  
  defp format_template_details(template) do
    %{
      name: template.name,
      description: template.description,
      category: template.category,
      tags: template.tags || [],
      version: template.version || "1.0.0",
      module: to_string(template.module),
      input_schema: template.input_schema || %{},
      examples: template.examples || [],
      created_at: template.created_at,
      updated_at: template.updated_at
    }
  end
  
  defp validate_template_inputs(template, inputs) do
    # Basic validation - in a real implementation, this would use a proper schema validator
    required_fields = Map.get(template.input_schema, "required", [])
    
    missing_fields = Enum.reject(required_fields, fn field ->
      Map.has_key?(inputs, field) or Map.has_key?(inputs, String.to_atom(field))
    end)
    
    if length(missing_fields) > 0 do
      {:error, {:validation_failed, %{missing_fields: missing_fields}}}
    else
      {:ok, inputs}
    end
  end
  
  defp build_agent_filters(params) do
    %{
      status: params["status"],
      tag: params["tag"],
      capability: params["capability"],
      node: params["node"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end
  
  defp apply_agent_filters(agents, filters) when filters == %{}, do: agents
  defp apply_agent_filters(agents, filters) do
    Enum.filter(agents, fn agent ->
      Enum.all?(filters, fn
        {:status, status} -> Map.get(agent, :status, :active) == String.to_atom(status)
        {:tag, tag} -> String.to_atom(tag) in Map.get(agent, :tags, [])
        {:capability, capability} -> String.to_atom(capability) in Map.get(agent, :capabilities, [])
        {:node, node} -> to_string(Map.get(agent, :node)) == node
        _ -> true
      end)
    end)
  end
  
  defp format_agent_summary(agent) do
    %{
      id: agent.id,
      module: to_string(agent.module || "Unknown"),
      tags: agent.tags || [],
      capabilities: agent.capabilities || [],
      status: agent.status || :active,
      node: agent.node,
      load: Map.get(agent.metadata || %{}, :load, 0),
      registered_at: agent.registered_at
    }
  end
  
  defp format_agent_details(agent) do
    %{
      id: agent.id,
      pid: inspect(agent.pid),
      module: to_string(agent.module || "Unknown"),
      tags: agent.tags || [],
      capabilities: agent.capabilities || [],
      status: agent.status || :active,
      node: agent.node,
      registered_at: agent.registered_at,
      metadata: agent.metadata || %{},
      load: Map.get(agent.metadata || %{}, :load, 0),
      uptime: calculate_agent_uptime(agent.registered_at)
    }
  end
  
  defp build_metrics_options(params) do
    [
      time_range: params["time_range"] || "1h",
      include_trends: params["include_trends"] != "false"
    ]
  end
  
  defp format_capability(capability) when is_atom(capability) do
    %{
      name: to_string(capability),
      description: get_capability_description(capability)
    }
  end
  
  defp get_capability_description(:process_data), do: "Process and transform data"
  defp get_capability_description(:analyze), do: "Analyze and extract insights"
  defp get_capability_description(:generate), do: "Generate content or code"
  defp get_capability_description(:validate), do: "Validate inputs and outputs"
  defp get_capability_description(capability), do: "#{capability} capability"
  
  defp build_capability_search_options(params) do
    [
      strategy: String.to_atom(params["strategy"] || "least_loaded"),
      limit: parse_integer(params["limit"], 10)
    ]
  end
  
  defp parse_datetime(nil), do: nil
  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end
  
  defp parse_integer(nil, default), do: default
  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end
  defp parse_integer(value, _default) when is_integer(value), do: value
  defp parse_integer(_, default), do: default
  
  defp calculate_agent_uptime(nil), do: 0
  defp calculate_agent_uptime(registered_at) do
    DateTime.diff(DateTime.utc_now(), registered_at, :second)
  end
  
  defp subscribe_to_telemetry(socket, context) do
    # Subscribe to relevant telemetry events based on context
    events = case context do
      "workflow_api" -> workflow_telemetry_events()
      "agent_api" -> agent_telemetry_events()
      "agent_events" -> agent_telemetry_events()
      _ -> []
    end
    
    if length(events) > 0 do
      :telemetry.attach_many(
        "#{context}_#{socket.id}",
        events,
        &handle_telemetry_event/4,
        %{socket: socket, context: context}
      )
    end
  end
  
  defp workflow_telemetry_events do
    [
      [:workflow, :started],
      [:workflow, :completed],
      [:workflow, :failed],
      [:workflow, :step, :completed],
      [:workflow, :step, :failed],
      [:workflow, :paused],
      [:workflow, :resumed]
    ]
  end
  
  defp agent_telemetry_events do
    [
      [:agent, :selected],
      [:agent, :status, :changed],
      [:agent, :registered],
      [:agent, :unregistered],
      [:agent, :load, :updated]
    ]
  end
end
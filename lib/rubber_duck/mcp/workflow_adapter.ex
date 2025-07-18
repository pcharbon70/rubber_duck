defmodule RubberDuck.MCP.WorkflowAdapter do
  @moduledoc """
  MCP-enhanced workflow adapter for sophisticated tool composition.
  
  This module extends the existing Reactor-based workflow system to support
  complex multi-tool operations over the MCP protocol. It enables external
  clients to create and execute sophisticated workflows that chain multiple
  tools together with advanced features like streaming, parallel execution,
  conditional branching, and context sharing.
  
  ## Key Features
  
  - **Multi-Tool Operations**: Chain multiple tools in sequential, parallel, or conditional patterns
  - **Workflow Streaming**: Real-time progress updates during workflow execution
  - **Reactive Triggers**: Event-driven workflow execution based on MCP notifications
  - **Context Sharing**: Persistent state management across workflow steps
  - **Sampling Integration**: Dynamic tool selection based on MCP sampling results
  - **Template Library**: Reusable workflow patterns for common use cases
  
  ## Example Usage
  
      # Create a multi-tool workflow
      workflow = WorkflowAdapter.create_workflow("data_processing", %{
        "type" => "sequential",
        "steps" => [
          %{"tool" => "data_fetcher", "params" => %{"source" => "api"}},
          %{"tool" => "data_transformer", "params" => %{"format" => "json"}},
          %{"tool" => "data_validator", "params" => %{"schema" => "user_schema"}}
        ]
      })
      
      # Execute workflow with streaming
      {:ok, result} = WorkflowAdapter.execute_workflow(workflow, %{
        "streaming" => true,
        "context" => %{"user_id" => "123"}
      })
  """
  
  alias RubberDuck.Tool.Composition
  alias RubberDuck.MCP.WorkflowAdapter.{StreamingHandler, TemplateRegistry}
  alias Phoenix.PubSub
  
  require Logger
  
  @type workflow_id :: String.t()
  @type workflow_definition :: map()
  @type workflow_context :: map()
  @type execution_options :: map()
  @type stream_event :: map()
  
  @doc """
  Creates a new workflow from an MCP workflow definition.
  
  Converts MCP workflow specifications into Reactor workflows with enhanced
  capabilities for streaming, context sharing, and advanced execution patterns.
  
  ## Workflow Types
  
  - `sequential`: Execute steps in order with result chaining
  - `parallel`: Execute steps concurrently with result aggregation
  - `conditional`: Execute different paths based on conditions
  - `loop`: Process collections with batch operations
  - `reactive`: Event-driven execution with triggers
  
  ## Example
  
      workflow = WorkflowAdapter.create_workflow("user_onboarding", %{
        "type" => "conditional",
        "condition" => %{
          "tool" => "user_validator",
          "params" => %{"strict" => true}
        },
        "success" => [
          %{"tool" => "welcome_service", "params" => %{"template" => "premium"}},
          %{"tool" => "notification_service", "params" => %{"event" => "new_user"}}
        ],
        "failure" => [
          %{"tool" => "rejection_service", "params" => %{"reason" => "validation_failed"}}
        ]
      })
  """
  @spec create_workflow(workflow_id(), workflow_definition()) :: {:ok, Reactor.t()} | {:error, term()}
  def create_workflow(workflow_id, definition) do
    case validate_workflow_definition(definition) do
      :ok ->
        case Map.get(definition, "type") do
          "sequential" -> create_sequential_workflow(workflow_id, definition)
          "parallel" -> create_parallel_workflow(workflow_id, definition)
          "conditional" -> create_conditional_workflow(workflow_id, definition)
          "loop" -> create_loop_workflow(workflow_id, definition)
          "reactive" -> create_reactive_workflow(workflow_id, definition)
          "template" -> create_template_workflow(workflow_id, definition)
          type -> {:error, "Unsupported workflow type: #{type}"}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Executes a workflow with MCP-enhanced capabilities.
  
  Supports streaming execution, context sharing, progress reporting,
  and reactive triggers for sophisticated workflow orchestration.
  
  ## Options
  
  - `streaming`: Enable real-time progress streaming
  - `context`: Shared context across workflow steps
  - `timeout`: Overall execution timeout
  - `sampling_enabled`: Enable MCP sampling integration
  - `telemetry_metadata`: Custom telemetry metadata
  
  ## Example
  
      {:ok, result} = WorkflowAdapter.execute_workflow(workflow, %{
        "streaming" => true,
        "context" => %{"user_id" => "123", "trace_id" => "abc-456"},
        "timeout" => 60000,
        "sampling_enabled" => true
      })
  """
  @spec execute_workflow(Reactor.t(), execution_options()) :: {:ok, term()} | {:error, term()}
  def execute_workflow(workflow, options \\ %{}) do
    # Set up workflow context
    context = build_workflow_context(options)
    
    # Enable streaming if requested
    if Map.get(options, "streaming", false) do
      execute_workflow_with_streaming(workflow, context, options)
    else
      execute_workflow_standard(workflow, context, options)
    end
  end
  
  @doc """
  Executes a workflow with real-time streaming capabilities.
  
  Returns a stream that emits progress events throughout the workflow execution.
  Each event contains step information, status updates, and intermediate results.
  
  ## Stream Events
  
  - `workflow_started`: Workflow execution began
  - `step_started`: Individual step began execution
  - `step_completed`: Individual step completed successfully
  - `step_failed`: Individual step failed with error
  - `workflow_completed`: Workflow completed successfully
  - `workflow_failed`: Workflow failed with error
  
  ## Example
  
      {:ok, stream} = WorkflowAdapter.execute_workflow_stream(workflow, %{
        "context" => %{"user_id" => "123"}
      })
      
      # Process streaming events as they arrive
  """
  @spec execute_workflow_stream(Reactor.t(), execution_options()) :: {:ok, Stream.t()} | {:error, term()}
  def execute_workflow_stream(workflow, options \\ %{}) do
    context = build_workflow_context(options)
    StreamingHandler.create_workflow_stream(workflow, context, options)
  end
  
  @doc """
  Creates a multi-tool operation from MCP tool call specifications.
  
  Enables chaining multiple tool calls in a single MCP request with
  sophisticated parameter passing and result transformation.
  
  ## Example
  
      operation = WorkflowAdapter.create_multi_tool_operation([
        %{"tool" => "data_fetcher", "params" => %{"source" => "api"}},
        %{"tool" => "data_transformer", "params" => %{"format" => "json"}},
        %{"tool" => "data_saver", "params" => %{"destination" => "database"}}
      ])
      
      {:ok, result} = WorkflowAdapter.execute_multi_tool_operation(operation, %{
        "context" => %{"user_id" => "123"}
      })
  """
  @spec create_multi_tool_operation([map()]) :: {:ok, Reactor.t()} | {:error, term()}
  def create_multi_tool_operation(tool_calls) do
    case validate_tool_calls(tool_calls) do
      :ok ->
        # Convert tool calls to workflow steps
        steps = Enum.map(tool_calls, fn %{"tool" => tool_name, "params" => params} ->
          {String.to_atom(tool_name), get_tool_module(tool_name), params}
        end)
        
        # Create sequential workflow
        workflow = Composition.sequential("multi_tool_operation", steps)
        {:ok, workflow}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Executes a multi-tool operation with enhanced parameter transformation.
  
  Automatically handles parameter passing between tools, including result
  filtering, data transformation, and context enrichment.
  """
  @spec execute_multi_tool_operation(Reactor.t(), execution_options()) :: {:ok, term()} | {:error, term()}
  def execute_multi_tool_operation(operation, options \\ %{}) do
    # Enhanced context with tool chaining capabilities
    context = build_multi_tool_context(options)
    
    # Execute with proper parameter transformation
    case Composition.execute(operation, context, timeout: Map.get(options, "timeout", 30_000)) do
      {:ok, result} ->
        # Format result for MCP
        formatted_result = format_multi_tool_result(result, options)
        {:ok, formatted_result}
        
      {:error, reason} ->
        {:error, translate_workflow_error(reason)}
    end
  end
  
  @doc """
  Integrates MCP sampling with workflow execution.
  
  Enables dynamic tool selection and conditional branching based on
  MCP sampling results within workflow steps.
  
  ## Example
  
      sampling_config = %{
        "model" => "gpt-4",
        "prompt" => "Choose the best tool for processing this data",
        "tools" => ["fast_processor", "accurate_processor", "balanced_processor"]
      }
      
      {:ok, selected_tool} = WorkflowAdapter.execute_sampling(sampling_config, %{
        "context" => %{"data_type" => "financial", "priority" => "accuracy"}
      })
  """
  @spec execute_sampling(map(), execution_options()) :: {:ok, String.t()} | {:error, term()}
  def execute_sampling(sampling_config, options \\ %{}) do
    case validate_sampling_config(sampling_config) do
      :ok ->
        # Execute MCP sampling request
        case perform_sampling(sampling_config, options) do
          {:ok, selected_tool} ->
            {:ok, selected_tool}
            
          {:error, reason} ->
            {:error, reason}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Creates reactive workflow triggers based on MCP notifications.
  
  Enables event-driven workflow execution with support for workflow
  resumption and conditional triggers.
  
  ## Example
  
      trigger = WorkflowAdapter.create_reactive_trigger(%{
        "event" => "user_signup",
        "condition" => %{"user_type" => "premium"},
        "workflow" => "premium_onboarding",
        "delay" => 5000
      })
      
      WorkflowAdapter.register_trigger(trigger)
  """
  @spec create_reactive_trigger(map()) :: {:ok, term()} | {:error, term()}
  def create_reactive_trigger(trigger_config) do
    case validate_trigger_config(trigger_config) do
      :ok ->
        # Create trigger with MCP notification integration
        trigger = %{
          id: generate_trigger_id(),
          event: Map.get(trigger_config, "event"),
          condition: Map.get(trigger_config, "condition"),
          workflow: Map.get(trigger_config, "workflow"),
          delay: Map.get(trigger_config, "delay", 0),
          active: true
        }
        
        {:ok, trigger}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Registers a reactive trigger for event-driven workflow execution.
  """
  @spec register_trigger(map()) :: :ok | {:error, term()}
  def register_trigger(trigger) do
    # Subscribe to relevant MCP events
    PubSub.subscribe(RubberDuck.PubSub, "mcp:events:#{trigger.event}")
    
    # Store trigger in registry
    case TemplateRegistry.register_trigger(trigger) do
      :ok ->
        Logger.info("Registered reactive trigger: #{trigger.id}")
        :ok
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Manages cross-tool context sharing within workflows.
  
  Enables persistent state management and context-aware tool interactions
  throughout workflow execution.
  
  ## Example
  
      context = WorkflowAdapter.create_shared_context(%{
        "user_id" => "123",
        "session_id" => "abc-456",
        "preferences" => %{"theme" => "dark", "language" => "en"}
      })
      
      # Context is automatically shared across all workflow steps
      {:ok, result} = WorkflowAdapter.execute_workflow(workflow, %{
        "context" => context
      })
  """
  @spec create_shared_context(map()) :: workflow_context()
  def create_shared_context(initial_context) do
    context_id = generate_context_id()
    
    %{
      id: context_id,
      data: initial_context,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      version: 1
    }
  end
  
  @doc """
  Retrieves available workflow templates from the registry.
  
  Templates provide reusable patterns for common workflow types and
  can be parameterized for different contexts.
  
  ## Example
  
      templates = WorkflowAdapter.list_workflow_templates()
      
      # Find a specific template
      template = Enum.find(templates, & &1.name == "data_processing_pipeline")
      
      # Create workflow from template
      {:ok, workflow} = WorkflowAdapter.create_workflow_from_template(template, %{
        "source" => "api",
        "destination" => "database"
      })
  """
  @spec list_workflow_templates() :: [map()]
  def list_workflow_templates do
    TemplateRegistry.list_templates()
  end
  
  @doc """
  Creates a workflow from a template with parameter substitution.
  """
  @spec create_workflow_from_template(map(), map()) :: {:ok, Reactor.t()} | {:error, term()}
  def create_workflow_from_template(template, params) do
    case TemplateRegistry.instantiate_template(template, params) do
      {:ok, workflow_definition} ->
        create_workflow(template.name, workflow_definition)
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Private helper functions
  
  defp validate_workflow_definition(definition) do
    required_fields = ["type"]
    
    case Enum.find(required_fields, &(!Map.has_key?(definition, &1))) do
      nil -> :ok
      missing_field -> {:error, "Missing required field: #{missing_field}"}
    end
  end
  
  defp create_sequential_workflow(workflow_id, definition) do
    steps = Map.get(definition, "steps", [])
    
    case convert_steps_to_composition(steps) do
      {:ok, composition_steps} ->
        workflow = Composition.sequential(workflow_id, composition_steps)
        {:ok, workflow}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp create_parallel_workflow(workflow_id, definition) do
    steps = Map.get(definition, "steps", [])
    merge_step = Map.get(definition, "merge_step")
    
    case convert_steps_to_composition(steps) do
      {:ok, composition_steps} ->
        opts = if merge_step, do: [merge_step: convert_merge_step(merge_step)], else: []
        workflow = Composition.parallel(workflow_id, composition_steps, opts)
        {:ok, workflow}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp create_conditional_workflow(workflow_id, definition) do
    condition = Map.get(definition, "condition")
    success_steps = Map.get(definition, "success", [])
    failure_steps = Map.get(definition, "failure", [])
    
    with {:ok, condition_step} <- convert_step_to_composition(condition),
         {:ok, success_composition} <- convert_steps_to_composition(success_steps),
         {:ok, failure_composition} <- convert_steps_to_composition(failure_steps) do
      
      opts = [
        condition: condition_step,
        success: success_composition,
        failure: failure_composition
      ]
      
      workflow = Composition.conditional(workflow_id, opts)
      {:ok, workflow}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp create_loop_workflow(workflow_id, definition) do
    items = Map.get(definition, "items", [])
    steps = Map.get(definition, "steps", [])
    aggregator = Map.get(definition, "aggregator")
    
    case convert_steps_to_composition(steps) do
      {:ok, composition_steps} ->
        opts = [
          items: items,
          steps: composition_steps
        ]
        
        opts = if aggregator, do: Keyword.put(opts, :aggregator, convert_aggregator(aggregator)), else: opts
        
        workflow = Composition.loop(workflow_id, opts)
        {:ok, workflow}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp create_reactive_workflow(workflow_id, definition) do
    # Enhanced reactive workflow with MCP integration
    triggers = Map.get(definition, "triggers", [])
    base_workflow = Map.get(definition, "workflow")
    
    case create_workflow(workflow_id <> "_base", base_workflow) do
      {:ok, base} ->
        # Add reactive triggers to the workflow
        enhanced_workflow = add_reactive_triggers(base, triggers)
        {:ok, enhanced_workflow}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp create_template_workflow(_workflow_id, definition) do
    template_name = Map.get(definition, "template")
    params = Map.get(definition, "params", %{})
    
    case TemplateRegistry.get_template(template_name) do
      {:ok, template} ->
        create_workflow_from_template(template, params)
        
      {:error, :not_found} ->
        {:error, "Template not found: #{template_name}"}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp convert_steps_to_composition(steps) do
    converted_steps = Enum.map(steps, fn step ->
      case convert_step_to_composition(step) do
        {:ok, converted} -> converted
        {:error, reason} -> {:error, reason}
      end
    end)
    
    case Enum.find(converted_steps, &match?({:error, _}, &1)) do
      nil -> {:ok, converted_steps}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp convert_step_to_composition(step) do
    tool_name = Map.get(step, "tool")
    params = Map.get(step, "params", %{})
    
    case get_tool_module(tool_name) do
      {:ok, module} ->
        step_name = String.to_atom(tool_name)
        {:ok, {step_name, module, params}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp get_tool_module(tool_name) do
    case RubberDuck.Tool.Registry.get(String.to_atom(tool_name)) do
      {:ok, tool_info} ->
        module = tool_info[:module] || tool_info.module
        {:ok, module}
        
      {:error, :not_found} ->
        {:error, "Tool not found: #{tool_name}"}
    end
  end
  
  defp convert_merge_step(merge_step) do
    tool_name = Map.get(merge_step, "tool")
    params = Map.get(merge_step, "params", %{})
    
    case get_tool_module(tool_name) do
      {:ok, module} ->
        {String.to_atom(tool_name), module, params}
        
      {:error, _} ->
        # Return a default merge step if tool not found
        {:merge, RubberDuck.Tool.Composition.DefaultMerger, params}
    end
  end
  
  defp convert_aggregator(aggregator) do
    convert_merge_step(aggregator)
  end
  
  defp build_workflow_context(options) do
    base_context = %{
      mcp_enhanced: true,
      streaming: Map.get(options, "streaming", false),
      sampling_enabled: Map.get(options, "sampling_enabled", false),
      created_at: DateTime.utc_now()
    }
    
    user_context = Map.get(options, "context", %{})
    Map.merge(base_context, user_context)
  end
  
  defp execute_workflow_standard(workflow, context, options) do
    timeout = Map.get(options, "timeout", 30_000)
    
    case Composition.execute(workflow, context, timeout: timeout) do
      {:ok, result} ->
        formatted_result = format_workflow_result(result, options)
        {:ok, formatted_result}
        
      {:error, reason} ->
        {:error, translate_workflow_error(reason)}
    end
  end
  
  defp execute_workflow_with_streaming(workflow, context, options) do
    case StreamingHandler.execute_with_streaming(workflow, context, options) do
      {:ok, result} ->
        formatted_result = format_workflow_result(result, options)
        {:ok, formatted_result}
        
      {:error, reason} ->
        {:error, translate_workflow_error(reason)}
    end
  end
  
  defp build_multi_tool_context(options) do
    base_context = build_workflow_context(options)
    
    Map.merge(base_context, %{
      multi_tool_operation: true,
      parameter_chaining: true,
      result_transformation: true
    })
  end
  
  defp validate_tool_calls(tool_calls) do
    case Enum.find(tool_calls, fn call ->
      !Map.has_key?(call, "tool") || !Map.has_key?(call, "params")
    end) do
      nil -> :ok
      _invalid_call -> {:error, "Invalid tool call format"}
    end
  end
  
  defp validate_sampling_config(config) do
    required_fields = ["model", "prompt", "tools"]
    
    case Enum.find(required_fields, &(!Map.has_key?(config, &1))) do
      nil -> :ok
      missing_field -> {:error, "Missing required sampling field: #{missing_field}"}
    end
  end
  
  defp validate_trigger_config(config) do
    required_fields = ["event", "workflow"]
    
    case Enum.find(required_fields, &(!Map.has_key?(config, &1))) do
      nil -> :ok
      missing_field -> {:error, "Missing required trigger field: #{missing_field}"}
    end
  end
  
  defp perform_sampling(sampling_config, _options) do
    # Placeholder for MCP sampling integration
    # In real implementation, this would call the MCP sampling endpoint
    tools = Map.get(sampling_config, "tools", [])
    
    case tools do
      [] -> {:error, "No tools available for sampling"}
      [single_tool] -> {:ok, single_tool}
      multiple_tools -> {:ok, Enum.random(multiple_tools)}
    end
  end
  
  defp add_reactive_triggers(workflow, _triggers) do
    # Add reactive capabilities to the workflow
    # This would integrate with the MCP notification system
    workflow
  end
  
  defp format_workflow_result(result, options) do
    base_result = %{
      "result" => result,
      "execution_time" => DateTime.utc_now(),
      "mcp_enhanced" => true
    }
    
    if Map.get(options, "include_metadata", false) do
      Map.put(base_result, "metadata", %{
        "workflow_type" => "mcp_enhanced",
        "streaming_enabled" => Map.get(options, "streaming", false),
        "context_sharing" => Map.get(options, "context") != nil
      })
    else
      base_result
    end
  end
  
  defp format_multi_tool_result(result, options) do
    base_result = format_workflow_result(result, options)
    
    Map.put(base_result, "operation_type", "multi_tool")
  end
  
  defp translate_workflow_error(reason) do
    case reason do
      {:timeout, _} -> "Workflow execution timed out"
      {:tool_error, error} -> "Tool execution failed: #{inspect(error)}"
      {:validation_error, error} -> "Validation failed: #{inspect(error)}"
      other -> "Workflow execution failed: #{inspect(other)}"
    end
  end
  
  defp generate_trigger_id do
    "trigger_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
  
  defp generate_context_id do
    "context_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
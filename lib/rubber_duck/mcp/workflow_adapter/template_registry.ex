defmodule RubberDuck.MCP.WorkflowAdapter.TemplateRegistry do
  @moduledoc """
  Registry for workflow templates and reactive triggers.
  
  Provides a library of reusable workflow patterns that can be instantiated
  with different parameters. Also manages reactive triggers for event-driven
  workflow execution.
  
  ## Template Features
  
  - **Parameterization**: Templates can be customized with runtime parameters
  - **Composition**: Templates can include other templates for reusability
  - **Validation**: Parameter validation ensures correct template usage
  - **Versioning**: Template versions for backward compatibility
  - **Categories**: Organize templates by functional categories
  
  ## Example Templates
  
  - Data Processing Pipeline
  - User Onboarding Flow
  - Content Moderation Workflow
  - Batch Processing Template
  - API Integration Pattern
  """
  
  use GenServer
  
  require Logger
  
  @type template_id :: String.t()
  @type template_name :: String.t()
  @type template_version :: String.t()
  @type template_params :: map()
  
  @type template :: %{
    id: template_id(),
    name: template_name(),
    version: template_version(),
    description: String.t(),
    category: String.t(),
    parameters: [map()],
    definition: map(),
    examples: [map()],
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    metadata: map()
  }
  
  @type trigger :: %{
    id: String.t(),
    event: String.t(),
    condition: map() | nil,
    workflow: String.t(),
    delay: integer(),
    active: boolean(),
    created_at: DateTime.t(),
    metadata: map()
  }
  
  # Client API
  
  @doc """
  Starts the template registry.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a workflow template.
  
  ## Example
  
      template = %{
        name: "data_processing_pipeline",
        version: "1.0.0",
        description: "Standard data processing workflow",
        category: "data_processing",
        parameters: [
          %{name: "source", type: "string", required: true},
          %{name: "destination", type: "string", required: true}
        ],
        definition: %{
          "type" => "sequential",
          "steps" => [
            %{"tool" => "data_fetcher", "params" => %{"source" => "{{source}}"}},
            %{"tool" => "data_transformer", "params" => %{"format" => "json"}},
            %{"tool" => "data_saver", "params" => %{"destination" => "{{destination}}"}}
          ]
        }
      }
      
      {:ok, registered_template} = TemplateRegistry.register_template(template)
  """
  @spec register_template(map()) :: {:ok, template()} | {:error, term()}
  def register_template(template_data) do
    GenServer.call(__MODULE__, {:register_template, template_data})
  end
  
  @doc """
  Retrieves a template by name.
  
  ## Example
  
      {:ok, template} = TemplateRegistry.get_template("data_processing_pipeline")
  """
  @spec get_template(template_name()) :: {:ok, template()} | {:error, term()}
  def get_template(template_name) do
    GenServer.call(__MODULE__, {:get_template, template_name})
  end
  
  @doc """
  Retrieves a specific version of a template.
  
  ## Example
  
      {:ok, template} = TemplateRegistry.get_template("data_processing_pipeline", "1.0.0")
  """
  @spec get_template(template_name(), template_version()) :: {:ok, template()} | {:error, term()}
  def get_template(template_name, version) do
    GenServer.call(__MODULE__, {:get_template, template_name, version})
  end
  
  @doc """
  Lists all available templates.
  
  ## Options
  
  - `category`: Filter by category
  - `limit`: Maximum number of templates to return
  
  ## Example
  
      templates = TemplateRegistry.list_templates(category: "data_processing")
  """
  @spec list_templates(keyword()) :: [template()]
  def list_templates(opts \\ []) do
    GenServer.call(__MODULE__, {:list_templates, opts})
  end
  
  @doc """
  Instantiates a template with the given parameters.
  
  Replaces template placeholders with actual values and validates
  that all required parameters are provided.
  
  ## Example
  
      {:ok, workflow_definition} = TemplateRegistry.instantiate_template(
        "data_processing_pipeline",
        %{"source" => "api", "destination" => "database"}
      )
  """
  @spec instantiate_template(template_name(), template_params()) :: {:ok, map()} | {:error, term()}
  def instantiate_template(template_name, params) do
    GenServer.call(__MODULE__, {:instantiate_template, template_name, params})
  end
  
  @doc """
  Instantiates a template struct with parameters.
  """
  @spec instantiate_template_struct(template(), template_params()) :: {:ok, map()} | {:error, term()}
  def instantiate_template_struct(template, params) do
    GenServer.call(__MODULE__, {:instantiate_template_struct, template, params})
  end
  
  @doc """
  Registers a reactive trigger.
  
  ## Example
  
      trigger = %{
        event: "user_signup",
        condition: %{"user_type" => "premium"},
        workflow: "premium_onboarding",
        delay: 5000
      }
      
      :ok = TemplateRegistry.register_trigger(trigger)
  """
  @spec register_trigger(map()) :: :ok | {:error, term()}
  def register_trigger(trigger_data) do
    GenServer.call(__MODULE__, {:register_trigger, trigger_data})
  end
  
  @doc """
  Lists all registered triggers.
  
  ## Example
  
      triggers = TemplateRegistry.list_triggers()
  """
  @spec list_triggers() :: [trigger()]
  def list_triggers do
    GenServer.call(__MODULE__, :list_triggers)
  end
  
  @doc """
  Gets triggers for a specific event.
  
  ## Example
  
      triggers = TemplateRegistry.get_triggers_for_event("user_signup")
  """
  @spec get_triggers_for_event(String.t()) :: [trigger()]
  def get_triggers_for_event(event) do
    GenServer.call(__MODULE__, {:get_triggers_for_event, event})
  end
  
  @doc """
  Removes a trigger.
  
  ## Example
  
      :ok = TemplateRegistry.remove_trigger("trigger_abc123")
  """
  @spec remove_trigger(String.t()) :: :ok | {:error, term()}
  def remove_trigger(trigger_id) do
    GenServer.call(__MODULE__, {:remove_trigger, trigger_id})
  end
  
  # Server implementation
  
  @impl GenServer
  def init(opts) do
    # Initialize storage
    templates_table = :ets.new(:workflow_templates, [:set, :public, :named_table])
    triggers_table = :ets.new(:workflow_triggers, [:set, :public, :named_table])
    
    state = %{
      templates_table: templates_table,
      triggers_table: triggers_table,
      auto_load: Keyword.get(opts, :auto_load, true)
    }
    
    # Load built-in templates if enabled
    if state.auto_load do
      load_built_in_templates(state)
    end
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:register_template, template_data}, _from, state) do
    case validate_template(template_data) do
      :ok ->
        template = build_template(template_data)
        :ets.insert(state.templates_table, {template.name, template})
        {:reply, {:ok, template}, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:get_template, template_name}, _from, state) do
    case :ets.lookup(state.templates_table, template_name) do
      [{^template_name, template}] ->
        {:reply, {:ok, template}, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:get_template, template_name, version}, _from, state) do
    case :ets.lookup(state.templates_table, template_name) do
      [{^template_name, template}] ->
        if template.version == version do
          {:reply, {:ok, template}, state}
        else
          {:reply, {:error, :version_not_found}, state}
        end
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:list_templates, opts}, _from, state) do
    all_templates = :ets.tab2list(state.templates_table)
    |> Enum.map(fn {_name, template} -> template end)
    
    # Apply filters
    filtered_templates = apply_template_filters(all_templates, opts)
    
    {:reply, filtered_templates, state}
  end
  
  @impl GenServer
  def handle_call({:instantiate_template, template_name, params}, _from, state) do
    case :ets.lookup(state.templates_table, template_name) do
      [{^template_name, template}] ->
        result = instantiate_template_internal(template, params)
        {:reply, result, state}
        
      [] ->
        {:reply, {:error, :template_not_found}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:instantiate_template_struct, template, params}, _from, state) do
    result = instantiate_template_internal(template, params)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:register_trigger, trigger_data}, _from, state) do
    case validate_trigger(trigger_data) do
      :ok ->
        trigger = build_trigger(trigger_data)
        :ets.insert(state.triggers_table, {trigger.id, trigger})
        {:reply, :ok, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:list_triggers, _from, state) do
    triggers = :ets.tab2list(state.triggers_table)
    |> Enum.map(fn {_id, trigger} -> trigger end)
    
    {:reply, triggers, state}
  end
  
  @impl GenServer
  def handle_call({:get_triggers_for_event, event}, _from, state) do
    triggers = :ets.tab2list(state.triggers_table)
    |> Enum.map(fn {_id, trigger} -> trigger end)
    |> Enum.filter(fn trigger -> trigger.event == event and trigger.active end)
    
    {:reply, triggers, state}
  end
  
  @impl GenServer
  def handle_call({:remove_trigger, trigger_id}, _from, state) do
    case :ets.lookup(state.triggers_table, trigger_id) do
      [{^trigger_id, _trigger}] ->
        :ets.delete(state.triggers_table, trigger_id)
        {:reply, :ok, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  # Private helper functions
  
  defp load_built_in_templates(state) do
    built_in_templates = [
      data_processing_pipeline_template(),
      user_onboarding_template(),
      content_moderation_template(),
      batch_processing_template(),
      api_integration_template()
    ]
    
    Enum.each(built_in_templates, fn template ->
      :ets.insert(state.templates_table, {template.name, template})
    end)
    
    Logger.info("Loaded #{length(built_in_templates)} built-in workflow templates")
  end
  
  defp validate_template(template_data) do
    required_fields = ["name", "version", "description", "definition"]
    
    case Enum.find(required_fields, &(!Map.has_key?(template_data, &1))) do
      nil -> :ok
      missing_field -> {:error, "Missing required field: #{missing_field}"}
    end
  end
  
  defp validate_trigger(trigger_data) do
    required_fields = ["event", "workflow"]
    
    case Enum.find(required_fields, &(!Map.has_key?(trigger_data, &1))) do
      nil -> :ok
      missing_field -> {:error, "Missing required field: #{missing_field}"}
    end
  end
  
  defp build_template(template_data) do
    %{
      id: generate_template_id(),
      name: Map.get(template_data, "name"),
      version: Map.get(template_data, "version"),
      description: Map.get(template_data, "description"),
      category: Map.get(template_data, "category", "general"),
      parameters: Map.get(template_data, "parameters", []),
      definition: Map.get(template_data, "definition"),
      examples: Map.get(template_data, "examples", []),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      metadata: Map.get(template_data, "metadata", %{})
    }
  end
  
  defp build_trigger(trigger_data) do
    %{
      id: generate_trigger_id(),
      event: Map.get(trigger_data, "event"),
      condition: Map.get(trigger_data, "condition"),
      workflow: Map.get(trigger_data, "workflow"),
      delay: Map.get(trigger_data, "delay", 0),
      active: Map.get(trigger_data, "active", true),
      created_at: DateTime.utc_now(),
      metadata: Map.get(trigger_data, "metadata", %{})
    }
  end
  
  defp instantiate_template_internal(template, params) do
    case validate_template_params(template, params) do
      :ok ->
        # Replace placeholders in the template definition
        instantiated_definition = replace_placeholders(template.definition, params)
        {:ok, instantiated_definition}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp validate_template_params(template, params) do
    required_params = template.parameters
    |> Enum.filter(fn param -> Map.get(param, "required", false) end)
    |> Enum.map(fn param -> Map.get(param, "name") end)
    
    provided_params = Map.keys(params)
    
    missing_params = required_params -- provided_params
    
    if Enum.empty?(missing_params) do
      :ok
    else
      {:error, "Missing required parameters: #{Enum.join(missing_params, ", ")}"}
    end
  end
  
  defp replace_placeholders(definition, params) when is_map(definition) do
    Map.new(definition, fn {key, value} ->
      {key, replace_placeholders(value, params)}
    end)
  end
  
  defp replace_placeholders(definition, params) when is_list(definition) do
    Enum.map(definition, fn item ->
      replace_placeholders(item, params)
    end)
  end
  
  defp replace_placeholders(definition, params) when is_binary(definition) do
    # Replace {{param_name}} with actual values
    Enum.reduce(params, definition, fn {param_name, param_value}, acc ->
      placeholder = "{{#{param_name}}}"
      String.replace(acc, placeholder, to_string(param_value))
    end)
  end
  
  defp replace_placeholders(definition, _params), do: definition
  
  defp apply_template_filters(templates, opts) do
    templates
    |> filter_by_category(Keyword.get(opts, :category))
    |> limit_results(Keyword.get(opts, :limit))
  end
  
  defp filter_by_category(templates, nil), do: templates
  defp filter_by_category(templates, category) do
    Enum.filter(templates, fn template -> template.category == category end)
  end
  
  defp limit_results(templates, nil), do: templates
  defp limit_results(templates, limit) do
    Enum.take(templates, limit)
  end
  
  defp generate_template_id do
    "template_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
  
  defp generate_trigger_id do
    "trigger_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
  
  # Built-in template definitions
  
  defp data_processing_pipeline_template do
    %{
      id: "template_data_processing_pipeline",
      name: "data_processing_pipeline",
      version: "1.0.0",
      description: "Standard data processing workflow with fetch, transform, and save steps",
      category: "data_processing",
      parameters: [
        %{"name" => "source", "type" => "string", "required" => true, "description" => "Data source"},
        %{"name" => "destination", "type" => "string", "required" => true, "description" => "Data destination"},
        %{"name" => "format", "type" => "string", "required" => false, "default" => "json", "description" => "Data format"}
      ],
      definition: %{
        "type" => "sequential",
        "steps" => [
          %{"tool" => "data_fetcher", "params" => %{"source" => "{{source}}"}},
          %{"tool" => "data_transformer", "params" => %{"format" => "{{format}}"}},
          %{"tool" => "data_saver", "params" => %{"destination" => "{{destination}}"}}
        ]
      },
      examples: [
        %{
          "name" => "API to Database",
          "params" => %{"source" => "api", "destination" => "database", "format" => "json"}
        }
      ],
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      metadata: %{"tags" => ["data", "etl", "pipeline"]}
    }
  end
  
  defp user_onboarding_template do
    %{
      id: "template_user_onboarding",
      name: "user_onboarding",
      version: "1.0.0",
      description: "User onboarding workflow with conditional paths",
      category: "user_management",
      parameters: [
        %{"name" => "user_type", "type" => "string", "required" => true, "description" => "Type of user"},
        %{"name" => "welcome_template", "type" => "string", "required" => false, "default" => "standard", "description" => "Welcome template"}
      ],
      definition: %{
        "type" => "conditional",
        "condition" => %{
          "tool" => "user_validator",
          "params" => %{"user_type" => "{{user_type}}"}
        },
        "success" => [
          %{"tool" => "welcome_service", "params" => %{"template" => "{{welcome_template}}"}},
          %{"tool" => "notification_service", "params" => %{"event" => "user_welcomed"}}
        ],
        "failure" => [
          %{"tool" => "rejection_service", "params" => %{"reason" => "validation_failed"}}
        ]
      },
      examples: [
        %{
          "name" => "Premium User Onboarding",
          "params" => %{"user_type" => "premium", "welcome_template" => "premium"}
        }
      ],
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      metadata: %{"tags" => ["user", "onboarding", "conditional"]}
    }
  end
  
  defp content_moderation_template do
    %{
      id: "template_content_moderation",
      name: "content_moderation",
      version: "1.0.0",
      description: "Content moderation workflow with parallel analysis",
      category: "content_management",
      parameters: [
        %{"name" => "content_type", "type" => "string", "required" => true, "description" => "Type of content"},
        %{"name" => "strictness", "type" => "string", "required" => false, "default" => "medium", "description" => "Moderation strictness"}
      ],
      definition: %{
        "type" => "parallel",
        "steps" => [
          %{"tool" => "text_analyzer", "params" => %{"strictness" => "{{strictness}}"}},
          %{"tool" => "image_analyzer", "params" => %{"content_type" => "{{content_type}}"}},
          %{"tool" => "spam_detector", "params" => %{"threshold" => "0.8"}}
        ],
        "merge_step" => %{
          "tool" => "moderation_aggregator",
          "params" => %{"strategy" => "consensus"}
        }
      },
      examples: [
        %{
          "name" => "Strict Image Moderation",
          "params" => %{"content_type" => "image", "strictness" => "high"}
        }
      ],
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      metadata: %{"tags" => ["content", "moderation", "parallel"]}
    }
  end
  
  defp batch_processing_template do
    %{
      id: "template_batch_processing",
      name: "batch_processing",
      version: "1.0.0",
      description: "Batch processing workflow for collections",
      category: "data_processing",
      parameters: [
        %{"name" => "batch_size", "type" => "integer", "required" => false, "default" => 10, "description" => "Batch size"},
        %{"name" => "max_concurrent", "type" => "integer", "required" => false, "default" => 3, "description" => "Max concurrent batches"}
      ],
      definition: %{
        "type" => "loop",
        "steps" => [
          %{"tool" => "item_processor", "params" => %{"batch_size" => "{{batch_size}}"}},
          %{"tool" => "item_validator", "params" => %{"strict" => false}}
        ],
        "aggregator" => %{
          "tool" => "batch_aggregator",
          "params" => %{"strategy" => "merge"}
        }
      },
      examples: [
        %{
          "name" => "Large Batch Processing",
          "params" => %{"batch_size" => 50, "max_concurrent" => 5}
        }
      ],
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      metadata: %{"tags" => ["batch", "processing", "loop"]}
    }
  end
  
  defp api_integration_template do
    %{
      id: "template_api_integration",
      name: "api_integration",
      version: "1.0.0",
      description: "API integration workflow with error handling",
      category: "integration",
      parameters: [
        %{"name" => "api_endpoint", "type" => "string", "required" => true, "description" => "API endpoint"},
        %{"name" => "retry_count", "type" => "integer", "required" => false, "default" => 3, "description" => "Retry attempts"}
      ],
      definition: %{
        "type" => "sequential",
        "steps" => [
          %{"tool" => "api_caller", "params" => %{"endpoint" => "{{api_endpoint}}", "retries" => "{{retry_count}}"}},
          %{"tool" => "response_validator", "params" => %{"strict" => true}},
          %{"tool" => "response_transformer", "params" => %{"format" => "normalized"}}
        ]
      },
      examples: [
        %{
          "name" => "External API Integration",
          "params" => %{"api_endpoint" => "https://api.example.com/data", "retry_count" => 5}
        }
      ],
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      metadata: %{"tags" => ["api", "integration", "error_handling"]}
    }
  end
end
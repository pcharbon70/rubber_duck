defmodule RubberDuck.Agents.PromptManagerAgent do
  @moduledoc """
  Prompt Manager Agent for handling prompt templates, dynamic construction, 
  A/B testing, and analytics.
  
  This agent serves as the central hub for all prompt-related operations in
  the RubberDuck system, providing:
  
  - Template storage and management
  - Dynamic prompt construction with variable substitution
  - A/B testing framework for prompt optimization
  - Analytics and performance tracking
  - Caching for improved performance
  
  ## Actions
  
  The agent supports the following actions through the Jido pattern:
  
  ### Template Management
  - `CreateTemplateAction`: Create a new prompt template
  - `UpdateTemplateAction`: Update an existing template
  - `DeleteTemplateAction`: Remove a template
  - `GetTemplateAction`: Retrieve a template by ID
  - `ListTemplatesAction`: List available templates with filtering
  
  ### Prompt Building
  - `BuildPromptAction`: Construct a prompt from template and context
  - `ValidateTemplateAction`: Validate template structure and variables
  
  ### Analytics
  - `GetAnalyticsAction`: Retrieve performance metrics for templates
  - `GetUsageStatsAction`: Get usage statistics for a specific template
  - `OptimizeTemplateAction`: Get optimization recommendations
  
  ### System Operations
  - `GetStatusAction`: Retrieve agent health and status information
  - `ClearCacheAction`: Clear the agent's cache
  """

  use Jido.Agent,
    name: "prompt_manager",
    description: "Manages prompt templates, construction, and optimization",
    schema: [
      templates: [type: :map, default: %{}],
      experiments: [type: :map, default: %{}],
      analytics: [type: :map, default: %{}],
      cache: [type: :map, default: %{}],
      config: [type: :map, default: %{
        cache_ttl: 3600,
        max_templates: 1000,
        analytics_retention_days: 30,
        default_optimization: true
      }]
    ],
    actions: [
      RubberDuck.Jido.Actions.PromptManager.CreateTemplateAction,
      RubberDuck.Jido.Actions.PromptManager.UpdateTemplateAction,
      RubberDuck.Jido.Actions.PromptManager.DeleteTemplateAction,
      RubberDuck.Jido.Actions.PromptManager.GetTemplateAction,
      RubberDuck.Jido.Actions.PromptManager.ListTemplatesAction,
      RubberDuck.Jido.Actions.PromptManager.BuildPromptAction,
      RubberDuck.Jido.Actions.PromptManager.ValidateTemplateAction,
      RubberDuck.Jido.Actions.PromptManager.GetAnalyticsAction,
      RubberDuck.Jido.Actions.PromptManager.GetUsageStatsAction,
      RubberDuck.Jido.Actions.PromptManager.OptimizeTemplateAction,
      RubberDuck.Jido.Actions.PromptManager.GetStatusAction,
      RubberDuck.Jido.Actions.PromptManager.ClearCacheAction
    ]

  alias RubberDuck.Agents.ErrorHandling
  alias RubberDuck.Agents.Prompt.Template
  require Logger

  @impl true
  def mount(opts, initial_state) do
    ErrorHandling.safe_execute(fn ->
      Logger.info("Mounting prompt manager agent", opts: opts)
      
      # Initialize with configuration validation
      case safe_build_config(opts, initial_state) do
        {:ok, config} ->
          # Initialize default templates with error handling
          case safe_create_default_templates() do
            {:ok, templates} ->
              state = %{
                templates: templates,
                experiments: %{},
                analytics: %{},
                cache: %{},
                config: config
              }
              
              # Start periodic cleanup task
              safe_schedule_cleanup()
              
              Logger.info("PromptManagerAgent mounted successfully", template_count: map_size(templates))
              {:ok, state}
              
            {:error, error} -> ErrorHandling.categorize_error(error)
          end
          
        {:error, error} -> ErrorHandling.categorize_error(error)
      end
    end)
  end

  # All signal handling is now managed through actions
  # The actions are defined in the actions list above and handle all operations

  # GenServer callbacks for periodic tasks

  @impl true
  def handle_info(:cleanup, %{state: state} = agent) do
    case ErrorHandling.safe_execute(fn ->
      Logger.debug("Running periodic cleanup")
      
      # Perform cleanup operations with error handling
      case safe_cleanup_expired_cache(state) do
        {:ok, updated_state} ->
          case safe_cleanup_old_analytics(updated_state) do
            {:ok, final_state} ->
              safe_schedule_cleanup()
              Logger.debug("Periodic cleanup completed successfully")
              {:ok, final_state}
            {:error, error} ->
              Logger.warning("Analytics cleanup failed: #{inspect(error)}")
              {:ok, updated_state}  # Continue with cache cleanup even if analytics fails
          end
        {:error, error} ->
          Logger.warning("Cache cleanup failed: #{inspect(error)}")
          {:ok, state}  # Return original state if cleanup fails
      end
    end) do
      {:ok, updated_state} ->
        {:noreply, %{agent | state: updated_state}}
      {:error, error} ->
        Logger.error("Cleanup task failed: #{inspect(error)}")
        safe_schedule_cleanup()  # Reschedule even on failure
        {:noreply, agent}
    end
  end

  # Private helper functions
  
  # Configuration validation and building
  defp safe_build_config(opts, initial_state) do
    try do
      base_config = %{
        cache_ttl: 3600,
        max_templates: 1000,
        analytics_retention_days: 30,
        default_optimization: true
      }
      
      # Merge with provided options
      config = if is_map(initial_state) and is_map(initial_state[:config]) do
        Map.merge(base_config, initial_state.config)
      else
        base_config
      end |> Map.merge(Map.new(opts))
      
      case validate_config(config) do
        :ok -> {:ok, config}
        error -> error
      end
    rescue
      error -> ErrorHandling.system_error("Failed to build configuration: #{Exception.message(error)}", %{opts: opts})
    end
  end
  
  defp validate_config(%{cache_ttl: ttl, max_templates: max, analytics_retention_days: retention}) 
       when is_integer(ttl) and ttl > 0 and is_integer(max) and max > 0 and is_integer(retention) and retention > 0 do
    :ok
  end
  defp validate_config(config), do: ErrorHandling.validation_error("Invalid configuration values", %{config: config})
  
  # Safe template creation
  defp safe_create_default_templates do
    try do
      templates = create_default_templates()
      {:ok, templates}
    rescue
      error -> ErrorHandling.system_error("Failed to create default templates: #{Exception.message(error)}", %{})
    end
  end
  
  # Safe cleanup operations
  defp safe_cleanup_expired_cache(state) do
    try do
      updated_state = cleanup_expired_cache(state)
      {:ok, updated_state}
    rescue
      error -> {:error, "Cache cleanup failed: #{Exception.message(error)}"}
    end
  end
  
  defp safe_cleanup_old_analytics(state) do
    try do
      updated_state = cleanup_old_analytics(state)
      {:ok, updated_state}
    rescue
      error -> {:error, "Analytics cleanup failed: #{Exception.message(error)}"}
    end
  end
  
  defp safe_schedule_cleanup do
    try do
      schedule_cleanup()
    rescue
      error -> Logger.error("Failed to schedule cleanup: #{Exception.message(error)}")
    end
  end

  defp create_default_templates do
    templates = [
      %{
        name: "Code Review",
        description: "Template for reviewing code submissions",
        content: "Please review this {{language}} code for:\n1. Correctness\n2. Performance\n3. Best practices\n\nCode:\n```{{language}}\n{{code}}\n```\n\nProvide specific feedback and suggestions.",
        variables: [
          %{name: "language", type: :string, required: true, description: "Programming language"},
          %{name: "code", type: :string, required: true, description: "Code to review"}
        ],
        category: "coding",
        tags: ["review", "analysis", "code"],
        access_level: :public
      },
      %{
        name: "Text Summarization",
        description: "Template for summarizing text content",
        content: "Summarize the following text in {{summary_length|3}} sentences:\n\n{{text}}\n\nSummary:",
        variables: [
          %{name: "text", type: :string, required: true, description: "Text to summarize"},
          %{name: "summary_length", type: :integer, required: false, default: 3, description: "Number of sentences"}
        ],
        category: "analysis",
        tags: ["summary", "text", "analysis"],
        access_level: :public
      }
    ]
    
    templates
    |> Enum.map(fn template_data ->
      case Template.new(template_data) do
        {:ok, template} -> {template.id, template}
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  # Utility functions used by actions and internal operations

  defp cleanup_expired_cache(state) do
    now = DateTime.utc_now()
    
    valid_cache = state.cache
    |> Enum.filter(fn {_key, entry} ->
      DateTime.compare(now, entry.expires_at) == :lt
    end)
    |> Map.new()
    
    put_in(state.cache, valid_cache)
  end

  defp cleanup_old_analytics(state) do
    # Remove analytics older than retention period
    _cutoff_date = DateTime.add(DateTime.utc_now(), -state.config.analytics_retention_days, :day)
    
    # Simplified cleanup - in production would be more sophisticated
    state
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 300_000)  # Every 5 minutes
  end
end
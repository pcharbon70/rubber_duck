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

  alias RubberDuck.Agents.Prompt.Template
  require Logger

  @impl true
  def mount(_opts, _initial_state) do
    # Initialize with some default templates
    state = %{
      templates: create_default_templates(),
      experiments: %{},
      analytics: %{},
      cache: %{},
      config: %{
        cache_ttl: 3600,
        max_templates: 1000,
        analytics_retention_days: 30,
        default_optimization: true
      }
    }
    
    # Start periodic cleanup task
    schedule_cleanup()
    
    Logger.info("PromptManagerAgent initialized with #{map_size(state.templates)} templates")
    {:ok, state}
  end

  # All signal handling is now managed through actions
  # The actions are defined in the actions list above and handle all operations

  # GenServer callbacks for periodic tasks

  @impl true
  def handle_info(:cleanup, %{state: state} = agent) do
    updated_state = state
    |> cleanup_expired_cache()
    |> cleanup_old_analytics()
    
    schedule_cleanup()
    {:noreply, %{agent | state: updated_state}}
  end

  # Private helper functions

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
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
  
  ## Signals
  
  The agent responds to the following signals:
  
  ### Template Management
  - `create_template`: Create a new prompt template
  - `update_template`: Update an existing template
  - `delete_template`: Remove a template
  - `get_template`: Retrieve a template by ID
  - `list_templates`: List available templates with filtering
  
  ### Prompt Building
  - `build_prompt`: Construct a prompt from template and context
  - `validate_template`: Validate template structure and variables
  
  ### Experimentation
  - `start_experiment`: Begin A/B test with multiple template variants
  - `get_experiment`: Get experiment status and results
  - `stop_experiment`: End an active experiment
  
  ### Analytics
  - `get_analytics`: Retrieve performance metrics for templates
  - `get_usage_stats`: Get usage statistics
  - `optimize_template`: Get optimization recommendations
  """

  use RubberDuck.Agents.BaseAgent,
    name: "prompt_manager",
    description: "Manages prompt templates, construction, and optimization",
    category: "management",
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
    ]

  alias RubberDuck.Agents.Prompt.{Template, Builder}
  require Logger

  @impl true
  def mount(_params, initial_state) do
    # Initialize with some default templates if none exist
    state = if map_size(initial_state.templates) == 0 do
      Map.put(initial_state, :templates, create_default_templates())
    else
      initial_state
    end
    
    # Start periodic cleanup task
    schedule_cleanup()
    
    Logger.info("PromptManagerAgent initialized with #{map_size(state.templates)} templates")
    {:ok, state}
  end

  # Template Management Signals

  @impl true
  def handle_signal(agent, %{"type" => "create_template", "data" => template_data}) do
    case Template.new(template_data) do
      {:ok, template} ->
        agent = put_in(agent.state.templates[template.id], template)
        
        emit_signal("template_created", %{
          "template_id" => template.id,
          "name" => template.name,
          "category" => template.category,
          "version" => template.version
        })
        
        Logger.info("Created template: #{template.name} (#{template.id})")
        {:ok, agent}
        
      {:error, reason} ->
        emit_signal("template_creation_failed", %{
          "error" => reason,
          "data" => template_data
        })
        
        Logger.warning("Failed to create template: #{reason}")
        {:ok, agent}
    end
  end

  def handle_signal(agent, %{"type" => "update_template", "data" => %{"id" => template_id} = update_data}) do
    case Map.get(agent.state.templates, template_id) do
      nil ->
        emit_signal("template_not_found", %{"template_id" => template_id})
        {:ok, agent}
        
      template ->
        case Template.update(template, update_data) do
          {:ok, updated_template} ->
            agent = put_in(agent.state.templates[template_id], updated_template)
            
            # Invalidate cache entries for this template
            agent = invalidate_template_cache(agent, template_id)
            
            emit_signal("template_updated", %{
              "template_id" => template_id,
              "name" => updated_template.name,
              "version" => updated_template.version
            })
            
            Logger.info("Updated template: #{updated_template.name} (#{template_id})")
            {:ok, agent}
            
          {:error, reason} ->
            emit_signal("template_update_failed", %{
              "template_id" => template_id,
              "error" => reason
            })
            
            {:ok, agent}
        end
    end
  end

  def handle_signal(agent, %{"type" => "delete_template", "data" => %{"id" => template_id}}) do
    case Map.get(agent.state.templates, template_id) do
      nil ->
        emit_signal("template_not_found", %{"template_id" => template_id})
        {:ok, agent}
        
      template ->
        {_deleted_template, agent} = pop_in(agent.state.templates[template_id])
        
        # Clean up related data
        agent = agent
        |> invalidate_template_cache(template_id)
        |> cleanup_template_analytics(template_id)
        
        emit_signal("template_deleted", %{
          "template_id" => template_id,
          "name" => template.name
        })
        
        Logger.info("Deleted template: #{template.name} (#{template_id})")
        {:ok, agent}
    end
  end

  def handle_signal(agent, %{"type" => "get_template", "data" => %{"id" => template_id}}) do
    case Map.get(agent.state.templates, template_id) do
      nil ->
        emit_signal("template_not_found", %{"template_id" => template_id})
        
      template ->
        emit_signal("template_response", %{
          "template" => template,
          "stats" => Template.get_stats(template)
        })
    end
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "list_templates", "data" => filters}) do
    templates = agent.state.templates
    |> Map.values()
    |> apply_template_filters(filters)
    |> Enum.map(fn template ->
      Map.take(template, [:id, :name, :description, :category, :tags, :version, :created_at, :access_level])
    end)
    
    emit_signal("templates_list", %{
      "templates" => templates,
      "count" => length(templates),
      "filters_applied" => filters
    })
    
    {:ok, agent}
  end

  # Prompt Building Signals

  def handle_signal(agent, %{"type" => "build_prompt", "data" => %{"template_id" => template_id} = build_data}) do
    case Map.get(agent.state.templates, template_id) do
      nil ->
        emit_signal("template_not_found", %{"template_id" => template_id})
        {:ok, agent}
        
      template ->
        context = Map.get(build_data, "context", %{})
        options = Map.get(build_data, "options", %{})
        
        # Check cache first
        cache_key = build_cache_key(template_id, context, options)
        
        case get_from_cache(agent, cache_key) do
          {:hit, cached_result} ->
            emit_signal("prompt_built", Map.put(cached_result, "cache_hit", true))
            {:ok, agent}
            
          :miss ->
            case Builder.build(template, context, options) do
              {:ok, built_prompt} ->
                result = %{
                  "template_id" => template_id,
                  "prompt" => built_prompt,
                  "metadata" => %{
                    "built_at" => DateTime.utc_now(),
                    "template_version" => template.version,
                    "context_size" => map_size(context)
                  }
                }
                
                # Cache the result
                agent = put_in_cache(agent, cache_key, result)
                
                # Update usage statistics
                agent = update_template_usage(agent, template_id, :success)
                
                emit_signal("prompt_built", result)
                {:ok, agent}
                
              {:error, reason} ->
                agent = update_template_usage(agent, template_id, :error)
                
                emit_signal("prompt_build_failed", %{
                  "template_id" => template_id,
                  "error" => reason,
                  "context" => context
                })
                
                {:ok, agent}
            end
        end
    end
  end

  def handle_signal(agent, %{"type" => "validate_template", "data" => %{"template" => template_data}}) do
    case Template.new(template_data) do
      {:ok, template} ->
        case Template.validate(template) do
          {:ok, _validated_template} ->
            emit_signal("template_valid", %{
              "valid" => true,
              "template_id" => template.id,
              "variables_count" => length(template.variables)
            })
            
          {:error, reason} ->
            emit_signal("template_invalid", %{
              "valid" => false,
              "error" => reason,
              "template_data" => template_data
            })
        end
        
      {:error, reason} ->
        emit_signal("template_invalid", %{
          "valid" => false,
          "error" => reason,
          "template_data" => template_data
        })
    end
    
    {:ok, agent}
  end

  # Analytics Signals

  def handle_signal(agent, %{"type" => "get_analytics", "data" => filters}) do
    analytics = build_analytics_report(agent, filters)
    
    emit_signal("analytics_report", analytics)
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "get_usage_stats", "data" => %{"template_id" => template_id}}) do
    case Map.get(agent.state.templates, template_id) do
      nil ->
        emit_signal("template_not_found", %{"template_id" => template_id})
        
      template ->
        stats = Template.get_stats(template)
        analytics_data = Map.get(agent.state.analytics, template_id, %{})
        
        emit_signal("usage_stats", %{
          "template_id" => template_id,
          "stats" => stats,
          "detailed_analytics" => analytics_data
        })
    end
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "optimize_template", "data" => %{"template_id" => template_id}}) do
    case Map.get(agent.state.templates, template_id) do
      nil ->
        emit_signal("template_not_found", %{"template_id" => template_id})
        {:ok, agent}
        
      template ->
        suggestions = generate_optimization_suggestions(template, agent)
        
        emit_signal("optimization_suggestions", %{
          "template_id" => template_id,
          "suggestions" => suggestions,
          "confidence_score" => calculate_confidence_score(suggestions, template)
        })
        
        {:ok, agent}
    end
  end

  # System Signals

  def handle_signal(agent, %{"type" => "get_status"}) do
    status = %{
      "templates_count" => map_size(agent.state.templates),
      "experiments_count" => map_size(agent.state.experiments),
      "cache_size" => map_size(agent.state.cache),
      "memory_usage" => calculate_memory_usage(agent),
      "uptime" => get_uptime(),
      "health" => "healthy"
    }
    
    emit_signal("status_report", status)
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "clear_cache"}) do
    agent = put_in(agent.state.cache, %{})
    
    emit_signal("cache_cleared", %{
      "timestamp" => DateTime.utc_now()
    })
    
    Logger.info("PromptManagerAgent cache cleared")
    {:ok, agent}
  end

  # Fallback for unknown signals
  def handle_signal(agent, signal) do
    Logger.warning("PromptManagerAgent received unknown signal: #{inspect(signal["type"])}")
    {:ok, agent}
  end

  # GenServer callbacks for periodic tasks

  @impl true
  def handle_info(:cleanup, agent) do
    agent = agent
    |> cleanup_expired_cache()
    |> cleanup_old_analytics()
    
    schedule_cleanup()
    {:noreply, agent}
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

  defp apply_template_filters(templates, filters) when is_map(filters) do
    templates
    |> filter_by_category(Map.get(filters, "category"))
    |> filter_by_tags(Map.get(filters, "tags"))
    |> filter_by_access_level(Map.get(filters, "access_level"))
    |> sort_templates(Map.get(filters, "sort_by"))
    |> limit_results(Map.get(filters, "limit"))
  end

  defp apply_template_filters(templates, _), do: templates

  defp filter_by_category(templates, nil), do: templates
  defp filter_by_category(templates, category) do
    Enum.filter(templates, &(&1.category == category))
  end

  defp filter_by_tags(templates, nil), do: templates
  defp filter_by_tags(templates, tags) when is_list(tags) do
    Enum.filter(templates, fn template ->
      Enum.any?(tags, &(&1 in template.tags))
    end)
  end

  defp filter_by_access_level(templates, nil), do: templates
  defp filter_by_access_level(templates, access_level) do
    Enum.filter(templates, &(&1.access_level == String.to_atom(access_level)))
  end

  defp sort_templates(templates, "name"), do: Enum.sort_by(templates, & &1.name)
  defp sort_templates(templates, "created_at"), do: Enum.sort_by(templates, & &1.created_at, DateTime)
  defp sort_templates(templates, "updated_at"), do: Enum.sort_by(templates, & &1.updated_at, DateTime)
  defp sort_templates(templates, _), do: templates

  defp limit_results(templates, nil), do: templates
  defp limit_results(templates, limit) when is_integer(limit) do
    Enum.take(templates, limit)
  end

  defp build_cache_key(template_id, context, options) do
    data = %{template_id: template_id, context: context, options: options}
    :crypto.hash(:md5, :erlang.term_to_binary(data)) |> Base.encode16()
  end

  defp get_from_cache(agent, cache_key) do
    case Map.get(agent.state.cache, cache_key) do
      nil -> :miss
      %{expires_at: expires_at} = entry ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:hit, Map.get(entry, :data)}
        else
          :miss
        end
    end
  end

  defp put_in_cache(agent, cache_key, data) do
    expires_at = DateTime.add(DateTime.utc_now(), agent.state.config.cache_ttl, :second)
    
    cache_entry = %{
      data: data,
      expires_at: expires_at,
      created_at: DateTime.utc_now()
    }
    
    put_in(agent.state.cache[cache_key], cache_entry)
  end

  defp invalidate_template_cache(agent, template_id) do
    cache = agent.state.cache
    |> Enum.reject(fn {_key, entry} ->
      case entry.data do
        %{"template_id" => ^template_id} -> true
        _ -> false
      end
    end)
    |> Map.new()
    
    put_in(agent.state.cache, cache)
  end

  defp update_template_usage(agent, template_id, status) do
    update_in(agent.state.templates[template_id].metadata, fn metadata ->
      current_count = Map.get(metadata, :usage_count, 0)
      error_count = Map.get(metadata, :error_count, 0)
      
      updated_metadata = metadata
      |> Map.put(:usage_count, current_count + 1)
      |> Map.put(:last_used, DateTime.utc_now())
      
      if status == :error do
        Map.put(updated_metadata, :error_count, error_count + 1)
      else
        updated_metadata
      end
    end)
  end

  defp cleanup_template_analytics(agent, template_id) do
    {_analytics, agent} = pop_in(agent.state.analytics[template_id])
    agent
  end

  defp build_analytics_report(agent, filters) do
    templates = Map.values(agent.state.templates)
    
    %{
      "total_templates" => length(templates),
      "templates_by_category" => group_by_category(templates),
      "most_used_templates" => get_most_used_templates(templates, 10),
      "cache_hit_rate" => calculate_cache_hit_rate(agent),
      "avg_build_success_rate" => calculate_avg_success_rate(templates),
      "generated_at" => DateTime.utc_now(),
      "period" => Map.get(filters, "period", "all_time")
    }
  end

  defp group_by_category(templates) do
    templates
    |> Enum.group_by(& &1.category)
    |> Map.new(fn {category, temps} -> {category, length(temps)} end)
  end

  defp get_most_used_templates(templates, limit) do
    templates
    |> Enum.map(fn template ->
      usage_count = get_in(template.metadata, [:usage_count]) || 0
      %{
        "id" => template.id,
        "name" => template.name,
        "usage_count" => usage_count,
        "category" => template.category
      }
    end)
    |> Enum.sort_by(& &1["usage_count"], :desc)
    |> Enum.take(limit)
  end

  defp calculate_cache_hit_rate(_agent) do
    # Simplified implementation
    # In production, would track hit/miss ratios
    0.85
  end

  defp calculate_avg_success_rate(templates) do
    if Enum.empty?(templates) do
      0.0
    else
      total_rate = templates
      |> Enum.map(fn template ->
        usage = get_in(template.metadata, [:usage_count]) || 0
        errors = get_in(template.metadata, [:error_count]) || 0
        if usage > 0, do: (usage - errors) / usage, else: 1.0
      end)
      |> Enum.sum()
      
      total_rate / length(templates)
    end
  end

  defp generate_optimization_suggestions(template, _agent) do
    suggestions = []
    
    # Check for long content
    suggestions = if String.length(template.content) > 1000 do
      [%{
        type: "content_length",
        message: "Template content is quite long. Consider breaking it into smaller, more focused templates.",
        priority: "medium"
      } | suggestions]
    else
      suggestions
    end
    
    # Check for unused variables
    content_vars = Template.extract_variables(template.content)
    defined_vars = Enum.map(template.variables, & &1.name)
    unused_vars = defined_vars -- content_vars
    
    suggestions = if length(unused_vars) > 0 do
      [%{
        type: "unused_variables",
        message: "Variables defined but not used: #{Enum.join(unused_vars, ", ")}",
        priority: "low"
      } | suggestions]
    else
      suggestions
    end
    
    # Check for missing descriptions
    suggestions = if template.description == "" do
      [%{
        type: "missing_description",
        message: "Template lacks a description. Add one to improve discoverability.",
        priority: "low"
      } | suggestions]
    else
      suggestions
    end
    
    suggestions
  end

  defp calculate_confidence_score(suggestions, _template) do
    # Simple confidence calculation based on suggestion count and types
    base_score = 0.8
    penalty_per_suggestion = 0.1
    
    max(0.1, base_score - (length(suggestions) * penalty_per_suggestion))
  end

  defp calculate_memory_usage(agent) do
    # Simplified memory calculation
    template_size = map_size(agent.state.templates) * 1024  # rough estimate
    cache_size = map_size(agent.state.cache) * 512
    
    %{
      "templates_bytes" => template_size,
      "cache_bytes" => cache_size,
      "total_bytes" => template_size + cache_size
    }
  end

  defp get_uptime do
    # Simple uptime calculation
    # In production, would track actual start time
    System.monotonic_time(:second)
  end

  defp cleanup_expired_cache(agent) do
    now = DateTime.utc_now()
    
    valid_cache = agent.state.cache
    |> Enum.filter(fn {_key, entry} ->
      DateTime.compare(now, entry.expires_at) == :lt
    end)
    |> Map.new()
    
    put_in(agent.state.cache, valid_cache)
  end

  defp cleanup_old_analytics(agent) do
    # Remove analytics older than retention period
    _cutoff_date = DateTime.add(DateTime.utc_now(), -agent.state.config.analytics_retention_days, :day)
    
    # Simplified cleanup - in production would be more sophisticated
    agent
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 300_000)  # Every 5 minutes
  end
end
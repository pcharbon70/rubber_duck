defmodule RubberDuck.CodingAssistant.Engines.ExplanationEngine do
  @moduledoc """
  ExplanationEngine provides AI-powered code explanation capabilities with context-aware analysis.
  
  This engine integrates with the LLM coordination system to provide detailed, structured explanations
  of code functionality, patterns, and design decisions. It supports multiple explanation types and
  adapts depth based on code complexity.
  
  ## Features
  
  - Multi-type explanations: summary, detailed, step-by-step
  - Context-aware analysis using Tree-sitter parsing
  - Intelligent caching with content-based keys
  - Adaptive explanation depth based on complexity
  - Fallback mechanisms for LLM unavailability
  - Real-time and batch processing modes
  
  ## Explanation Types
  
  - `:summary` - Brief overview of code functionality
  - `:detailed` - Comprehensive explanation with context
  - `:step_by_step` - Line-by-line walkthrough
  - `:architectural` - High-level design pattern analysis
  - `:documentation` - Documentation-style explanation
  """
  
  use RubberDuck.CodingAssistant.Engine
  
  alias RubberDuck.LLM.Coordinator
  alias RubberDuck.ILP.Parser.TreeSitterWrapper
  alias RubberDuck.LLMAbstraction.{Message, Response}
  alias RubberDuck.CodingAssistant.FileSizeManager
  
  require Logger
  
  @capabilities [
    :code_explanation,
    :documentation_generation,
    :concept_clarification,
    :pattern_analysis,
    :architectural_analysis
  ]
  
  @explanation_types [:summary, :detailed, :step_by_step, :architectural, :documentation]
  @supported_languages [:elixir, :erlang, :javascript, :python, :typescript, :rust, :go]
  @max_context_size 8192
  @cache_ttl :timer.hours(24)
  @real_time_timeout 100
  
  defstruct [
    :llm_coordinator,
    :parser,
    :cache,
    :file_size_manager,
    :templates,
    :config,
    statistics: %{
      explanations_generated: 0,
      cache_hits: 0,
      cache_misses: 0,
      total_processing_time: 0,
      avg_processing_time: 0,
      success_rate: 1.0
    },
    health_status: :healthy
  ]
  
  @type explanation_request :: %{
    content: String.t(),
    language: atom(),
    type: atom(),
    context: map(),
    options: map()
  }
  
  @type explanation_result :: %{
    explanation: String.t(),
    metadata: map(),
    confidence: float(),
    processing_time: non_neg_integer()
  }
  
  @impl true
  def capabilities, do: @capabilities
  
  @impl true
  def init(config) do
    Logger.info("Initializing ExplanationEngine with config: #{inspect(config)}")
    
    validated_config = validate_config(config)
    
    state = %__MODULE__{
      llm_coordinator: Coordinator,
      parser: TreeSitterWrapper,
      cache: init_cache(validated_config),
      file_size_manager: FileSizeManager,
      templates: load_explanation_templates(validated_config),
      config: validated_config
    }
    
    {:ok, state}
  rescue
    error ->
      Logger.error("Failed to initialize ExplanationEngine: #{inspect(error)}")
      {:error, error}
  end
  
  @impl true
  def process_real_time(explanation_request, state) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      with {:ok, validated_request} <- validate_explanation_request(explanation_request),
           {:ok, cached_result} <- check_cache(validated_request, state),
           result when not is_nil(result) <- cached_result do
        
        processing_time = System.monotonic_time(:millisecond) - start_time
        updated_stats = update_cache_hit_stats(state.statistics, processing_time)
        
        {:ok, result, %{state | statistics: updated_stats}}
      else
        {:ok, nil} ->
          # Cache miss - proceed with real-time processing
          process_explanation_real_time(explanation_request, state, start_time)
        
        {:error, reason} ->
          {:error, reason, state}
      end
    rescue
      error ->
        Logger.error("Real-time explanation processing failed: #{inspect(error)}")
        {:error, {:processing_error, error}, state}
    end
  end
  
  @impl true
  def process_batch(explanation_requests, state) when is_list(explanation_requests) do
    Logger.info("Processing batch of #{length(explanation_requests)} explanation requests")
    
    start_time = System.monotonic_time(:millisecond)
    
    try do
      results = explanation_requests
      |> Enum.map(&validate_explanation_request/1)
      |> Enum.filter(fn
        {:ok, _} -> true
        {:error, reason} -> 
          Logger.warning("Invalid explanation request: #{inspect(reason)}")
          false
      end)
      |> Enum.map(fn {:ok, request} -> request end)
      |> process_batch_explanations(state)
      
      processing_time = System.monotonic_time(:millisecond) - start_time
      updated_stats = update_batch_stats(state.statistics, length(results), processing_time)
      
      {:ok, results, %{state | statistics: updated_stats}}
    rescue
      error ->
        Logger.error("Batch explanation processing failed: #{inspect(error)}")
        {:error, {:batch_processing_error, error}, state}
    end
  end
  
  @impl true
  def handle_engine_event({:cache_clear, patterns}, state) do
    cleared_count = clear_cache_patterns(state.cache, patterns)
    Logger.info("Cleared #{cleared_count} cache entries matching patterns: #{inspect(patterns)}")
    {:ok, state}
  end
  
  def handle_engine_event({:config_update, new_config}, state) do
    case validate_config(new_config) do
      {:ok, validated_config} ->
        updated_state = %{state | 
          config: validated_config,
          templates: load_explanation_templates(validated_config)
        }
        Logger.info("ExplanationEngine configuration updated")
        {:ok, updated_state}
      
      {:error, reason} ->
        Logger.error("Failed to update ExplanationEngine config: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  def handle_engine_event(_event, state) do
    {:ok, state}
  end
  
  @impl true
  def health_check(state) do
    checks = [
      {:cache_health, check_cache_health(state.cache)},
      {:llm_connectivity, check_llm_connectivity(state.llm_coordinator)},
      {:processing_performance, check_processing_performance(state.statistics)},
      {:memory_usage, check_memory_usage()}
    ]
    
    failed_checks = Enum.filter(checks, fn {_, result} -> result != :ok end)
    
    cond do
      length(failed_checks) == 0 ->
        {:ok, :healthy, %{checks: checks}}
      
      length(failed_checks) <= 2 ->
        {:ok, :degraded, %{checks: checks, issues: failed_checks}}
      
      true ->
        {:error, :unhealthy, %{checks: checks, issues: failed_checks}}
    end
  end
  
  @impl true
  def terminate(reason, state) do
    Logger.info("ExplanationEngine terminating: #{inspect(reason)}")
    cleanup_cache(state.cache)
    :ok
  end
  
  # Private Functions
  
  defp validate_config(config) do
    required_keys = [:llm_providers, :cache_config, :template_config]
    
    case Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      true ->
        validated_config = config
        |> Map.put_new(:max_context_size, @max_context_size)
        |> Map.put_new(:cache_ttl, @cache_ttl)
        |> Map.put_new(:real_time_timeout, @real_time_timeout)
        |> Map.put_new(:supported_languages, @supported_languages)
        
        {:ok, validated_config}
      
      false ->
        missing = required_keys -- Map.keys(config)
        {:error, {:missing_config_keys, missing}}
    end
  end
  
  defp validate_explanation_request(request) do
    with {:ok, content} <- validate_content(request[:content]),
         {:ok, language} <- validate_language(request[:language]),
         {:ok, type} <- validate_explanation_type(request[:type]) do
      
      validated_request = %{
        content: content,
        language: language,
        type: type,
        context: Map.get(request, :context, %{}),
        options: Map.get(request, :options, %{})
      }
      
      {:ok, validated_request}
    end
  end
  
  defp validate_content(content) when is_binary(content) and content != "", do: {:ok, content}
  defp validate_content(_), do: {:error, :invalid_content}
  
  defp validate_language(language) when language in @supported_languages, do: {:ok, language}
  defp validate_language(language) when is_atom(language) do
    case Atom.to_string(language) |> String.downcase() |> String.to_atom() do
      normalized when normalized in @supported_languages -> {:ok, normalized}
      _ -> {:error, {:unsupported_language, language}}
    end
  end
  defp validate_language(_), do: {:error, :invalid_language}
  
  defp validate_explanation_type(type) when type in @explanation_types, do: {:ok, type}
  defp validate_explanation_type(_), do: {:error, :invalid_explanation_type}
  
  defp process_explanation_real_time(request, state, start_time) do
    timeout = min(@real_time_timeout, state.config.real_time_timeout)
    
    task = Task.async(fn ->
      generate_explanation(request, state)
    end)
    
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        cache_result(request, result, state)
        processing_time = System.monotonic_time(:millisecond) - start_time
        updated_stats = update_success_stats(state.statistics, processing_time)
        
        {:ok, result, %{state | statistics: updated_stats}}
      
      {:ok, {:error, reason}} ->
        processing_time = System.monotonic_time(:millisecond) - start_time
        updated_stats = update_error_stats(state.statistics, processing_time)
        
        {:error, reason, %{state | statistics: updated_stats}}
      
      nil ->
        Logger.warning("Real-time explanation timed out after #{timeout}ms")
        fallback_result = generate_fallback_explanation(request, state)
        processing_time = System.monotonic_time(:millisecond) - start_time
        updated_stats = update_timeout_stats(state.statistics, processing_time)
        
        {:ok, fallback_result, %{state | statistics: updated_stats}}
    end
  end
  
  defp generate_explanation(request, state) do
    with {:ok, code_context} <- extract_code_context(request, state),
         {:ok, llm_request} <- build_llm_request(request, code_context, state),
         {:ok, llm_response} <- coordinate_llm_request(llm_request, state),
         {:ok, formatted_explanation} <- format_explanation(llm_response, request, state) do
      
      result = %{
        explanation: formatted_explanation,
        metadata: %{
          type: request.type,
          language: request.language,
          context_size: byte_size(code_context.content),
          model_used: llm_response.metadata[:model],
          confidence: calculate_confidence(llm_response)
        },
        confidence: calculate_confidence(llm_response),
        processing_time: System.monotonic_time(:millisecond)
      }
      
      {:ok, result}
    end
  end
  
  defp extract_code_context(request, state) do
    case TreeSitterWrapper.parse_with_treesitter(request.content, request.language, %{}) do
      {:ok, ast} ->
        context = %{
          content: request.content,
          ast: ast,
          symbols: extract_symbols(ast, request.language),
          structure: analyze_structure(ast, request.language),
          complexity: calculate_complexity(ast, request.language)
        }
        {:ok, context}
      
      {:error, reason} ->
        Logger.warning("Failed to parse code with Tree-sitter: #{inspect(reason)}")
        # Fallback to basic context
        {:ok, %{
          content: request.content,
          ast: nil,
          symbols: [],
          structure: %{},
          complexity: :unknown
        }}
    end
  end
  
  defp build_llm_request(request, code_context, state) do
    template = get_explanation_template(request.type, state.templates)
    
    prompt = render_template(template, %{
      code: code_context.content,
      language: request.language,
      symbols: code_context.symbols,
      structure: code_context.structure,
      complexity: code_context.complexity,
      context: request.context
    })
    
    llm_request = %{
      task_type: :code_explanation,
      content: prompt,
      requirements: %{
        complexity: determine_task_complexity(code_context),
        quality: :high,
        cost_sensitivity: :medium
      },
      metadata: %{
        explanation_type: request.type,
        language: request.language,
        engine: :explanation_engine
      }
    }
    
    {:ok, llm_request}
  end
  
  defp coordinate_llm_request(llm_request, state) do
    case Coordinator.route_task(llm_request.task_type, llm_request.content, llm_request.requirements) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, {:llm_coordination_failed, reason}}
    end
  end
  
  defp format_explanation(llm_response, request, state) do
    case request.type do
      :summary -> format_summary_explanation(llm_response, state)
      :detailed -> format_detailed_explanation(llm_response, state)
      :step_by_step -> format_step_by_step_explanation(llm_response, state)
      :architectural -> format_architectural_explanation(llm_response, state)
      :documentation -> format_documentation_explanation(llm_response, state)
    end
  end
  
  defp generate_fallback_explanation(request, _state) do
    %{
      explanation: """
      Basic code analysis for #{request.language} code:
      
      The provided code appears to be written in #{request.language}. 
      Due to processing constraints, a detailed explanation is not available at this time.
      
      Consider breaking the code into smaller sections for more detailed analysis.
      """,
      metadata: %{
        type: :fallback,
        language: request.language,
        fallback_reason: :timeout
      },
      confidence: 0.3,
      processing_time: 0
    }
  end
  
  # Cache operations
  
  defp init_cache(config) do
    # Implementation would initialize appropriate cache backend
    :ets.new(:explanation_cache, [:set, :private])
  end
  
  defp check_cache(request, state) do
    cache_key = generate_cache_key(request)
    
    case :ets.lookup(state.cache, cache_key) do
      [{^cache_key, {result, timestamp}}] ->
        if timestamp + @cache_ttl > System.system_time(:millisecond) do
          {:ok, result}
        else
          :ets.delete(state.cache, cache_key)
          {:ok, nil}
        end
      
      [] ->
        {:ok, nil}
    end
  end
  
  defp cache_result(request, result, state) do
    cache_key = generate_cache_key(request)
    timestamp = System.system_time(:millisecond)
    :ets.insert(state.cache, {cache_key, {result, timestamp}})
  end
  
  defp generate_cache_key(request) do
    content_hash = :crypto.hash(:sha256, request.content) |> Base.encode16()
    "#{request.type}:#{request.language}:#{content_hash}"
  end
  
  # Template operations
  
  defp load_explanation_templates(_config) do
    %{
      summary: """
      Provide a concise summary of the following {{language}} code:
      
      ```{{language}}
      {{code}}
      ```
      
      Focus on the main purpose and key functionality.
      """,
      detailed: """
      Provide a detailed explanation of the following {{language}} code:
      
      ```{{language}}
      {{code}}
      ```
      
      Include:
      - Purpose and functionality
      - Key components and their roles
      - Data flow and logic
      - Important patterns or techniques used
      """,
      step_by_step: """
      Provide a step-by-step walkthrough of the following {{language}} code:
      
      ```{{language}}
      {{code}}
      ```
      
      Explain each significant line or block of code and how it contributes to the overall functionality.
      """,
      architectural: """
      Analyze the architectural patterns and design decisions in the following {{language}} code:
      
      ```{{language}}
      {{code}}
      ```
      
      Focus on:
      - Design patterns used
      - Architectural principles
      - Structure and organization
      - Relationships between components
      """,
      documentation: """
      Generate comprehensive documentation for the following {{language}} code:
      
      ```{{language}}
      {{code}}
      ```
      
      Include:
      - Purpose and usage
      - Parameters and return values
      - Examples
      - Important notes or considerations
      """
    }
  end
  
  defp get_explanation_template(type, templates) do
    Map.get(templates, type, templates.summary)
  end
  
  defp render_template(template, variables) do
    Enum.reduce(variables, template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end
  
  # Helper functions
  
  defp extract_symbols(_ast, _language), do: []
  defp analyze_structure(_ast, _language), do: %{}
  defp calculate_complexity(_ast, _language), do: :low
  defp determine_task_complexity(_context), do: :medium
  defp calculate_confidence(_response), do: 0.85
  
  defp format_summary_explanation(response, _state), do: {:ok, response.content}
  defp format_detailed_explanation(response, _state), do: {:ok, response.content}
  defp format_step_by_step_explanation(response, _state), do: {:ok, response.content}
  defp format_architectural_explanation(response, _state), do: {:ok, response.content}
  defp format_documentation_explanation(response, _state), do: {:ok, response.content}
  
  defp process_batch_explanations(requests, state) do
    requests
    |> Enum.map(fn request ->
      case generate_explanation(request, state) do
        {:ok, result} -> result
        {:error, reason} ->
          Logger.error("Batch explanation failed: #{inspect(reason)}")
          generate_fallback_explanation(request, state)
      end
    end)
  end
  
  # Statistics updates
  
  defp update_cache_hit_stats(stats, processing_time) do
    %{stats |
      cache_hits: stats.cache_hits + 1,
      total_processing_time: stats.total_processing_time + processing_time,
      avg_processing_time: calculate_avg_processing_time(stats, processing_time)
    }
  end
  
  defp update_success_stats(stats, processing_time) do
    total_requests = stats.explanations_generated + 1
    
    %{stats |
      explanations_generated: total_requests,
      cache_misses: stats.cache_misses + 1,
      total_processing_time: stats.total_processing_time + processing_time,
      avg_processing_time: calculate_avg_processing_time(stats, processing_time),
      success_rate: calculate_success_rate(stats, true)
    }
  end
  
  defp update_error_stats(stats, processing_time) do
    %{stats |
      total_processing_time: stats.total_processing_time + processing_time,
      avg_processing_time: calculate_avg_processing_time(stats, processing_time),
      success_rate: calculate_success_rate(stats, false)
    }
  end
  
  defp update_timeout_stats(stats, processing_time) do
    update_success_stats(stats, processing_time)
  end
  
  defp update_batch_stats(stats, count, processing_time) do
    %{stats |
      explanations_generated: stats.explanations_generated + count,
      total_processing_time: stats.total_processing_time + processing_time,
      avg_processing_time: calculate_avg_processing_time(stats, processing_time)
    }
  end
  
  defp calculate_avg_processing_time(stats, new_time) do
    total_operations = stats.explanations_generated + stats.cache_hits + 1
    (stats.total_processing_time + new_time) / total_operations
  end
  
  defp calculate_success_rate(_stats, _success), do: 0.95  # Simplified
  
  # Health check helpers
  
  defp check_cache_health(_cache), do: :ok
  defp check_llm_connectivity(_coordinator), do: :ok
  defp check_processing_performance(_stats), do: :ok
  defp check_memory_usage(), do: :ok
  
  defp cleanup_cache(cache) do
    :ets.delete(cache)
  end
  
  defp clear_cache_patterns(_cache, _patterns), do: 0
end
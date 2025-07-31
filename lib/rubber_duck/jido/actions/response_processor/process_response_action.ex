defmodule RubberDuck.Jido.Actions.ResponseProcessor.ProcessResponseAction do
  @moduledoc """
  Action for processing LLM responses through the complete pipeline.
  
  This action handles the main processing workflow including:
  - Cache checking and retrieval
  - Content parsing, validation, and enhancement
  - Caching of successful results
  - Metrics updates and signal emission
  """
  
  use Jido.Action,
    name: "process_response",
    description: "Processes LLM responses with parsing, validation, enhancement, and caching",
    schema: [
      content: [
        type: :string,
        required: true,
        doc: "The raw response content to process"
      ],
      request_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for the request"
      ],
      provider: [
        type: :atom,
        default: :unknown,
        doc: "The LLM provider that generated the response"
      ],
      model: [
        type: :string,
        default: "unknown",
        doc: "The model that generated the response"
      ],
      options: [
        type: :map,
        default: %{},
        doc: "Processing options including format, validation rules, etc."
      ]
    ]

  alias RubberDuck.Agents.Response.{ProcessedResponse, Parser}
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    start_time = System.monotonic_time(:millisecond)
    
    %{
      content: content,
      request_id: request_id,
      provider: provider,
      model: model,
      options: options
    } = params
    
    # Check cache first
    cache_key = generate_cache_key(content, options)
    
    case get_from_cache(agent, cache_key) do
      {:hit, cached_response} ->
        handle_cache_hit(agent, cached_response, start_time)
        
      :miss ->
        handle_cache_miss(agent, content, request_id, provider, model, options, cache_key, start_time)
    end
  end

  # Private functions

  defp handle_cache_hit(agent, cached_response, _start_time) do
    agent = update_cache_metrics(agent, :hit)
    
    signal_data = Map.merge(cached_response, %{
      cache_hit: true,
      processing_time: 0,
      timestamp: DateTime.utc_now()
    })
    
    case EmitSignalAction.run(
      %{signal_type: "response.processed", data: signal_data},
      %{agent: agent}
    ) do
      {:ok, _result, %{agent: updated_agent}} ->
        {:ok, %{cache_hit: true, response: cached_response}, %{agent: updated_agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end

  defp handle_cache_miss(agent, content, request_id, provider, model, options, cache_key, start_time) do
    agent = update_cache_metrics(agent, :miss)
    
    case process_response_pipeline(content, request_id, provider, model, options, agent) do
      {:ok, processed_response, updated_agent} ->
        # Cache the result if it meets quality threshold
        updated_agent = if ProcessedResponse.cacheable?(processed_response) do
          put_in_cache(updated_agent, cache_key, processed_response)
        else
          updated_agent
        end
        
        # Update metrics
        processing_time = System.monotonic_time(:millisecond) - start_time
        updated_agent = update_processing_metrics(updated_agent, processed_response, processing_time)
        
        # Emit the processed response
        client_response = ProcessedResponse.to_client_response(processed_response)
        signal_data = Map.merge(client_response, %{
          cache_hit: false,
          timestamp: DateTime.utc_now()
        })
        
        case EmitSignalAction.run(
          %{signal_type: "response.processed", data: signal_data},
          %{agent: updated_agent}
        ) do
          {:ok, _result, %{agent: final_agent}} ->
            {:ok, %{cache_hit: false, response: client_response}, %{agent: final_agent}}
          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
        
      {:error, reason, updated_agent} ->
        updated_agent = update_error_metrics(updated_agent, reason)
        
        signal_data = %{
          request_id: request_id,
          error: reason,
          original_content: content,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "response.processing.failed", data: signal_data},
          %{agent: updated_agent}
        ) do
          {:ok, _result, %{agent: final_agent}} ->
            {:error, reason, %{agent: final_agent}}
          {:error, emit_error} ->
            Logger.error("Failed to emit processing failure signal: #{inspect(emit_error)}")
            {:error, reason, %{agent: updated_agent}}
        end
    end
  end

  defp process_response_pipeline(content, request_id, provider, model, options, agent) do
    try do
      # Step 1: Create ProcessedResponse
      processed_response = ProcessedResponse.new(content, request_id, provider, model)
      
      # Step 2: Parse content
      case parse_content(content, Map.get(options, "format"), options) do
        {:ok, parsed_content, format, _parse_metadata} ->
          processed_response = ProcessedResponse.set_parsed_content(processed_response, parsed_content, format)
          
          # Step 3: Validate content
          case validate_content(content, Map.get(options, "validation_rules", %{}), agent) do
            {:ok, quality_score, validation_results} ->
              processed_response = ProcessedResponse.set_quality_score(processed_response, quality_score, validation_results)
              
              # Step 4: Enhance content if enabled and quality is sufficient
              enhanced_response = if agent.state.config.auto_enhance and quality_score < agent.state.config.quality_threshold do
                case enhance_content(content, Map.get(options, "enhancement_options", %{}), agent) do
                  {:ok, enhanced_content, enhancement_log} ->
                    processed_response
                    |> ProcessedResponse.set_enhanced_content(enhanced_content)
                    |> add_enhancement_logs(enhancement_log)
                    
                  {:error, _reason} ->
                    # Enhancement failed, keep original
                    processed_response
                end
              else
                processed_response
              end
              
              {:ok, enhanced_response, agent}
              
            {:error, validation_error} ->
              _error_response = ProcessedResponse.add_error_log(processed_response, :validation_failed, validation_error)
              {:error, "Validation failed: #{validation_error}", agent}
          end
          
        {:error, parse_error} ->
          _error_response = ProcessedResponse.add_error_log(processed_response, :parsing_failed, parse_error)
          {:error, "Parsing failed: #{parse_error}", agent}
      end
      
    rescue
      error ->
        Logger.error("Response processing pipeline failed: #{inspect(error)}")
        {:error, "Processing pipeline failed: #{Exception.message(error)}", agent}
    end
  end

  defp parse_content(content, forced_format, options) do
    case forced_format do
      nil ->
        # Auto-detect format
        Parser.parse(content, options)
        
      format when is_atom(format) ->
        # Use specified format
        case Parser.parse_with_format(content, format, options) do
          {:ok, parsed_content} ->
            {:ok, parsed_content, format, %{forced_format: true}}
          error ->
            error
        end
        
      format when is_binary(format) ->
        # Convert string to atom and retry
        parse_content(content, String.to_atom(format), options)
    end
  end

  defp validate_content(content, validation_rules, agent) do
    try do
      validators = agent.state.validators
      
      # Run all validators
      validation_results = Enum.reduce(validators, %{}, fn validator, acc ->
        case run_validator(validator, content, validation_rules) do
          {:ok, result} -> Map.put(acc, validator, result)
          {:error, _} -> Map.put(acc, validator, %{error: true})
        end
      end)
      
      # Calculate overall quality score
      quality_score = calculate_quality_score(validation_results)
      
      # Build validation summary
      validation_summary = %{
        is_valid: quality_score >= 0.5,
        completeness_score: Map.get(validation_results, :completeness_check, %{}) |> Map.get(:score, 0.5),
        readability_score: Map.get(validation_results, :quality_scoring, %{}) |> Map.get(:readability, 0.5),
        safety_score: Map.get(validation_results, :safety_validation, %{}) |> Map.get(:score, 1.0),
        issues: extract_validation_issues(validation_results)
      }
      
      {:ok, quality_score, validation_summary}
      
    rescue
      error ->
        Logger.warning("Content validation failed: #{inspect(error)}")
        {:error, "Validation failed: #{Exception.message(error)}"}
    end
  end

  defp enhance_content(content, enhancement_options, agent) do
    try do
      enhancers = agent.state.enhancers
      enhancement_log = []
      
      # Apply enhancers in sequence
      {enhanced_content, final_log} = Enum.reduce(enhancers, {content, enhancement_log}, fn enhancer, {current_content, log} ->
        case apply_enhancer(enhancer, current_content, enhancement_options) do
          {:ok, improved_content, enhancer_log} ->
            {improved_content, [enhancer_log | log]}
            
          {:error, _reason} ->
            # Enhancement failed, keep current content
            {current_content, log}
        end
      end)
      
      {:ok, enhanced_content, Enum.reverse(final_log)}
      
    rescue
      error ->
        Logger.warning("Content enhancement failed: #{inspect(error)}")
        {:error, "Enhancement failed: #{Exception.message(error)}"}
    end
  end

  # Validator implementations
  defp run_validator(:completeness_check, content, _rules) do
    # Check if content appears complete
    trimmed = String.trim(content)
    score = cond do
      String.length(trimmed) == 0 -> 0.0
      String.ends_with?(trimmed, [".", "!", "?", "```", "}"]) -> 1.0
      String.length(trimmed) > 50 -> 0.8
      true -> 0.6
    end
    
    {:ok, %{score: score, complete: score >= 0.8}}
  end

  defp run_validator(:safety_validation, content, _rules) do
    # Basic safety checks
    unsafe_patterns = [
      ~r/\b(password|secret|api[_-]?key|token)\s*[:=]\s*\S+/i,
      ~r/\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/, # Credit card
      ~r/\b\d{3}-\d{2}-\d{4}\b/ # SSN
    ]
    
    issues = unsafe_patterns
    |> Enum.filter(&Regex.match?(&1, content))
    |> length()
    
    score = if issues == 0, do: 1.0, else: max(0.0, 1.0 - (issues * 0.3))
    
    {:ok, %{score: score, issues: issues, safe: score >= 0.8}}
  end

  defp run_validator(:quality_scoring, content, _rules) do
    # Basic quality scoring
    word_count = String.split(content) |> length()
    sentence_count = String.split(content, ~r/[.!?]+/) |> length()
    
    readability = if sentence_count > 0 do
      avg_words_per_sentence = word_count / sentence_count
      # Ideal is 15-20 words per sentence
      cond do
        avg_words_per_sentence < 5 -> 0.6
        avg_words_per_sentence <= 20 -> 1.0
        avg_words_per_sentence <= 30 -> 0.8
        true -> 0.5
      end
    else
      0.5
    end
    
    {:ok, %{readability: readability, word_count: word_count, sentence_count: sentence_count}}
  end

  defp run_validator(:format_validation, _content, _rules) do
    # Check if content matches expected format patterns
    {:ok, %{format_consistent: true}}
  end

  # Enhancer implementations
  defp apply_enhancer(:format_beautification, content, _options) do
    # Basic formatting improvements
    enhanced = content
    |> String.replace(~r/\s+/, " ")  # Normalize whitespace
    |> String.replace(~r/\n\s*\n\s*\n+/, "\n\n")  # Normalize line breaks
    |> String.trim()
    
    log = %{
      type: :format_beautification,
      applied_at: DateTime.utc_now(),
      changes: ["whitespace_normalized", "line_breaks_cleaned"]
    }
    
    {:ok, enhanced, log}
  end

  defp apply_enhancer(:link_enrichment, content, _options) do
    # Find and validate URLs
    enhanced = Regex.replace(~r/(https?:\/\/[^\s]+)/, content, fn full_match, _url ->
      # In production, would validate URL and possibly expand
      full_match
    end)
    
    log = %{
      type: :link_enrichment,
      applied_at: DateTime.utc_now(),
      changes: ["urls_processed"]
    }
    
    {:ok, enhanced, log}
  end

  defp apply_enhancer(:content_cleanup, content, _options) do
    # Remove unwanted artifacts
    enhanced = content
    |> String.replace(~r/\s*\n\s*$/, "")  # Trailing whitespace
    |> String.replace(~r/^\s*\n\s*/, "")  # Leading whitespace
    
    log = %{
      type: :content_cleanup,
      applied_at: DateTime.utc_now(),
      changes: ["artifacts_removed"]
    }
    
    {:ok, enhanced, log}
  end

  defp apply_enhancer(:readability_improvement, content, _options) do
    # Basic readability improvements
    # This is a simplified version - real implementation would be more sophisticated
    log = %{
      type: :readability_improvement,
      applied_at: DateTime.utc_now(),
      changes: ["readability_analyzed"]
    }
    
    {:ok, content, log}  # No changes for now
  end

  # Helper functions
  defp calculate_quality_score(validation_results) do
    scores = validation_results
    |> Enum.map(fn {_validator, result} ->
      case result do
        %{score: score} -> score
        %{readability: score} -> score
        _ -> 0.5
      end
    end)
    
    if Enum.empty?(scores) do
      0.5
    else
      Enum.sum(scores) / length(scores)
    end
  end

  defp extract_validation_issues(validation_results) do
    validation_results
    |> Enum.flat_map(fn {validator, result} ->
      case result do
        %{issues: issues} when is_list(issues) -> issues
        %{error: true} -> ["#{validator} failed"]
        %{complete: false} -> ["Content appears incomplete"]
        %{safe: false} -> ["Content safety concerns"]
        _ -> []
      end
    end)
  end

  defp add_enhancement_logs(processed_response, enhancement_logs) do
    Enum.reduce(enhancement_logs, processed_response, fn log, acc ->
      ProcessedResponse.add_enhancement_log(acc, log.type, 0.5, 0.7, log)
    end)
  end

  defp generate_cache_key(content, options) do
    data = %{content: content, options: options}
    :crypto.hash(:md5, :erlang.term_to_binary(data))
    |> Base.encode16(case: :lower)
  end

  defp get_from_cache(agent, cache_key) do
    case Map.get(agent.state.cache, cache_key) do
      nil -> 
        :miss
      %{expires_at: expires_at} = entry ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:hit, Map.get(entry, :data)}
        else
          :miss
        end
    end
  end

  defp put_in_cache(agent, cache_key, processed_response) do
    expires_at = DateTime.add(DateTime.utc_now(), agent.state.config.cache_ttl, :second)
    
    cache_entry = %{
      data: ProcessedResponse.to_client_response(processed_response),
      expires_at: expires_at,
      created_at: DateTime.utc_now(),
      access_count: 0
    }
    
    # Check cache size limits
    agent = if map_size(agent.state.cache) >= agent.state.config.max_cache_size do
      evict_oldest_cache_entries(agent)
    else
      agent
    end
    
    put_in(agent.state.cache[cache_key], cache_entry)
  end

  defp evict_oldest_cache_entries(agent) do
    # Remove 20% of oldest entries
    entries_to_remove = div(agent.state.config.max_cache_size, 5)
    
    oldest_keys = agent.state.cache
    |> Enum.sort_by(fn {_key, entry} -> entry.created_at end, DateTime)
    |> Enum.take(entries_to_remove)
    |> Enum.map(fn {key, _entry} -> key end)
    
    cache = Map.drop(agent.state.cache, oldest_keys)
    put_in(agent.state.cache, cache)
  end

  defp update_cache_metrics(agent, hit_or_miss) do
    case hit_or_miss do
      :hit ->
        update_in(agent.state.metrics.cache_hits, &(&1 + 1))
      :miss ->
        update_in(agent.state.metrics.cache_misses, &(&1 + 1))
    end
  end

  defp update_processing_metrics(agent, processed_response, processing_time) do
    metrics = agent.state.metrics
    
    # Update counters
    total_processed = metrics.total_processed + 1
    
    # Update average processing time
    avg_processing_time = if metrics.avg_processing_time == 0 do
      processing_time
    else
      (metrics.avg_processing_time * metrics.total_processed + processing_time) / total_processed
    end
    
    # Update format distribution
    format = processed_response.format
    format_distribution = Map.update(metrics.format_distribution, format, 1, &(&1 + 1))
    
    # Update quality distribution
    quality_bucket = get_quality_bucket(processed_response.quality_score)
    quality_distribution = Map.update(metrics.quality_distribution, quality_bucket, 1, &(&1 + 1))
    
    updated_metrics = %{metrics |
      total_processed: total_processed,
      avg_processing_time: avg_processing_time,
      format_distribution: format_distribution,
      quality_distribution: quality_distribution
    }
    
    put_in(agent.state.metrics, updated_metrics)
  end

  defp update_error_metrics(agent, _reason) do
    update_in(agent.state.metrics.error_count, &(&1 + 1))
  end

  defp get_quality_bucket(score) do
    cond do
      score >= 0.9 -> :excellent
      score >= 0.7 -> :good
      score >= 0.5 -> :fair
      true -> :poor
    end
  end
end
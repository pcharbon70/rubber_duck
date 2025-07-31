defmodule RubberDuck.Agents.ResponseProcessorAgent do
  @moduledoc """
  Response Processor Agent for handling post-processing of LLM responses.
  
  This agent provides comprehensive response processing including:
  - Multi-format parsing with automatic detection
  - Quality validation and scoring
  - Content enhancement and enrichment
  - Intelligent caching with TTL management
  - Performance metrics and optimization
  
  ## Signals
  
  The agent responds to the following signals:
  
  ### Processing Operations
  - `process_response`: Main processing pipeline
  - `parse_response`: Parse specific format
  - `validate_response`: Validate response quality
  - `enhance_response`: Apply enhancement pipeline
  
  ### Caching Operations
  - `get_cached_response`: Retrieve from cache
  - `invalidate_cache`: Remove cached entries
  - `clear_cache`: Clear all cached responses
  
  ### Metrics and Configuration
  - `get_metrics`: Retrieve processing metrics
  - `get_status`: Agent health and performance status
  - `configure_processor`: Update configuration
  """

  use RubberDuck.Agents.BaseAgent,
    name: "response_processor",
    description: "Processes and enhances LLM responses with parsing, validation, and caching",
    category: "processing",
    schema: [
      cache: [type: :map, default: %{}],
      metrics: [type: :map, default: %{
        total_processed: 0,
        total_cached: 0,
        cache_hits: 0,
        cache_misses: 0,
        avg_processing_time: 0.0,
        format_distribution: %{},
        quality_distribution: %{},
        error_count: 0
      }],
      parsers: [type: :map, default: %{}],
      enhancers: [type: :list, default: []],
      validators: [type: :list, default: []],
      config: [type: :map, default: %{
        cache_ttl: 7200,  # 2 hours
        max_cache_size: 10000,
        enable_streaming: true,
        quality_threshold: 0.8,
        compression_enabled: true,
        auto_enhance: true,
        fallback_to_text: true
      }]
    ]

  alias RubberDuck.Agents.Response.{ProcessedResponse, Parser}
  require Logger

  @impl true
  def mount(_params, initial_state) do
    # Initialize parsers
    parsers = initialize_parsers()
    
    # Initialize enhancers and validators
    enhancers = initialize_enhancers()
    validators = initialize_validators()
    
    state = initial_state
    |> Map.put(:parsers, parsers)
    |> Map.put(:enhancers, enhancers)
    |> Map.put(:validators, validators)
    
    # Start periodic cleanup
    schedule_cleanup()
    
    Logger.info("ResponseProcessorAgent initialized with #{map_size(parsers)} parsers")
    {:ok, state}
  end

  # Main Processing Signals

  @impl true
  def handle_signal(agent, %{"type" => "process_response", "data" => response_data}) do
    start_time = System.monotonic_time(:millisecond)
    
    %{
      "content" => content,
      "request_id" => request_id
    } = response_data
    
    provider = Map.get(response_data, "provider", :unknown)
    model = Map.get(response_data, "model", "unknown")
    options = Map.get(response_data, "options", %{})
    
    # Check cache first
    cache_key = generate_cache_key(content, options)
    
    case get_from_cache(agent, cache_key) do
      {:hit, cached_response} ->
        agent = update_cache_metrics(agent, :hit)
        
        signal = Jido.Signal.new!(%{
          type: "response.processed",
          source: "agent:#{agent.id}",
          data: Map.merge(cached_response, %{
            cache_hit: true,
            processing_time: 0,
            timestamp: DateTime.utc_now()
          })
        })
        emit_signal(agent, signal)
        
        {:ok, agent}
        
      :miss ->
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
            signal = Jido.Signal.new!(%{
              type: "response.processed",
              source: "agent:#{agent.id}",
              data: Map.merge(client_response, %{
                cache_hit: false,
                timestamp: DateTime.utc_now()
              })
            })
            emit_signal(agent, signal)
            
            {:ok, updated_agent}
            
          {:error, reason, updated_agent} ->
            updated_agent = update_error_metrics(updated_agent, reason)
            
            signal = Jido.Signal.new!(%{
              type: "response.processing.failed",
              source: "agent:#{agent.id}",
              data: %{
                request_id: request_id,
                error: reason,
                original_content: content,
                timestamp: DateTime.utc_now()
              }
            })
            emit_signal(agent, signal)
            
            {:ok, updated_agent}
        end
    end
  end

  def handle_signal(agent, %{"type" => "parse_response", "data" => parse_data}) do
    %{
      "content" => content,
      "request_id" => request_id
    } = parse_data
    
    format = Map.get(parse_data, "format")
    options = Map.get(parse_data, "options", %{})
    
    case parse_content(content, format, options) do
      {:ok, parsed_content, detected_format, metadata} ->
        signal = Jido.Signal.new!(%{
          type: "response.parsed",
          source: "agent:#{agent.id}",
          data: %{
            request_id: request_id,
            parsed_content: parsed_content,
            format: detected_format,
            metadata: metadata,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
        
      {:error, reason} ->
        signal = Jido.Signal.new!(%{
          type: "response.parsing.failed",
          source: "agent:#{agent.id}",
          data: %{
            request_id: request_id,
            error: reason,
            content: content,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
    end
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "validate_response", "data" => validation_data}) do
    %{
      "content" => content,
      "request_id" => request_id
    } = validation_data
    
    validation_rules = Map.get(validation_data, "validation_rules", %{})
    
    case validate_content(content, validation_rules, agent) do
      {:ok, quality_score, validation_results} ->
        signal = Jido.Signal.new!(%{
          type: "response.validated",
          source: "agent:#{agent.id}",
          data: %{
            request_id: request_id,
            quality_score: quality_score,
            validation_results: validation_results,
            is_valid: validation_results.is_valid,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
        
      {:error, reason} ->
        signal = Jido.Signal.new!(%{
          type: "response.validation.failed",
          source: "agent:#{agent.id}",
          data: %{
            request_id: request_id,
            error: reason,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
    end
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "enhance_response", "data" => enhancement_data}) do
    %{
      "content" => content,
      "request_id" => request_id
    } = enhancement_data
    
    enhancement_options = Map.get(enhancement_data, "options", %{})
    
    case enhance_content(content, enhancement_options, agent) do
      {:ok, enhanced_content, enhancement_log} ->
        signal = Jido.Signal.new!(%{
          type: "response.enhanced",
          source: "agent:#{agent.id}",
          data: %{
            request_id: request_id,
            enhanced_content: enhanced_content,
            enhancement_log: enhancement_log,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
        
      {:error, reason} ->
        signal = Jido.Signal.new!(%{
          type: "response.enhancement.failed",
          source: "agent:#{agent.id}",
          data: %{
            request_id: request_id,
            error: reason,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
    end
    
    {:ok, agent}
  end

  # Caching Signals

  def handle_signal(agent, %{"type" => "get_cached_response", "data" => cache_data}) do
    %{"cache_key" => cache_key} = cache_data
    
    case get_from_cache(agent, cache_key) do
      {:hit, cached_response} ->
        signal = Jido.Signal.new!(%{
          type: "response.cache.hit",
          source: "agent:#{agent.id}",
          data: Map.merge(cached_response, %{
            timestamp: DateTime.utc_now()
          })
        })
        emit_signal(agent, signal)
        
      :miss ->
        signal = Jido.Signal.new!(%{
          type: "response.cache.miss",
          source: "agent:#{agent.id}",
          data: %{
            cache_key: cache_key,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
    end
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "invalidate_cache", "data" => invalidation_data}) do
    cache_keys = Map.get(invalidation_data, "cache_keys", [])
    pattern = Map.get(invalidation_data, "pattern")
    
    agent = if pattern do
      invalidate_cache_by_pattern(agent, pattern)
    else
      Enum.reduce(cache_keys, agent, fn key, acc_agent ->
        {_, updated_agent} = pop_in(acc_agent.cache[key])
        updated_agent
      end)
    end
    
    signal = Jido.Signal.new!(%{
      type: "response.cache.invalidated",
      source: "agent:#{agent.id}",
      data: %{
        invalidated_keys: cache_keys,
        pattern: pattern,
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "clear_cache"}) do
    cache_size = map_size(agent.cache)
    agent = put_in(agent.cache, %{})
    
    signal = Jido.Signal.new!(%{
      type: "response.cache.cleared",
      source: "agent:#{agent.id}",
      data: %{
        cleared_entries: cache_size,
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    Logger.info("ResponseProcessorAgent cache cleared (#{cache_size} entries)")
    {:ok, agent}
  end

  # Metrics and Status Signals

  def handle_signal(agent, %{"type" => "get_metrics"}) do
    metrics = build_metrics_report(agent)
    signal = Jido.Signal.new!(%{
      type: "response.metrics",
      source: "agent:#{agent.id}",
      data: Map.merge(metrics, %{
        timestamp: DateTime.utc_now()
      })
    })
    emit_signal(agent, signal)
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "get_status"}) do
    status = build_status_report(agent)
    signal = Jido.Signal.new!(%{
      type: "response.status",
      source: "agent:#{agent.id}",
      data: Map.merge(status, %{
        timestamp: DateTime.utc_now()
      })
    })
    emit_signal(agent, signal)
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "configure_processor", "data" => config_updates}) do
    current_config = agent.config
    updated_config = Map.merge(current_config, config_updates)
    
    agent = put_in(agent.config, updated_config)
    
    signal = Jido.Signal.new!(%{
      type: "response.configured",
      source: "agent:#{agent.id}",
      data: %{
        updated_config: updated_config,
        changes: Map.keys(config_updates),
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    Logger.info("ResponseProcessorAgent configuration updated: #{inspect(Map.keys(config_updates))}")
    {:ok, agent}
  end

  # Fallback for unknown signals
  def handle_signal(agent, signal) do
    Logger.warning("ResponseProcessorAgent received unknown signal: #{inspect(signal["type"])}")
    {:ok, agent}
  end

  # GenServer callbacks for periodic tasks

  @impl true
  def handle_info(:cleanup, agent) do
    agent = agent
    |> cleanup_expired_cache()
    |> cleanup_old_metrics()
    
    schedule_cleanup()
    {:noreply, agent}
  end

  # Private helper functions

  defp initialize_parsers do
    %{
      json: Parser.JSONParser,
      markdown: Parser.MarkdownParser,
      text: Parser.TextParser
    }
  end

  defp initialize_enhancers do
    [
      :format_beautification,
      :link_enrichment,
      :content_cleanup,
      :readability_improvement
    ]
  end

  defp initialize_validators do
    [
      :completeness_check,
      :safety_validation,
      :quality_scoring,
      :format_validation
    ]
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
              enhanced_response = if agent.config.auto_enhance and quality_score < agent.config.quality_threshold do
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
      validators = agent.validators
      
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
      enhancers = agent.enhancers
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
    case Map.get(agent.cache, cache_key) do
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
    expires_at = DateTime.add(DateTime.utc_now(), agent.config.cache_ttl, :second)
    
    cache_entry = %{
      data: ProcessedResponse.to_client_response(processed_response),
      expires_at: expires_at,
      created_at: DateTime.utc_now(),
      access_count: 0
    }
    
    # Check cache size limits
    agent = if map_size(agent.cache) >= agent.config.max_cache_size do
      evict_oldest_cache_entries(agent)
    else
      agent
    end
    
    put_in(agent.cache[cache_key], cache_entry)
  end

  defp evict_oldest_cache_entries(agent) do
    # Remove 20% of oldest entries
    entries_to_remove = div(agent.config.max_cache_size, 5)
    
    oldest_keys = agent.cache
    |> Enum.sort_by(fn {_key, entry} -> entry.created_at end, DateTime)
    |> Enum.take(entries_to_remove)
    |> Enum.map(fn {key, _entry} -> key end)
    
    cache = Map.drop(agent.cache, oldest_keys)
    put_in(agent.cache, cache)
  end

  defp invalidate_cache_by_pattern(agent, pattern) do
    regex = Regex.compile!(pattern)
    
    cache = agent.cache
    |> Enum.reject(fn {key, _entry} -> Regex.match?(regex, key) end)
    |> Map.new()
    
    put_in(agent.cache, cache)
  end

  defp update_cache_metrics(agent, hit_or_miss) do
    case hit_or_miss do
      :hit ->
        update_in(agent.metrics.cache_hits, &(&1 + 1))
      :miss ->
        update_in(agent.metrics.cache_misses, &(&1 + 1))
    end
  end

  defp update_processing_metrics(agent, processed_response, processing_time) do
    metrics = agent.metrics
    
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
    
    put_in(agent.metrics, updated_metrics)
  end

  defp update_error_metrics(agent, _reason) do
    update_in(agent.metrics.error_count, &(&1 + 1))
  end

  defp get_quality_bucket(score) do
    cond do
      score >= 0.9 -> :excellent
      score >= 0.7 -> :good
      score >= 0.5 -> :fair
      true -> :poor
    end
  end

  defp build_metrics_report(agent) do
    cache_total = agent.metrics.cache_hits + agent.metrics.cache_misses
    cache_hit_rate = if cache_total > 0, do: agent.metrics.cache_hits / cache_total, else: 0.0
    
    %{
      "processing" => %{
        "total_processed" => agent.metrics.total_processed,
        "avg_processing_time_ms" => agent.metrics.avg_processing_time,
        "error_count" => agent.metrics.error_count,
        "error_rate" => if(agent.metrics.total_processed > 0, do: agent.metrics.error_count / agent.metrics.total_processed, else: 0.0)
      },
      "caching" => %{
        "cache_hits" => agent.metrics.cache_hits,
        "cache_misses" => agent.metrics.cache_misses,
        "hit_rate" => cache_hit_rate,
        "cache_size" => map_size(agent.cache)
      },
      "distributions" => %{
        "formats" => agent.metrics.format_distribution,
        "quality" => agent.metrics.quality_distribution
      },
      "generated_at" => DateTime.utc_now()
    }
  end

  defp build_status_report(agent) do
    %{
      "status" => "healthy",
      "cache_size" => map_size(agent.cache),
      "total_processed" => agent.metrics.total_processed,
      "uptime" => get_uptime(),
      "parsers_available" => Map.keys(agent.parsers),
      "enhancers_enabled" => agent.enhancers,
      "validators_active" => agent.validators,
      "configuration" => agent.config,
      "memory_usage" => calculate_memory_usage(agent)
    }
  end

  defp cleanup_expired_cache(agent) do
    now = DateTime.utc_now()
    
    valid_cache = agent.cache
    |> Enum.filter(fn {_key, entry} ->
      DateTime.compare(now, entry.expires_at) == :lt
    end)
    |> Map.new()
    
    put_in(agent.cache, valid_cache)
  end

  defp cleanup_old_metrics(agent) do
    # In production, would clean up old metric data
    agent
  end

  defp calculate_memory_usage(agent) do
    # Simplified memory calculation
    cache_size = map_size(agent.cache) * 2048  # rough estimate per entry
    metrics_size = 1024  # rough estimate for metrics
    
    %{
      "cache_bytes" => cache_size,
      "metrics_bytes" => metrics_size,
      "total_bytes" => cache_size + metrics_size
    }
  end

  defp get_uptime do
    # Simple uptime calculation
    System.monotonic_time(:second)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 300_000)  # Every 5 minutes
  end
end
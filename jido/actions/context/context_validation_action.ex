defmodule RubberDuck.Jido.Actions.Context.ContextValidationAction do
  @moduledoc """
  Action for validating context quality and ensuring optimal LLM consumption.

  This action performs comprehensive validation of context entries including
  content quality assessment, relevance verification, completeness checking,
  and optimization recommendations for improved LLM performance.

  ## Parameters

  - `entries` - List of context entries to validate (required)
  - `request` - Context request for validation context (required)
  - `validation_types` - Types of validation to perform (default: [:quality, :relevance, :completeness])
  - `quality_threshold` - Minimum quality score for acceptance (default: 0.6)
  - `relevance_threshold` - Minimum relevance score for acceptance (default: 0.4)
  - `strict_mode` - Enable strict validation rules (default: false)
  - `fix_issues` - Attempt to automatically fix detected issues (default: true)
  - `report_details` - Include detailed issue reports (default: true)

  ## Returns

  - `{:ok, result}` - Validation completed with results and recommendations
  - `{:error, reason}` - Validation failed

  ## Example

      params = %{
        entries: context_entries,
        request: context_request,
        validation_types: [:quality, :relevance, :completeness, :security],
        quality_threshold: 0.7,
        strict_mode: true
      }

      {:ok, result} = ContextValidationAction.run(params, context)
  """

  use Jido.Action,
    name: "context_validation",
    description: "Validate context quality and ensure optimal LLM consumption",
    schema: [
      entries: [
        type: :list,
        required: true,
        doc: "List of context entries to validate"
      ],
      request: [
        type: :map,
        required: true,
        doc: "Context request for validation context"
      ],
      validation_types: [
        type: {:list, :atom},
        default: [:quality, :relevance, :completeness],
        doc: "Types of validation to perform"
      ],
      quality_threshold: [
        type: :float,
        default: 0.6,
        doc: "Minimum quality score for acceptance (0.0-1.0)"
      ],
      relevance_threshold: [
        type: :float,
        default: 0.4,
        doc: "Minimum relevance score for acceptance (0.0-1.0)"
      ],
      strict_mode: [
        type: :boolean,
        default: false,
        doc: "Enable strict validation rules"
      ],
      fix_issues: [
        type: :boolean,
        default: true,
        doc: "Attempt to automatically fix detected issues"
      ],
      report_details: [
        type: :boolean,
        default: true,
        doc: "Include detailed issue reports"
      ],
      max_token_variance: [
        type: :float,
        default: 0.3,
        doc: "Maximum allowed variance in token distribution"
      ],
      require_metadata: [
        type: {:list, :atom},
        default: [],
        doc: "Required metadata fields for entries"
      ]
    ]

  require Logger

  alias RubberDuck.Context.ContextEntry

  @impl true
  def run(params, context) do
    Logger.info("Starting context validation with types: #{inspect(params.validation_types)}")

    with {:ok, validation_results} <- perform_all_validations(params),
         {:ok, fixed_entries} <- apply_fixes_if_enabled(params, validation_results),
         {:ok, final_report} <- generate_validation_report(params, validation_results, fixed_entries) do
      
      result = %{
        validated_entries: fixed_entries,
        validation_passed: final_report.overall_passed,
        quality_score: final_report.overall_quality_score,
        issues_found: final_report.total_issues,
        issues_fixed: final_report.issues_fixed,
        validation_results: validation_results,
        recommendations: final_report.recommendations,
        metadata: %{
          validated_at: DateTime.utc_now(),
          validation_types: params.validation_types,
          strict_mode: params.strict_mode,
          original_count: length(params.entries),
          final_count: length(fixed_entries)
        }
      }

      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Context validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Main validation orchestration

  defp perform_all_validations(params) do
    validation_results = Enum.reduce(params.validation_types, %{}, fn type, acc ->
      case perform_validation_type(type, params) do
        {:ok, result} -> Map.put(acc, type, result)
        {:error, reason} -> 
          Logger.warning("Validation type #{type} failed: #{inspect(reason)}")
          Map.put(acc, type, %{passed: false, error: reason})
      end
    end)
    
    {:ok, validation_results}
  end

  defp perform_validation_type(:quality, params) do
    validate_content_quality(params.entries, params)
  end

  defp perform_validation_type(:relevance, params) do
    validate_relevance(params.entries, params.request, params)
  end

  defp perform_validation_type(:completeness, params) do
    validate_completeness(params.entries, params.request, params)
  end

  defp perform_validation_type(:consistency, params) do
    validate_consistency(params.entries, params)
  end

  defp perform_validation_type(:security, params) do
    validate_security(params.entries, params)
  end

  defp perform_validation_type(:structure, params) do
    validate_structure(params.entries, params)
  end

  defp perform_validation_type(:metadata, params) do
    validate_metadata(params.entries, params)
  end

  defp perform_validation_type(unknown_type, _params) do
    {:error, {:unknown_validation_type, unknown_type}}
  end

  # Quality validation

  defp validate_content_quality(entries, params) do
    quality_issues = []
    
    {passing_entries, failing_entries, detailed_issues} = Enum.reduce(entries, {[], [], []}, fn entry, {passing, failing, issues} ->
      quality_score = calculate_content_quality_score(entry)
      
      if quality_score >= params.quality_threshold do
        {[entry | passing], failing, issues}
      else
        quality_issues = identify_quality_issues(entry, quality_score, params)
        {passing, [entry | failing], quality_issues ++ issues}
      end
    end)
    
    result = %{
      passed: length(failing_entries) == 0,
      passing_count: length(passing_entries),
      failing_count: length(failing_entries),
      average_quality: calculate_average_quality(entries),
      threshold: params.quality_threshold,
      issues: detailed_issues,
      failing_entries: failing_entries
    }
    
    {:ok, result}
  end

  defp calculate_content_quality_score(entry) do
    base_score = 0.5
    
    # Content length assessment
    length_score = case entry.size_tokens do
      tokens when tokens < 10 -> 0.2  # Too short
      tokens when tokens > 2000 -> 0.3  # Very long, might be noisy
      tokens when tokens >= 50 and tokens <= 500 -> 1.0  # Good length
      _ -> 0.7
    end
    
    # Content structure assessment
    structure_score = assess_content_structure(entry.content)
    
    # Compression/summarization penalty
    processing_penalty = case {entry.compressed, entry.summarized} do
      {true, true} -> -0.3
      {true, false} -> -0.1
      {false, true} -> -0.2
      {false, false} -> 0.0
    end
    
    # Metadata richness
    metadata_score = if map_size(entry.metadata) >= 3, do: 0.1, else: 0.0
    
    final_score = base_score + (length_score * 0.3) + (structure_score * 0.4) + processing_penalty + metadata_score
    
    max(0.0, min(1.0, final_score))
  end

  defp assess_content_structure(content) when is_binary(content) do
    # Check for structured content indicators
    structure_indicators = [
      {~r/^#/, 0.1},  # Headers
      {~r/^-|\*/, 0.1},  # Lists
      {~r/```/, 0.2},  # Code blocks
      {~r/\n\n/, 0.1},  # Paragraphs
      {~r/[.!?]/, 0.1}  # Sentences
    ]
    
    Enum.reduce(structure_indicators, 0.0, fn {pattern, score}, acc ->
      if String.match?(content, pattern) do
        acc + score
      else
        acc
      end
    end)
    |> min(1.0)
  end

  defp assess_content_structure(_content), do: 0.5

  defp identify_quality_issues(entry, quality_score, params) do
    issues = []
    
    # Check specific quality problems
    issues = if entry.size_tokens < 10 do
      [%{type: :too_short, entry_id: entry.id, severity: :warning, 
         message: "Entry content is very short (#{entry.size_tokens} tokens)"} | issues]
    else
      issues
    end
    
    issues = if entry.size_tokens > 2000 do
      [%{type: :too_long, entry_id: entry.id, severity: :info,
         message: "Entry content is very long (#{entry.size_tokens} tokens), consider compression"} | issues]
    else
      issues
    end
    
    issues = if entry.compressed and entry.summarized do
      [%{type: :over_processed, entry_id: entry.id, severity: :warning,
         message: "Entry has been both compressed and summarized, quality may be degraded"} | issues]
    else
      issues
    end
    
    issues = if quality_score < params.quality_threshold * 0.5 do
      [%{type: :very_low_quality, entry_id: entry.id, severity: :error,
         message: "Entry quality score (#{Float.round(quality_score, 2)}) is very low"} | issues]
    else
      issues
    end
    
    issues
  end

  # Relevance validation

  defp validate_relevance(entries, request, params) do
    {relevant_entries, irrelevant_entries, detailed_issues} = Enum.reduce(entries, {[], [], []}, fn entry, {relevant, irrelevant, issues} ->
      relevance_score = calculate_relevance_score(entry, request)
      
      if relevance_score >= params.relevance_threshold do
        {[entry | relevant], irrelevant, issues}
      else
        relevance_issues = identify_relevance_issues(entry, relevance_score, request, params)
        {relevant, [entry | irrelevant], relevance_issues ++ issues}
      end
    end)
    
    result = %{
      passed: length(irrelevant_entries) == 0,
      relevant_count: length(relevant_entries),
      irrelevant_count: length(irrelevant_entries),
      average_relevance: calculate_average_relevance(entries, request),
      threshold: params.relevance_threshold,
      issues: detailed_issues,
      irrelevant_entries: irrelevant_entries
    }
    
    {:ok, result}
  end

  defp calculate_relevance_score(entry, request) do
    base_relevance = entry.relevance_score || 0.5
    
    # Purpose alignment
    purpose_alignment = calculate_purpose_alignment(entry, request.purpose)
    
    # Filter matching
    filter_alignment = calculate_filter_alignment(entry, request.filters || %{})
    
    # Recency factor
    recency_factor = calculate_recency_factor(entry.timestamp)
    
    # Combine scores
    final_score = (base_relevance * 0.4) + (purpose_alignment * 0.3) + 
                  (filter_alignment * 0.2) + (recency_factor * 0.1)
    
    max(0.0, min(1.0, final_score))
  end

  defp calculate_purpose_alignment(entry, purpose) do
    purpose_keywords = extract_purpose_keywords(purpose)
    content_string = entry_content_to_string(entry)
    
    if Enum.empty?(purpose_keywords) do
      0.5  # Neutral if no specific purpose
    else
      matching_keywords = Enum.count(purpose_keywords, fn keyword ->
        String.contains?(String.downcase(content_string), String.downcase(keyword))
      end)
      
      matching_keywords / length(purpose_keywords)
    end
  end

  defp calculate_filter_alignment(entry, filters) do
    if map_size(filters) == 0 do
      1.0  # No filters to match
    else
      matching_filters = Enum.count(filters, fn {key, value} ->
        entry_value = get_nested_metadata(entry.metadata, key)
        entry_value == value
      end)
      
      matching_filters / map_size(filters)
    end
  end

  defp calculate_recency_factor(timestamp) do
    age_hours = DateTime.diff(DateTime.utc_now(), timestamp, :hour)
    
    cond do
      age_hours < 1 -> 1.0
      age_hours < 24 -> 0.8
      age_hours < 168 -> 0.6  # 1 week
      age_hours < 720 -> 0.4  # 1 month
      true -> 0.2
    end
  end

  defp identify_relevance_issues(entry, relevance_score, request, params) do
    issues = []
    
    issues = if relevance_score < params.relevance_threshold * 0.5 do
      [%{type: :very_low_relevance, entry_id: entry.id, severity: :warning,
         message: "Entry relevance score (#{Float.round(relevance_score, 2)}) is very low for purpose '#{request.purpose}'"} | issues]
    else
      issues
    end
    
    # Check if entry matches any filters
    filter_matches = calculate_filter_alignment(entry, request.filters || %{})
    issues = if filter_matches == 0.0 and map_size(request.filters || %{}) > 0 do
      [%{type: :no_filter_match, entry_id: entry.id, severity: :info,
         message: "Entry does not match any request filters"} | issues]
    else
      issues
    end
    
    issues
  end

  # Completeness validation

  defp validate_completeness(entries, request, params) do
    issues = []
    
    # Check for required source coverage
    {source_issues, source_coverage} = validate_source_coverage(entries, request)
    issues = source_issues ++ issues
    
    # Check for content diversity
    {diversity_issues, diversity_score} = validate_content_diversity(entries)
    issues = diversity_issues ++ issues
    
    # Check for token distribution
    {distribution_issues, distribution_score} = validate_token_distribution(entries, params)
    issues = distribution_issues ++ issues
    
    # Check for required metadata
    {metadata_issues, metadata_coverage} = validate_required_metadata(entries, params)
    issues = metadata_issues ++ issues
    
    completeness_score = (source_coverage + diversity_score + distribution_score + metadata_coverage) / 4
    
    result = %{
      passed: Enum.all?([source_coverage, diversity_score, distribution_score, metadata_coverage], &(&1 >= 0.7)),
      completeness_score: completeness_score,
      source_coverage: source_coverage,
      diversity_score: diversity_score,
      distribution_score: distribution_score,
      metadata_coverage: metadata_coverage,
      issues: issues
    }
    
    {:ok, result}
  end

  defp validate_source_coverage(entries, request) do
    required_sources = request.required_sources || []
    available_sources = entries |> Enum.map(& &1.source) |> Enum.uniq()
    
    if Enum.empty?(required_sources) do
      {[], 1.0}  # No specific requirements
    else
      missing_sources = required_sources -- available_sources
      coverage = (length(required_sources) - length(missing_sources)) / length(required_sources)
      
      issues = Enum.map(missing_sources, fn source ->
        %{type: :missing_required_source, source: source, severity: :error,
          message: "Required source '#{source}' is not represented in context"}
      end)
      
      {issues, coverage}
    end
  end

  defp validate_content_diversity(entries) do
    if length(entries) < 2 do
      {[], 1.0}
    else
      # Calculate pairwise similarities
      similarities = calculate_pairwise_similarities(entries)
      avg_similarity = Enum.sum(similarities) / length(similarities)
      
      diversity_score = 1.0 - avg_similarity
      
      issues = if avg_similarity > 0.8 do
        [%{type: :low_content_diversity, severity: :warning,
           message: "Content entries are very similar (avg similarity: #{Float.round(avg_similarity, 2)})"}]
      else
        []
      end
      
      {issues, diversity_score}
    end
  end

  defp validate_token_distribution(entries, params) do
    if Enum.empty?(entries) do
      {[], 1.0}
    else
      token_counts = Enum.map(entries, & &1.size_tokens)
      mean_tokens = Enum.sum(token_counts) / length(token_counts)
      
      variance = Enum.reduce(token_counts, 0, fn tokens, acc ->
        acc + :math.pow(tokens - mean_tokens, 2)
      end) / length(token_counts)
      
      std_dev = :math.sqrt(variance)
      coefficient_of_variation = if mean_tokens > 0, do: std_dev / mean_tokens, else: 0.0
      
      distribution_score = max(0.0, 1.0 - coefficient_of_variation)
      
      issues = if coefficient_of_variation > params.max_token_variance do
        [%{type: :uneven_token_distribution, severity: :info,
           message: "Token distribution is uneven (CV: #{Float.round(coefficient_of_variation, 2)})"}]
      else
        []
      end
      
      {issues, distribution_score}
    end
  end

  defp validate_required_metadata(entries, params) do
    required_fields = params.require_metadata || []
    
    if Enum.empty?(required_fields) do
      {[], 1.0}
    else
      {missing_issues, coverage_scores} = Enum.reduce(entries, {[], []}, fn entry, {issues, scores} ->
        missing_fields = Enum.filter(required_fields, fn field ->
          not Map.has_key?(entry.metadata, field)
        end)
        
        coverage = (length(required_fields) - length(missing_fields)) / length(required_fields)
        
        entry_issues = Enum.map(missing_fields, fn field ->
          %{type: :missing_required_metadata, entry_id: entry.id, field: field, severity: :warning,
            message: "Entry missing required metadata field: #{field}"}
        end)
        
        {entry_issues ++ issues, [coverage | scores]}
      end)
      
      avg_coverage = if Enum.empty?(coverage_scores), do: 1.0, else: Enum.sum(coverage_scores) / length(coverage_scores)
      
      {missing_issues, avg_coverage}
    end
  end

  # Additional validation types

  defp validate_consistency(entries, _params) do
    # Check for consistent metadata schemas, timestamps, etc.
    consistency_issues = []
    
    # Check timestamp consistency
    timestamps = Enum.map(entries, & &1.timestamp)
    timestamp_spread = DateTime.diff(Enum.max(timestamps), Enum.min(timestamps), :hour)
    
    consistency_issues = if timestamp_spread > 168 do  # 1 week
      [%{type: :large_timestamp_spread, severity: :info,
         message: "Entries span a large time range (#{timestamp_spread} hours)"} | consistency_issues]
    else
      consistency_issues
    end
    
    result = %{
      passed: Enum.empty?(consistency_issues),
      timestamp_spread_hours: timestamp_spread,
      issues: consistency_issues
    }
    
    {:ok, result}
  end

  defp validate_security(entries, _params) do
    security_issues = []
    
    # Check for sensitive information patterns
    sensitive_patterns = [
      {~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, :email},
      {~r/\b\d{3}-\d{2}-\d{4}\b/, :ssn},
      {~r/\b(?:\d{4}[-\s]?){3}\d{4}\b/, :credit_card},
      {~r/password\s*[:=]\s*\S+/i, :password}
    ]
    
    Enum.each(entries, fn entry ->
      content_string = entry_content_to_string(entry)
      
      Enum.each(sensitive_patterns, fn {pattern, type} ->
        if String.match?(content_string, pattern) do
          security_issues = [%{type: :sensitive_data, entry_id: entry.id, data_type: type, severity: :error,
                               message: "Entry may contain sensitive #{type} data"} | security_issues]
        end
      end)
    end)
    
    result = %{
      passed: Enum.empty?(security_issues),
      sensitive_data_found: length(security_issues),
      issues: security_issues
    }
    
    {:ok, result}
  end

  defp validate_structure(entries, _params) do
    structure_issues = []
    
    # Check for proper entry structure
    Enum.each(entries, fn entry ->
      structure_issues = if is_nil(entry.id) or entry.id == "" do
        [%{type: :missing_id, entry_id: "unknown", severity: :error,
           message: "Entry missing required ID"} | structure_issues]
      else
        structure_issues
      end
      
      structure_issues = if is_nil(entry.source) or entry.source == "" do
        [%{type: :missing_source, entry_id: entry.id, severity: :error,
           message: "Entry missing source identifier"} | structure_issues]
      else
        structure_issues
      end
      
      structure_issues = if is_nil(entry.timestamp) do
        [%{type: :missing_timestamp, entry_id: entry.id, severity: :warning,
           message: "Entry missing timestamp"} | structure_issues]
      else
        structure_issues
      end
    end)
    
    result = %{
      passed: Enum.empty?(structure_issues),
      structure_violations: length(structure_issues),
      issues: structure_issues
    }
    
    {:ok, result}
  end

  # Issue fixing

  defp apply_fixes_if_enabled(params, validation_results) do
    if params.fix_issues do
      fixed_entries = apply_automatic_fixes(params.entries, validation_results)
      {:ok, fixed_entries}
    else
      {:ok, params.entries}
    end
  end

  defp apply_automatic_fixes(entries, validation_results) do
    # Apply fixes for automatically correctable issues
    Enum.map(entries, fn entry ->
      entry
      |> fix_missing_id()
      |> fix_missing_timestamp()
      |> fix_quality_issues(validation_results)
    end)
  end

  defp fix_missing_id(entry) do
    if is_nil(entry.id) or entry.id == "" do
      %{entry | id: generate_entry_id()}
    else
      entry
    end
  end

  defp fix_missing_timestamp(entry) do
    if is_nil(entry.timestamp) do
      %{entry | timestamp: DateTime.utc_now()}
    else
      entry
    end
  end

  defp fix_quality_issues(entry, validation_results) do
    quality_result = Map.get(validation_results, :quality, %{})
    
    # If entry failed quality check and is too short, try to enhance it
    if entry in Map.get(quality_result, :failing_entries, []) and entry.size_tokens < 10 do
      enhanced_content = enhance_short_content(entry.content)
      %{entry | content: enhanced_content, size_tokens: estimate_tokens(enhanced_content)}
    else
      entry
    end
  end

  defp enhance_short_content(content) when is_binary(content) and byte_size(content) < 50 do
    # Add minimal context if content is very short
    "Context: " <> content
  end

  defp enhance_short_content(content), do: content

  # Report generation

  defp generate_validation_report(params, validation_results, fixed_entries) do
    all_issues = validation_results
    |> Map.values()
    |> Enum.flat_map(&(Map.get(&1, :issues, [])))
    
    issues_by_severity = Enum.group_by(all_issues, & &1.severity)
    
    overall_passed = Enum.all?(validation_results, fn {_type, result} ->
      Map.get(result, :passed, false)
    end)
    
    overall_quality_score = calculate_overall_quality_score(validation_results)
    
    recommendations = generate_recommendations(validation_results, all_issues)
    
    report = %{
      overall_passed: overall_passed,
      overall_quality_score: overall_quality_score,
      total_issues: length(all_issues),
      issues_fixed: count_fixed_issues(params.entries, fixed_entries),
      issues_by_severity: %{
        error: length(Map.get(issues_by_severity, :error, [])),
        warning: length(Map.get(issues_by_severity, :warning, [])),
        info: length(Map.get(issues_by_severity, :info, []))
      },
      recommendations: recommendations,
      validation_summary: summarize_validation_results(validation_results)
    }
    
    {:ok, report}
  end

  defp calculate_overall_quality_score(validation_results) do
    scores = validation_results
    |> Map.values()
    |> Enum.map(fn result ->
      cond do
        Map.has_key?(result, :completeness_score) -> result.completeness_score
        Map.has_key?(result, :average_quality) -> result.average_quality
        Map.has_key?(result, :average_relevance) -> result.average_relevance
        Map.get(result, :passed, false) -> 1.0
        true -> 0.0
      end
    end)
    
    if Enum.empty?(scores), do: 0.0, else: Enum.sum(scores) / length(scores)
  end

  defp generate_recommendations(validation_results, issues) do
    recommendations = []
    
    # Quality recommendations
    quality_result = Map.get(validation_results, :quality, %{})
    recommendations = if Map.get(quality_result, :average_quality, 1.0) < 0.7 do
      ["Consider improving content quality through better source selection or preprocessing" | recommendations]
    else
      recommendations
    end
    
    # Relevance recommendations
    relevance_result = Map.get(validation_results, :relevance, %{})
    recommendations = if Map.get(relevance_result, :average_relevance, 1.0) < 0.6 do
      ["Review context request filters and purpose to improve relevance matching" | recommendations]
    else
      recommendations
    end
    
    # Security recommendations
    security_issues = Enum.filter(issues, &(&1.type == :sensitive_data))
    recommendations = if length(security_issues) > 0 do
      ["Remove or redact sensitive information from context entries" | recommendations]
    else
      recommendations
    end
    
    # Add generic recommendations based on issue patterns
    error_count = Enum.count(issues, &(&1.severity == :error))
    recommendations = if error_count > 0 do
      ["Address #{error_count} critical validation errors before using context" | recommendations]
    else
      recommendations
    end
    
    Enum.reverse(recommendations)
  end

  # Helper functions

  defp calculate_average_quality(entries) do
    if Enum.empty?(entries) do
      0.0
    else
      qualities = Enum.map(entries, &calculate_content_quality_score/1)
      Enum.sum(qualities) / length(qualities)
    end
  end

  defp calculate_average_relevance(entries, request) do
    if Enum.empty?(entries) do
      0.0
    else
      relevances = Enum.map(entries, &calculate_relevance_score(&1, request))
      Enum.sum(relevances) / length(relevances)
    end
  end

  defp calculate_pairwise_similarities(entries) do
    for i <- 0..(length(entries) - 1),
        j <- (i + 1)..(length(entries) - 1) do
      entry1 = Enum.at(entries, i)
      entry2 = Enum.at(entries, j)
      ContextEntry.similar?(entry1, entry2, 0.0)  # Get raw similarity score
    end
  end

  defp summarize_validation_results(validation_results) do
    Map.new(validation_results, fn {type, result} ->
      summary = %{
        passed: Map.get(result, :passed, false),
        issue_count: length(Map.get(result, :issues, []))
      }
      {type, summary}
    end)
  end

  defp count_fixed_issues(original_entries, fixed_entries) do
    # Simple count based on entries that changed
    changed_count = Enum.zip(original_entries, fixed_entries)
    |> Enum.count(fn {original, fixed} -> original != fixed end)
    
    changed_count
  end

  defp extract_purpose_keywords(purpose) do
    case purpose do
      "code_generation" -> ["code", "function", "class", "method", "implementation"]
      "debugging" -> ["error", "bug", "issue", "problem", "exception"]
      "planning" -> ["plan", "strategy", "goal", "requirement", "task"]
      "documentation" -> ["docs", "documentation", "guide", "manual"]
      _ -> String.split(purpose, ~r/[^a-zA-Z0-9]/) |> Enum.filter(&(String.length(&1) > 2))
    end
  end

  defp entry_content_to_string(entry) do
    case entry.content do
      content when is_binary(content) -> content
      content when is_map(content) -> Jason.encode!(content)
      content -> inspect(content)
    end
  end

  defp get_nested_metadata(metadata, key) when is_binary(key) do
    keys = String.split(key, ".")
    get_in(metadata, Enum.map(keys, &String.to_atom/1))
  end
  defp get_nested_metadata(metadata, key), do: Map.get(metadata, key)

  defp estimate_tokens(content) when is_binary(content) do
    div(String.length(content), 4)
  end
  defp estimate_tokens(_), do: 0

  defp generate_entry_id do
    "ctx_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
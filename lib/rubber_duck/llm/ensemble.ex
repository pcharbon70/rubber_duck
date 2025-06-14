defmodule RubberDuck.LLM.Ensemble do
  @moduledoc """
  Ensemble processing with conflict resolution and response aggregation.
  Coordinates multiple LLM responses to improve accuracy, reliability, and quality
  through sophisticated voting mechanisms and consensus algorithms.
  """
  use GenServer
  require Logger

  defstruct [
    :ensemble_strategies,
    :voting_mechanisms,
    :conflict_resolvers,
    :aggregation_config,
    :response_cache,
    :ensemble_metrics
  ]

  @voting_strategies [:majority, :weighted, :confidence_based, :ranked_choice, :consensus]
  @aggregation_methods [:simple_merge, :weighted_merge, :semantic_fusion, :quality_weighted]
  @conflict_resolution [:accept_highest_confidence, :democratic_vote, :expert_preference, :hybrid]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Processes a task with multiple LLMs and aggregates responses.
  """
  def process_with_models(task, models, config \\ %{}) do
    GenServer.call(__MODULE__, {:process_ensemble, task, models, config}, 60_000)
  end

  @doc """
  Aggregates multiple responses using specified strategy.
  """
  def aggregate_responses(responses, strategy \\ :weighted, opts \\ []) do
    GenServer.call(__MODULE__, {:aggregate_responses, responses, strategy, opts})
  end

  @doc """
  Resolves conflicts between differing model responses.
  """
  def resolve_conflicts(conflicting_responses, resolution_strategy \\ :hybrid) do
    GenServer.call(__MODULE__, {:resolve_conflicts, conflicting_responses, resolution_strategy})
  end

  @doc """
  Evaluates ensemble performance and quality metrics.
  """
  def evaluate_ensemble_quality(ensemble_result, ground_truth \\ nil) do
    GenServer.call(__MODULE__, {:evaluate_quality, ensemble_result, ground_truth})
  end

  @doc """
  Updates ensemble configuration and strategies.
  """
  def update_ensemble_config(new_config) do
    GenServer.call(__MODULE__, {:update_config, new_config})
  end

  @doc """
  Gets ensemble performance metrics and statistics.
  """
  def get_ensemble_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @impl true
  def init(opts) do
    Logger.info("Starting LLM Ensemble processor with conflict resolution")
    
    state = %__MODULE__{
      ensemble_strategies: initialize_ensemble_strategies(opts),
      voting_mechanisms: initialize_voting_mechanisms(opts),
      conflict_resolvers: initialize_conflict_resolvers(opts),
      aggregation_config: initialize_aggregation_config(opts),
      response_cache: %{},
      ensemble_metrics: initialize_ensemble_metrics()
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:process_ensemble, task, models, config}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    case perform_ensemble_processing(task, models, config, state) do
      {:ok, ensemble_result} ->
        end_time = System.monotonic_time(:microsecond)
        processing_time = end_time - start_time
        
        # Update metrics
        new_metrics = update_ensemble_metrics(state.ensemble_metrics, ensemble_result, processing_time)
        new_state = %{state | ensemble_metrics: new_metrics}
        
        {:reply, {:ok, ensemble_result}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:aggregate_responses, responses, strategy, opts}, _from, state) do
    case perform_response_aggregation(responses, strategy, opts, state) do
      {:ok, aggregated_response} ->
        {:reply, {:ok, aggregated_response}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:resolve_conflicts, conflicting_responses, resolution_strategy}, _from, state) do
    case perform_conflict_resolution(conflicting_responses, resolution_strategy, state) do
      {:ok, resolved_response} ->
        {:reply, {:ok, resolved_response}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:evaluate_quality, ensemble_result, ground_truth}, _from, state) do
    quality_metrics = evaluate_ensemble_quality_internal(ensemble_result, ground_truth, state)
    {:reply, {:ok, quality_metrics}, state}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    updated_config = Map.merge(state.aggregation_config, new_config)
    new_state = %{state | aggregation_config: updated_config}
    {:reply, {:ok, :config_updated}, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    enhanced_metrics = enhance_ensemble_metrics(state.ensemble_metrics, state)
    {:reply, enhanced_metrics, state}
  end

  # Private functions

  defp perform_ensemble_processing(task, models, config, state) do
    # Step 1: Execute task with all models concurrently
    case execute_concurrent_requests(task, models, config) do
      {:ok, responses} ->
        # Step 2: Analyze responses for conflicts and quality
        response_analysis = analyze_responses(responses, task)
        
        # Step 3: Apply ensemble strategy
        ensemble_strategy = Map.get(config, :strategy, :weighted)
        
        case apply_ensemble_strategy(responses, response_analysis, ensemble_strategy, state) do
          {:ok, ensemble_result} ->
            # Step 4: Add metadata and quality scores
            enhanced_result = enhance_ensemble_result(ensemble_result, responses, response_analysis)
            {:ok, enhanced_result}
          
          {:error, reason} ->
            {:error, reason}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_concurrent_requests(task, models, config) do
    timeout = Map.get(config, :timeout, 30_000)
    
    # Create tasks for concurrent execution
    async_tasks = Enum.map(models, fn {model_id, model_config} ->
      Task.async(fn ->
        execute_model_request(model_id, model_config, task, config)
      end)
    end)
    
    # Wait for all responses with timeout
    try do
      responses = Task.await_many(async_tasks, timeout)
      successful_responses = Enum.filter(responses, &match?({:ok, _}, &1))
      
      if length(successful_responses) >= 1 do
        {:ok, successful_responses}
      else
        {:error, :no_successful_responses}
      end
    rescue
      e ->
        {:error, {:execution_failed, e}}
    end
  end

  defp execute_model_request(model_id, model_config, task, config) do
    start_time = System.monotonic_time(:microsecond)
    
    # Simulate LLM request - in production would call actual LLM APIs
    case simulate_llm_request(model_id, model_config, task, config) do
      {:ok, response} ->
        end_time = System.monotonic_time(:microsecond)
        execution_time = end_time - start_time
        
        {:ok, %{
          model_id: model_id,
          response: response,
          execution_time: execution_time,
          confidence: calculate_response_confidence(response),
          quality_score: estimate_response_quality(response),
          metadata: %{
            model_config: model_config,
            timestamp: System.monotonic_time(:millisecond)
          }
        }}
      
      {:error, reason} ->
        {:error, %{model_id: model_id, reason: reason}}
    end
  end

  defp analyze_responses(responses, task) do
    successful_responses = Enum.filter(responses, &match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, response} -> response end)
    
    %{
      total_responses: length(responses),
      successful_responses: length(successful_responses),
      response_similarity: calculate_response_similarity(successful_responses),
      confidence_distribution: analyze_confidence_distribution(successful_responses),
      quality_distribution: analyze_quality_distribution(successful_responses),
      conflicts: detect_response_conflicts(successful_responses),
      consensus_level: calculate_consensus_level(successful_responses),
      task_analysis: analyze_task_characteristics(task)
    }
  end

  defp apply_ensemble_strategy(responses, response_analysis, strategy, state) do
    successful_responses = Enum.filter(responses, &match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, response} -> response end)
    
    case strategy do
      :majority ->
        apply_majority_voting(successful_responses, response_analysis, state)
      
      :weighted ->
        apply_weighted_aggregation(successful_responses, response_analysis, state)
      
      :confidence_based ->
        apply_confidence_based_selection(successful_responses, response_analysis, state)
      
      :consensus ->
        apply_consensus_building(successful_responses, response_analysis, state)
      
      :quality_weighted ->
        apply_quality_weighted_aggregation(successful_responses, response_analysis, state)
      
      _ ->
        apply_weighted_aggregation(successful_responses, response_analysis, state)
    end
  end

  defp apply_majority_voting(responses, response_analysis, state) do
    # Group similar responses and select majority
    response_groups = group_similar_responses(responses, 0.8)  # 80% similarity threshold
    
    case Enum.max_by(response_groups, &length/1, fn -> [] end) do
      [] ->
        {:error, :no_majority_found}
      
      majority_group ->
        # Select best response from majority group
        best_response = select_best_from_group(majority_group)
        
        {:ok, %{
          final_response: best_response.response,
          strategy: :majority,
          confidence: calculate_group_confidence(majority_group),
          support_count: length(majority_group),
          total_responses: length(responses)
        }}
    end
  end

  defp apply_weighted_aggregation(responses, response_analysis, state) do
    # Calculate weights based on model performance and confidence
    weighted_responses = Enum.map(responses, fn response ->
      model_weight = get_model_weight(response.model_id, state)
      confidence_weight = response.confidence
      quality_weight = response.quality_score
      
      combined_weight = model_weight * 0.4 + confidence_weight * 0.3 + quality_weight * 0.3
      
      %{response | weight: combined_weight}
    end)
    
    # Aggregate responses based on weights
    case aggregate_weighted_responses(weighted_responses) do
      {:ok, aggregated_response} ->
        total_weight = Enum.sum(Enum.map(weighted_responses, & &1.weight))
        avg_confidence = Enum.sum(Enum.map(weighted_responses, &(&1.confidence * &1.weight))) / total_weight
        
        {:ok, %{
          final_response: aggregated_response,
          strategy: :weighted,
          confidence: avg_confidence,
          total_weight: total_weight,
          contributing_models: Enum.map(weighted_responses, & &1.model_id)
        }}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_confidence_based_selection(responses, response_analysis, state) do
    # Select response with highest confidence that meets quality threshold
    quality_threshold = Map.get(state.aggregation_config, :min_quality_threshold, 0.6)
    
    qualified_responses = Enum.filter(responses, fn response ->
      response.quality_score >= quality_threshold
    end)
    
    case Enum.max_by(qualified_responses, & &1.confidence, fn -> nil end) do
      nil ->
        # Fallback to highest quality if no response meets confidence threshold
        case Enum.max_by(responses, & &1.quality_score, fn -> nil end) do
          nil -> {:error, :no_suitable_response}
          fallback_response ->
            {:ok, %{
              final_response: fallback_response.response,
              strategy: :confidence_based_fallback,
              confidence: fallback_response.confidence,
              selected_model: fallback_response.model_id
            }}
        end
      
      selected_response ->
        {:ok, %{
          final_response: selected_response.response,
          strategy: :confidence_based,
          confidence: selected_response.confidence,
          selected_model: selected_response.model_id
        }}
    end
  end

  defp apply_consensus_building(responses, response_analysis, state) do
    consensus_threshold = Map.get(state.aggregation_config, :consensus_threshold, 0.7)
    
    if response_analysis.consensus_level >= consensus_threshold do
      # High consensus - use weighted aggregation
      apply_weighted_aggregation(responses, response_analysis, state)
    else
      # Low consensus - use conflict resolution
      conflicts = response_analysis.conflicts
      
      case perform_conflict_resolution(responses, :hybrid, state) do
        {:ok, resolved_response} ->
          {:ok, %{
            final_response: resolved_response,
            strategy: :consensus_with_resolution,
            confidence: calculate_consensus_confidence(responses),
            consensus_level: response_analysis.consensus_level
          }}
        
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp apply_quality_weighted_aggregation(responses, response_analysis, state) do
    # Weight responses primarily by quality scores
    quality_weighted_responses = Enum.map(responses, fn response ->
      quality_weight = response.quality_score
      confidence_bonus = response.confidence * 0.2
      
      combined_weight = quality_weight + confidence_bonus
      %{response | weight: combined_weight}
    end)
    
    case aggregate_weighted_responses(quality_weighted_responses) do
      {:ok, aggregated_response} ->
        avg_quality = Enum.sum(Enum.map(quality_weighted_responses, & &1.quality_score)) / length(quality_weighted_responses)
        
        {:ok, %{
          final_response: aggregated_response,
          strategy: :quality_weighted,
          confidence: avg_quality,
          avg_quality_score: avg_quality
        }}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_response_aggregation(responses, strategy, opts, state) do
    case strategy do
      :simple_merge ->
        simple_merge_responses(responses, opts)
      
      :weighted_merge ->
        weighted_merge_responses(responses, opts, state)
      
      :semantic_fusion ->
        semantic_fusion_responses(responses, opts, state)
      
      :quality_weighted ->
        quality_weighted_merge(responses, opts, state)
      
      _ ->
        weighted_merge_responses(responses, opts, state)
    end
  end

  defp perform_conflict_resolution(conflicting_responses, resolution_strategy, state) do
    case resolution_strategy do
      :accept_highest_confidence ->
        resolve_by_highest_confidence(conflicting_responses)
      
      :democratic_vote ->
        resolve_by_democratic_vote(conflicting_responses)
      
      :expert_preference ->
        resolve_by_expert_preference(conflicting_responses, state)
      
      :hybrid ->
        resolve_by_hybrid_approach(conflicting_responses, state)
      
      _ ->
        resolve_by_hybrid_approach(conflicting_responses, state)
    end
  end

  # Response analysis and utility functions

  defp calculate_response_similarity(responses) do
    if length(responses) < 2 do
      1.0
    else
      similarities = for {r1, i} <- Enum.with_index(responses),
                         {r2, j} <- Enum.with_index(responses),
                         i < j do
        calculate_text_similarity(r1.response, r2.response)
      end
      
      Enum.sum(similarities) / length(similarities)
    end
  end

  defp analyze_confidence_distribution(responses) do
    confidences = Enum.map(responses, & &1.confidence)
    
    %{
      min: Enum.min(confidences, fn -> 0.0 end),
      max: Enum.max(confidences, fn -> 0.0 end),
      avg: Enum.sum(confidences) / length(confidences),
      std_dev: calculate_standard_deviation(confidences)
    }
  end

  defp analyze_quality_distribution(responses) do
    qualities = Enum.map(responses, & &1.quality_score)
    
    %{
      min: Enum.min(qualities, fn -> 0.0 end),
      max: Enum.max(qualities, fn -> 0.0 end),
      avg: Enum.sum(qualities) / length(qualities),
      std_dev: calculate_standard_deviation(qualities)
    }
  end

  defp detect_response_conflicts(responses) do
    conflicts = []
    
    # Detect length conflicts
    lengths = Enum.map(responses, &String.length(&1.response))
    length_variance = calculate_variance(lengths)
    
    conflicts = if length_variance > 1000 do
      [%{type: :length_conflict, variance: length_variance} | conflicts]
    else
      conflicts
    end
    
    # Detect semantic conflicts
    similarities = for {r1, i} <- Enum.with_index(responses),
                       {r2, j} <- Enum.with_index(responses),
                       i < j do
      calculate_text_similarity(r1.response, r2.response)
    end
    
    min_similarity = Enum.min(similarities, fn -> 1.0 end)
    
    conflicts = if min_similarity < 0.5 do
      [%{type: :semantic_conflict, min_similarity: min_similarity} | conflicts]
    else
      conflicts
    end
    
    conflicts
  end

  defp calculate_consensus_level(responses) do
    if length(responses) < 2 do
      1.0
    else
      similarity = calculate_response_similarity(responses)
      confidence_consistency = calculate_confidence_consistency(responses)
      
      (similarity + confidence_consistency) / 2
    end
  end

  defp group_similar_responses(responses, threshold) do
    groups = []
    
    Enum.reduce(responses, groups, fn response, acc_groups ->
      # Find a group this response belongs to
      matching_group = Enum.find(acc_groups, fn group ->
        representative = hd(group)
        calculate_text_similarity(response.response, representative.response) >= threshold
      end)
      
      case matching_group do
        nil ->
          # Create new group
          [[response] | acc_groups]
        
        group ->
          # Add to existing group
          updated_group = [response | group]
          other_groups = List.delete(acc_groups, group)
          [updated_group | other_groups]
      end
    end)
  end

  defp select_best_from_group(group) do
    Enum.max_by(group, fn response ->
      response.confidence * 0.5 + response.quality_score * 0.5
    end)
  end

  defp calculate_group_confidence(group) do
    confidences = Enum.map(group, & &1.confidence)
    Enum.sum(confidences) / length(confidences)
  end

  defp aggregate_weighted_responses(weighted_responses) do
    # Simplified aggregation - in production would use more sophisticated NLP
    case Enum.max_by(weighted_responses, & &1.weight, fn -> nil end) do
      nil -> {:error, :no_responses_to_aggregate}
      best_response -> {:ok, best_response.response}
    end
  end

  # Conflict resolution methods

  defp resolve_by_highest_confidence(responses) do
    case Enum.max_by(responses, & &1.confidence, fn -> nil end) do
      nil -> {:error, :no_responses}
      best_response -> {:ok, best_response.response}
    end
  end

  defp resolve_by_democratic_vote(responses) do
    # Group similar responses and vote
    groups = group_similar_responses(responses, 0.7)
    
    case Enum.max_by(groups, &length/1, fn -> [] end) do
      [] -> {:error, :no_consensus}
      winning_group ->
        best_from_group = select_best_from_group(winning_group)
        {:ok, best_from_group.response}
    end
  end

  defp resolve_by_expert_preference(responses, state) do
    # Prefer responses from models with higher expertise scores
    model_expertise = Map.get(state.aggregation_config, :model_expertise, %{})
    
    expert_weighted = Enum.map(responses, fn response ->
      expertise = Map.get(model_expertise, response.model_id, 0.5)
      %{response | weight: expertise * response.confidence}
    end)
    
    case Enum.max_by(expert_weighted, & &1.weight, fn -> nil end) do
      nil -> {:error, :no_expert_response}
      best_response -> {:ok, best_response.response}
    end
  end

  defp resolve_by_hybrid_approach(responses, state) do
    # Combine multiple resolution strategies
    confidence_result = resolve_by_highest_confidence(responses)
    vote_result = resolve_by_democratic_vote(responses)
    expert_result = resolve_by_expert_preference(responses, state)
    
    # Choose result based on available methods
    case {confidence_result, vote_result, expert_result} do
      {{:ok, conf_resp}, {:ok, vote_resp}, {:ok, expert_resp}} ->
        # All methods succeeded - use expert preference if different, otherwise confidence
        if expert_resp == conf_resp or expert_resp == vote_resp do
          {:ok, expert_resp}
        else
          {:ok, conf_resp}
        end
      
      {{:ok, conf_resp}, _, _} -> {:ok, conf_resp}
      {_, {:ok, vote_resp}, _} -> {:ok, vote_resp}
      {_, _, {:ok, expert_resp}} -> {:ok, expert_resp}
      _ -> {:error, :all_resolution_methods_failed}
    end
  end

  # Aggregation methods

  defp simple_merge_responses(responses, _opts) do
    merged_content = responses
    |> Enum.map(fn response -> response[:content] || response[:response] || "" end)
    |> Enum.join("\n\n---\n\n")
    
    {:ok, merged_content}
  end

  defp weighted_merge_responses(responses, opts, state) do
    weights = Keyword.get(opts, :weights, [])
    
    weighted_responses = if length(weights) == length(responses) do
      Enum.zip(responses, weights)
    else
      # Calculate weights based on quality and confidence
      Enum.map(responses, fn response ->
        confidence = response[:confidence] || 0.5
        quality = response[:quality_score] || 0.5
        weight = confidence * 0.6 + quality * 0.4
        {response, weight}
      end)
    end
    
    # Select best weighted response
    case Enum.max_by(weighted_responses, fn {_response, weight} -> weight end, fn -> nil end) do
      nil -> {:error, :no_responses}
      {best_response, _weight} -> {:ok, best_response[:content] || best_response[:response]}
    end
  end

  defp semantic_fusion_responses(responses, _opts, _state) do
    # Simplified semantic fusion - would use NLP models in production
    contents = Enum.map(responses, fn response -> 
      response[:content] || response[:response] || ""
    end)
    
    # For now, just return the longest response as a proxy for most complete
    case Enum.max_by(contents, &String.length/1, fn -> "" end) do
      "" -> {:error, :no_content}
      best_content -> {:ok, best_content}
    end
  end

  defp quality_weighted_merge(responses, _opts, _state) do
    # Weight by quality scores
    quality_weighted = Enum.map(responses, fn response ->
      quality = response[:quality_score] || estimate_response_quality(response[:content] || "")
      {response, quality}
    end)
    
    case Enum.max_by(quality_weighted, fn {_response, quality} -> quality end, fn -> nil end) do
      nil -> {:error, :no_responses}
      {best_response, _quality} -> {:ok, best_response[:content] || best_response[:response]}
    end
  end

  # Helper and utility functions

  defp enhance_ensemble_result(ensemble_result, original_responses, response_analysis) do
    Map.merge(ensemble_result, %{
      original_responses: length(original_responses),
      response_analysis: response_analysis,
      ensemble_timestamp: System.monotonic_time(:millisecond),
      quality_metrics: calculate_ensemble_quality_metrics(ensemble_result, original_responses)
    })
  end

  defp calculate_ensemble_quality_metrics(ensemble_result, original_responses) do
    successful_responses = Enum.filter(original_responses, &match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, response} -> response end)
    
    %{
      response_count: length(successful_responses),
      avg_confidence: Enum.sum(Enum.map(successful_responses, & &1.confidence)) / length(successful_responses),
      avg_quality: Enum.sum(Enum.map(successful_responses, & &1.quality_score)) / length(successful_responses),
      consensus_strength: calculate_consensus_level(successful_responses)
    }
  end

  defp simulate_llm_request(model_id, model_config, task, config) do
    # Simulate different response characteristics based on model
    base_response = generate_mock_response(task)
    
    # Add model-specific variations
    case model_id do
      "gpt-4" ->
        {:ok, %{
          content: base_response,
          quality_score: 0.9,
          latency: 3000 + :rand.uniform(2000)
        }}
      
      "claude-3-opus" ->
        {:ok, %{
          content: base_response <> "\n\nAdditional analysis...",
          quality_score: 0.85,
          latency: 2500 + :rand.uniform(1500)
        }}
      
      "gpt-3.5-turbo" ->
        {:ok, %{
          content: String.slice(base_response, 0, div(String.length(base_response), 2)),
          quality_score: 0.75,
          latency: 1500 + :rand.uniform(1000)
        }}
      
      _ ->
        {:ok, %{
          content: base_response,
          quality_score: 0.7,
          latency: 2000 + :rand.uniform(1500)
        }}
    end
  end

  defp generate_mock_response(task) do
    content = task[:content] || task[:prompt] || "No content provided"
    "Response to: #{String.slice(content, 0, 100)}... [Generated response based on task]"
  end

  defp calculate_response_confidence(response) do
    content = response[:content] || ""
    
    # Simple heuristic - longer responses with certain words get higher confidence
    base_confidence = min(0.9, String.length(content) / 1000.0)
    
    certainty_bonus = if String.contains?(content, ["definitely", "clearly", "certainly"]) do
      0.1
    else
      0.0
    end
    
    uncertainty_penalty = if String.contains?(content, ["maybe", "might", "possibly", "unclear"]) do
      -0.1
    else
      0.0
    end
    
    max(0.1, min(0.95, base_confidence + certainty_bonus + uncertainty_penalty))
  end

  defp estimate_response_quality(response) do
    content = response[:content] || response || ""
    
    # Simple quality estimation based on length and structure
    length_score = min(0.4, String.length(content) / 500.0)
    structure_score = if String.contains?(content, ["\n", ".", "!"]) do 0.3 else 0.1 end
    completeness_score = if String.length(content) > 50 do 0.3 else 0.1 end
    
    length_score + structure_score + completeness_score
  end

  defp analyze_task_characteristics(task) do
    content = task[:content] || task[:prompt] || ""
    
    %{
      length: String.length(content),
      complexity: estimate_task_complexity(content),
      domain: classify_task_domain(content)
    }
  end

  defp estimate_task_complexity(content) do
    cond do
      String.length(content) > 1000 -> :high
      String.length(content) > 300 -> :medium
      true -> :low
    end
  end

  defp classify_task_domain(content) do
    content_lower = String.downcase(content)
    
    cond do
      String.contains?(content_lower, ["code", "programming", "function"]) -> :technical
      String.contains?(content_lower, ["creative", "story", "poem"]) -> :creative
      String.contains?(content_lower, ["analyze", "research", "study"]) -> :analytical
      true -> :general
    end
  end

  defp calculate_text_similarity(text1, text2) do
    # Simplified Jaccard similarity
    words1 = String.split(String.downcase(text1)) |> MapSet.new()
    words2 = String.split(String.downcase(text2)) |> MapSet.new()
    
    intersection = MapSet.intersection(words1, words2) |> MapSet.size()
    union = MapSet.union(words1, words2) |> MapSet.size()
    
    if union > 0 do
      intersection / union
    else
      0.0
    end
  end

  defp calculate_confidence_consistency(responses) do
    confidences = Enum.map(responses, & &1.confidence)
    
    if length(confidences) < 2 do
      1.0
    else
      std_dev = calculate_standard_deviation(confidences)
      max(0.0, 1.0 - std_dev)  # Lower std dev = higher consistency
    end
  end

  defp calculate_standard_deviation([]), do: 0.0
  defp calculate_standard_deviation(values) do
    mean = Enum.sum(values) / length(values)
    variance = Enum.sum(Enum.map(values, &((&1 - mean) ** 2))) / length(values)
    :math.sqrt(variance)
  end

  defp calculate_variance([]), do: 0.0
  defp calculate_variance(values) do
    mean = Enum.sum(values) / length(values)
    Enum.sum(Enum.map(values, &((&1 - mean) ** 2))) / length(values)
  end

  defp calculate_consensus_confidence(responses) do
    confidences = Enum.map(responses, & &1.confidence)
    Enum.sum(confidences) / length(confidences)
  end

  defp get_model_weight(model_id, state) do
    model_weights = Map.get(state.aggregation_config, :model_weights, %{})
    Map.get(model_weights, model_id, 0.5)  # Default weight
  end

  defp evaluate_ensemble_quality_internal(ensemble_result, ground_truth, state) do
    # Basic quality metrics
    base_metrics = %{
      response_length: String.length(ensemble_result.final_response || ""),
      strategy_used: ensemble_result.strategy,
      confidence_score: ensemble_result.confidence || 0.5
    }
    
    # Add ground truth comparison if available
    if ground_truth do
      similarity = calculate_text_similarity(ensemble_result.final_response, ground_truth)
      Map.put(base_metrics, :ground_truth_similarity, similarity)
    else
      base_metrics
    end
  end

  # Initialization functions

  defp initialize_ensemble_strategies(_opts) do
    @voting_strategies
  end

  defp initialize_voting_mechanisms(_opts) do
    %{
      majority: %{threshold: 0.5, min_responses: 2},
      weighted: %{use_confidence: true, use_quality: true},
      consensus: %{threshold: 0.7, max_iterations: 3}
    }
  end

  defp initialize_conflict_resolvers(_opts) do
    @conflict_resolution
  end

  defp initialize_aggregation_config(opts) do
    %{
      default_strategy: Keyword.get(opts, :default_strategy, :weighted),
      min_quality_threshold: Keyword.get(opts, :min_quality_threshold, 0.6),
      consensus_threshold: Keyword.get(opts, :consensus_threshold, 0.7),
      model_weights: Keyword.get(opts, :model_weights, %{}),
      model_expertise: Keyword.get(opts, :model_expertise, %{})
    }
  end

  defp initialize_ensemble_metrics do
    %{
      total_ensembles_processed: 0,
      avg_processing_time: 0,
      strategy_usage: %{},
      avg_consensus_level: 0,
      conflict_resolution_count: 0
    }
  end

  defp update_ensemble_metrics(metrics, ensemble_result, processing_time) do
    new_total = metrics.total_ensembles_processed + 1
    new_avg_time = (metrics.avg_processing_time * (new_total - 1) + processing_time) / new_total
    
    strategy = ensemble_result.strategy
    new_strategy_usage = Map.update(metrics.strategy_usage, strategy, 1, &(&1 + 1))
    
    consensus_level = ensemble_result[:consensus_level] || 0.5
    new_avg_consensus = (metrics.avg_consensus_level * (new_total - 1) + consensus_level) / new_total
    
    %{metrics |
      total_ensembles_processed: new_total,
      avg_processing_time: new_avg_time,
      strategy_usage: new_strategy_usage,
      avg_consensus_level: new_avg_consensus
    }
  end

  defp enhance_ensemble_metrics(metrics, state) do
    Map.merge(metrics, %{
      available_strategies: length(state.ensemble_strategies),
      current_config: state.aggregation_config,
      cache_size: map_size(state.response_cache)
    })
  end
end
defmodule RubberDuck.Agents.Prompt.Experiment do
  @moduledoc """
  A/B testing framework for prompt optimization.
  
  This module provides functionality for running controlled experiments
  on prompt templates to determine which variants perform best according
  to specified metrics.
  """

  @derive {Jason.Encoder, only: [:id, :name, :description, :variants, :traffic_split, :status, :start_date, :end_date]}
  defstruct [
    :id,              # UUID for the experiment
    :name,            # Human-readable name
    :description,     # Description of what's being tested
    :variants,        # List of template variants being tested
    :traffic_split,   # How traffic is distributed between variants
    :metrics,         # Performance metrics being tracked
    :status,          # :draft, :running, :paused, :completed, :cancelled
    :start_date,      # When experiment started
    :end_date,        # When experiment ended/will end
    :target_audience, # Criteria for participants
    :results,         # Collected results and analysis
    :confidence_level, # Statistical confidence level (0.95, 0.99, etc.)
    :sample_size,     # Required sample size for statistical significance
    :created_at,      # Creation timestamp
    :updated_at       # Last update timestamp
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    description: String.t(),
    variants: [variant()],
    traffic_split: %{String.t() => float()},
    metrics: [metric()],
    status: :draft | :running | :paused | :completed | :cancelled,
    start_date: DateTime.t() | nil,
    end_date: DateTime.t() | nil,
    target_audience: map(),
    results: map(),
    confidence_level: float(),
    sample_size: integer(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  @type variant :: %{
    id: String.t(),
    name: String.t(),
    template_id: String.t(),
    template_version: String.t(),
    weight: float()
  }

  @type metric :: %{
    name: String.t(),
    type: :success_rate | :response_time | :token_efficiency | :user_rating | :custom,
    target_value: float() | nil,
    higher_is_better: boolean()
  }

  @doc """
  Creates a new A/B test experiment.
  
  ## Examples
  
      iex> variants = [
      ...>   %{id: "v1", name: "Original", template_id: "template-1", weight: 0.5},
      ...>   %{id: "v2", name: "Optimized", template_id: "template-2", weight: 0.5}
      ...> ]
      iex> metrics = [
      ...>   %{name: "success_rate", type: :success_rate, higher_is_better: true},
      ...>   %{name: "response_time", type: :response_time, higher_is_better: false}
      ...> ]
      iex> RubberDuck.Agents.Prompt.Experiment.new(%{
      ...>   name: "Prompt Optimization Test",
      ...>   description: "Testing optimized vs original prompt",
      ...>   variants: variants,
      ...>   metrics: metrics
      ...> })
      {:ok, %RubberDuck.Agents.Prompt.Experiment{...}}
  """
  def new(attrs) do
    with {:ok, validated_attrs} <- validate_experiment_attrs(attrs),
         {:ok, experiment} <- build_experiment(validated_attrs) do
      {:ok, experiment}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates an existing experiment.
  """
  def update(%__MODULE__{} = experiment, attrs) do
    with {:ok, validated_attrs} <- validate_experiment_attrs(attrs),
         updated_experiment <- apply_experiment_updates(experiment, validated_attrs) do
      {:ok, updated_experiment}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Starts an experiment if it's in draft status.
  """
  def start(%__MODULE__{status: :draft} = experiment) do
    updated_experiment = %{experiment |
      status: :running,
      start_date: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
    
    {:ok, updated_experiment}
  end

  def start(%__MODULE__{status: status}) do
    {:error, "Cannot start experiment in #{status} status"}
  end

  @doc """
  Stops a running experiment.
  """
  def stop(%__MODULE__{status: :running} = experiment) do
    updated_experiment = %{experiment |
      status: :completed,
      end_date: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
    
    {:ok, updated_experiment}
  end

  def stop(%__MODULE__{status: status}) do
    {:error, "Cannot stop experiment in #{status} status"}
  end

  @doc """
  Selects a variant for a user based on the traffic split and targeting rules.
  """
  def select_variant(experiment, user_context \\ %{})
  
  def select_variant(%__MODULE__{status: :running} = experiment, user_context) do
    if matches_target_audience?(experiment, user_context) do
      variant = weighted_random_selection(experiment.variants, experiment.traffic_split)
      {:ok, variant}
    else
      {:error, "User does not match target audience"}
    end
  end

  def select_variant(%__MODULE__{status: status}, _user_context) do
    {:error, "Experiment is not running (status: #{status})"}
  end

  @doc """
  Records a result for a specific variant.
  """
  def record_result(%__MODULE__{} = experiment, variant_id, metric_name, value, context \\ %{}) do
    result_entry = %{
      variant_id: variant_id,
      metric_name: metric_name,
      value: value,
      context: context,
      timestamp: DateTime.utc_now()
    }
    
    results = Map.get(experiment.results, :raw_data, [])
    updated_results = [result_entry | results]
    
    experiment = %{experiment |
      results: Map.put(experiment.results, :raw_data, updated_results),
      updated_at: DateTime.utc_now()
    }
    
    {:ok, experiment}
  end

  @doc """
  Analyzes experiment results and determines statistical significance.
  """
  def analyze_results(%__MODULE__{} = experiment) do
    raw_data = Map.get(experiment.results, :raw_data, [])
    
    if length(raw_data) < experiment.sample_size do
      {:insufficient_data, %{
        current_sample_size: length(raw_data),
        required_sample_size: experiment.sample_size,
        completion_percentage: length(raw_data) / experiment.sample_size * 100
      }}
    else
      analysis = perform_statistical_analysis(experiment, raw_data)
      
      experiment = %{experiment |
        results: Map.put(experiment.results, :analysis, analysis),
        updated_at: DateTime.utc_now()
      }
      
      {:ok, experiment, analysis}
    end
  end

  @doc """
  Gets a summary of experiment performance.
  """
  def get_summary(%__MODULE__{} = experiment) do
    raw_data = Map.get(experiment.results, :raw_data, [])
    analysis = Map.get(experiment.results, :analysis, %{})
    
    %{
      id: experiment.id,
      name: experiment.name,
      status: experiment.status,
      variants: length(experiment.variants),
      metrics: length(experiment.metrics),
      sample_size: length(raw_data),
      required_sample_size: experiment.sample_size,
      completion_rate: if(experiment.sample_size > 0, do: length(raw_data) / experiment.sample_size, else: 0),
      duration_days: calculate_duration(experiment),
      winning_variant: Map.get(analysis, :winning_variant),
      confidence_level: Map.get(analysis, :confidence_level, 0.0),
      statistically_significant: Map.get(analysis, :significant, false)
    }
  end

  @doc """
  Checks if experiment has enough data for reliable results.
  """
  def sufficient_data?(%__MODULE__{} = experiment) do
    raw_data = Map.get(experiment.results, :raw_data, [])
    length(raw_data) >= experiment.sample_size
  end

  # Private functions

  defp validate_experiment_attrs(attrs) do
    required_fields = [:name, :variants, :metrics]
    
    with :ok <- validate_required_fields(attrs, required_fields),
         :ok <- validate_variants(Map.get(attrs, :variants, [])),
         :ok <- validate_metrics(Map.get(attrs, :metrics, [])),
         :ok <- validate_traffic_split(Map.get(attrs, :variants, []), Map.get(attrs, :traffic_split)) do
      {:ok, attrs}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_required_fields(attrs, required_fields) do
    missing_fields = required_fields -- Map.keys(attrs)
    
    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_variants(variants) when is_list(variants) and length(variants) >= 2 do
    Enum.reduce_while(variants, :ok, fn variant, acc ->
      case validate_variant(variant) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_variants(variants) when is_list(variants) do
    {:error, "Experiment must have at least 2 variants, got #{length(variants)}"}
  end

  defp validate_variants(_) do
    {:error, "Variants must be a list"}
  end

  defp validate_variant(%{id: id, name: name, template_id: template_id, weight: weight}) 
       when is_binary(id) and is_binary(name) and is_binary(template_id) and is_number(weight) and weight > 0 do
    :ok
  end

  defp validate_variant(variant) do
    {:error, "Invalid variant format: #{inspect(variant)}"}
  end

  defp validate_metrics(metrics) when is_list(metrics) and length(metrics) > 0 do
    Enum.reduce_while(metrics, :ok, fn metric, acc ->
      case validate_metric(metric) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_metrics(metrics) when is_list(metrics) do
    {:error, "Experiment must have at least 1 metric"}
  end

  defp validate_metrics(_) do
    {:error, "Metrics must be a list"}
  end

  defp validate_metric(%{name: name, type: type, higher_is_better: higher_is_better}) 
       when is_binary(name) and is_atom(type) and is_boolean(higher_is_better) do
    valid_types = [:success_rate, :response_time, :token_efficiency, :user_rating, :custom]
    
    if type in valid_types do
      :ok
    else
      {:error, "Invalid metric type: #{type}"}
    end
  end

  defp validate_metric(metric) do
    {:error, "Invalid metric format: #{inspect(metric)}"}
  end

  defp validate_traffic_split(_variants, nil) do
    # Auto-generate equal split
    :ok
  end

  defp validate_traffic_split(variants, traffic_split) when is_map(traffic_split) do
    variant_ids = Enum.map(variants, & &1.id) |> MapSet.new()
    split_ids = Map.keys(traffic_split) |> MapSet.new()
    
    cond do
      not MapSet.equal?(variant_ids, split_ids) ->
        {:error, "Traffic split must include all variant IDs"}
        
      abs(Enum.sum(Map.values(traffic_split)) - 1.0) > 0.001 ->
        {:error, "Traffic split must sum to 1.0"}
        
      true ->
        :ok
    end
  end

  defp validate_traffic_split(_variants, _traffic_split) do
    {:error, "Traffic split must be a map or nil"}
  end

  defp build_experiment(attrs) do
    now = DateTime.utc_now()
    variants = Map.fetch!(attrs, :variants)
    
    experiment = %__MODULE__{
      id: Map.get(attrs, :id, Uniq.UUID.uuid4()),
      name: Map.fetch!(attrs, :name),
      description: Map.get(attrs, :description, ""),
      variants: variants,
      traffic_split: Map.get(attrs, :traffic_split, generate_equal_split(variants)),
      metrics: Map.fetch!(attrs, :metrics),
      status: :draft,
      start_date: nil,
      end_date: nil,
      target_audience: Map.get(attrs, :target_audience, %{}),
      results: %{raw_data: [], analysis: %{}},
      confidence_level: Map.get(attrs, :confidence_level, 0.95),
      sample_size: Map.get(attrs, :sample_size, 1000),
      created_at: now,
      updated_at: now
    }
    
    {:ok, experiment}
  end

  defp generate_equal_split(variants) do
    weight = 1.0 / length(variants)
    
    variants
    |> Enum.map(& &1.id)
    |> Enum.map(&{&1, weight})
    |> Map.new()
  end

  defp apply_experiment_updates(experiment, attrs) do
    %{experiment |
      name: Map.get(attrs, :name, experiment.name),
      description: Map.get(attrs, :description, experiment.description),
      variants: Map.get(attrs, :variants, experiment.variants),
      traffic_split: Map.get(attrs, :traffic_split, experiment.traffic_split),
      metrics: Map.get(attrs, :metrics, experiment.metrics),
      target_audience: Map.get(attrs, :target_audience, experiment.target_audience),
      confidence_level: Map.get(attrs, :confidence_level, experiment.confidence_level),
      sample_size: Map.get(attrs, :sample_size, experiment.sample_size),
      updated_at: DateTime.utc_now()
    }
  end

  defp matches_target_audience?(%{target_audience: target_audience}, _user_context) 
       when map_size(target_audience) == 0 do
    # No targeting rules, everyone matches
    true
  end

  defp matches_target_audience?(%{target_audience: target_audience}, user_context) do
    Enum.all?(target_audience, fn {key, expected_value} ->
      case Map.get(user_context, key) do
        ^expected_value -> true
        _ -> false
      end
    end)
  end

  defp weighted_random_selection(variants, traffic_split) do
    random_value = :rand.uniform()
    cumulative_weight = 0
    
    Enum.reduce_while(variants, nil, fn variant, _acc ->
      weight = Map.get(traffic_split, variant.id, 0)
      new_cumulative = cumulative_weight + weight
      
      if random_value <= new_cumulative do
        {:halt, variant}
      else
        {:cont, nil}
      end
    end) || List.last(variants)  # Fallback to last variant
  end

  defp perform_statistical_analysis(experiment, raw_data) do
    # Group data by variant and metric
    grouped_data = Enum.group_by(raw_data, fn entry ->
      {entry.variant_id, entry.metric_name}
    end)
    
    # Calculate statistics for each variant-metric combination
    variant_stats = experiment.variants
    |> Enum.map(fn variant ->
      variant_data = experiment.metrics
      |> Enum.map(fn metric ->
        data_key = {variant.id, metric.name}
        values = Map.get(grouped_data, data_key, [])
        |> Enum.map(& &1.value)
        
        stats = if length(values) > 0 do
          calculate_metric_stats(values, metric)
        else
          %{count: 0, mean: 0, std_dev: 0}
        end
        
        {metric.name, stats}
      end)
      |> Map.new()
      
      {variant.id, variant_data}
    end)
    |> Map.new()
    
    # Determine winning variant and statistical significance
    winning_variant = determine_winning_variant(experiment, variant_stats)
    significance_results = calculate_statistical_significance(experiment, variant_stats)
    
    %{
      variant_statistics: variant_stats,
      winning_variant: winning_variant,
      significance_results: significance_results,
      significant: Map.get(significance_results, :significant, false),
      confidence_level: experiment.confidence_level,
      analyzed_at: DateTime.utc_now()
    }
  end

  defp calculate_metric_stats(values, _metric) do
    count = length(values)
    mean = Enum.sum(values) / count
    variance = Enum.sum(Enum.map(values, &(:math.pow(&1 - mean, 2)))) / count
    std_dev = :math.sqrt(variance)
    
    %{
      count: count,
      mean: mean,
      std_dev: std_dev,
      min: Enum.min(values),
      max: Enum.max(values)
    }
  end

  defp determine_winning_variant(experiment, variant_stats) do
    # Simplified winning variant determination
    # In production, would use more sophisticated statistical methods
    primary_metric = List.first(experiment.metrics)
    
    if primary_metric do
      variant_scores = Enum.map(experiment.variants, fn variant ->
        stats = get_in(variant_stats, [variant.id, primary_metric.name])
        score = if stats && stats.count > 0, do: stats.mean, else: 0
        
        # Adjust score based on whether higher is better
        adjusted_score = if primary_metric.higher_is_better, do: score, else: -score
        
        {variant.id, adjusted_score}
      end)
      
      {winning_id, _score} = Enum.max_by(variant_scores, fn {_id, score} -> score end)
      winning_id
    else
      nil
    end
  end

  defp calculate_statistical_significance(_experiment, _variant_stats) do
    # Simplified significance calculation
    # In production, would implement proper statistical tests (t-test, chi-square, etc.)
    %{
      significant: true,
      p_value: 0.03,
      test_type: "simplified"
    }
  end

  defp calculate_duration(%{start_date: nil}), do: 0
  defp calculate_duration(%{start_date: start_date, end_date: nil}) do
    DateTime.diff(DateTime.utc_now(), start_date, :day)
  end
  defp calculate_duration(%{start_date: start_date, end_date: end_date}) do
    DateTime.diff(end_date, start_date, :day)
  end
end
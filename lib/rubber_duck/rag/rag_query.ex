defmodule RubberDuck.RAG.RAGQuery do
  @moduledoc """
  Data structure representing a RAG (Retrieval-Augmented Generation) query.
  
  Encapsulates all configuration and parameters needed to execute a complete
  RAG pipeline, including retrieval settings, augmentation rules, and
  generation parameters.
  """

  defstruct [
    :id,
    :query,
    :retrieval_config,
    :augmentation_config,
    :generation_config,
    :metadata,
    :created_at,
    :user_id,
    :session_id,
    :priority
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    query: String.t(),
    retrieval_config: retrieval_config(),
    augmentation_config: augmentation_config(),
    generation_config: generation_config(),
    metadata: map(),
    created_at: DateTime.t(),
    user_id: String.t() | nil,
    session_id: String.t() | nil,
    priority: priority_level()
  }

  @type retrieval_config :: %{
    strategy: retrieval_strategy(),
    max_documents: integer(),
    min_relevance_score: float(),
    vector_weight: float(),
    keyword_weight: float(),
    rerank_enabled: boolean(),
    filters: map()
  }

  @type augmentation_config :: %{
    dedup_enabled: boolean(),
    dedup_threshold: float(),
    summarization_enabled: boolean(),
    max_summary_ratio: float(),
    format_standardization: boolean(),
    validation_enabled: boolean()
  }

  @type generation_config :: %{
    template: String.t(),
    max_tokens: integer(),
    temperature: float(),
    streaming: boolean(),
    fallback_strategy: String.t(),
    quality_check: boolean()
  }

  @type retrieval_strategy :: :vector_only | :keyword_only | :hybrid | :ensemble
  @type priority_level :: :low | :normal | :high | :critical

  @doc """
  Creates a new RAG query with validation.
  """
  def new(attrs) do
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      query: validate_query(attrs[:query]),
      retrieval_config: build_retrieval_config(attrs[:retrieval_config]),
      augmentation_config: build_augmentation_config(attrs[:augmentation_config]),
      generation_config: build_generation_config(attrs[:generation_config]),
      metadata: attrs[:metadata] || %{},
      created_at: DateTime.utc_now(),
      user_id: attrs[:user_id],
      session_id: attrs[:session_id],
      priority: validate_priority(attrs[:priority])
    }
  end

  @doc """
  Updates query configuration.
  """
  def update_config(query, config_type, updates) do
    case config_type do
      :retrieval ->
        %{query | retrieval_config: Map.merge(query.retrieval_config, updates)}
        
      :augmentation ->
        %{query | augmentation_config: Map.merge(query.augmentation_config, updates)}
        
      :generation ->
        %{query | generation_config: Map.merge(query.generation_config, updates)}
        
      _ ->
        query
    end
  end

  @doc """
  Validates if the query is properly configured.
  """
  def valid?(query) do
    query.query != nil and
    String.length(query.query) > 0 and
    valid_retrieval_config?(query.retrieval_config) and
    valid_augmentation_config?(query.augmentation_config) and
    valid_generation_config?(query.generation_config)
  end

  @doc """
  Returns a hash of the query for caching.
  """
  def cache_key(query) do
    key_parts = [
      query.query,
      inspect(query.retrieval_config),
      inspect(query.augmentation_config)
    ]
    
    :crypto.hash(:sha256, Enum.join(key_parts, "_"))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Estimates the complexity of the query.
  """
  def complexity_score(query) do
    query_complexity = String.split(query.query) |> length() |> min(10)
    doc_complexity = query.retrieval_config.max_documents / 10
    
    strategy_complexity = case query.retrieval_config.strategy do
      :vector_only -> 1.0
      :keyword_only -> 1.0
      :hybrid -> 1.5
      :ensemble -> 2.0
    end
    
    (query_complexity + doc_complexity + strategy_complexity) / 3
  end

  @doc """
  Converts query to execution parameters.
  """
  def to_execution_params(query) do
    %{
      query_text: query.query,
      retrieval: query.retrieval_config,
      augmentation: query.augmentation_config,
      generation: query.generation_config,
      metadata: Map.merge(query.metadata, %{
        "query_id" => query.id,
        "created_at" => query.created_at,
        "priority" => query.priority
      })
    }
  end

  # Private functions

  defp generate_id do
    "rag_" <> :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  defp validate_query(nil), do: raise ArgumentError, "Query text is required"
  defp validate_query(query) when is_binary(query) and byte_size(query) > 0, do: query
  defp validate_query(_), do: raise ArgumentError, "Query must be a non-empty string"

  defp validate_priority(nil), do: :normal
  defp validate_priority(priority) when priority in [:low, :normal, :high, :critical], do: priority
  defp validate_priority(priority) when is_binary(priority) do
    String.to_atom(priority)
  end
  defp validate_priority(_), do: :normal

  defp build_retrieval_config(nil), do: default_retrieval_config()
  defp build_retrieval_config(config) when is_map(config) do
    Map.merge(default_retrieval_config(), config)
    |> validate_retrieval_config!()
  end

  defp build_augmentation_config(nil), do: default_augmentation_config()
  defp build_augmentation_config(config) when is_map(config) do
    Map.merge(default_augmentation_config(), config)
    |> validate_augmentation_config!()
  end

  defp build_generation_config(nil), do: default_generation_config()
  defp build_generation_config(config) when is_map(config) do
    Map.merge(default_generation_config(), config)
    |> validate_generation_config!()
  end

  defp default_retrieval_config do
    %{
      strategy: :hybrid,
      max_documents: 10,
      min_relevance_score: 0.5,
      vector_weight: 0.7,
      keyword_weight: 0.3,
      rerank_enabled: true,
      filters: %{}
    }
  end

  defp default_augmentation_config do
    %{
      dedup_enabled: true,
      dedup_threshold: 0.85,
      summarization_enabled: true,
      max_summary_ratio: 0.3,
      format_standardization: true,
      validation_enabled: true
    }
  end

  defp default_generation_config do
    %{
      template: "default",
      max_tokens: 2000,
      temperature: 0.7,
      streaming: false,
      fallback_strategy: "summarize_context",
      quality_check: true
    }
  end

  defp validate_retrieval_config!(config) do
    unless config.strategy in [:vector_only, :keyword_only, :hybrid, :ensemble] do
      raise ArgumentError, "Invalid retrieval strategy: #{config.strategy}"
    end
    
    unless config.max_documents > 0 and config.max_documents <= 100 do
      raise ArgumentError, "max_documents must be between 1 and 100"
    end
    
    unless config.min_relevance_score >= 0 and config.min_relevance_score <= 1 do
      raise ArgumentError, "min_relevance_score must be between 0 and 1"
    end
    
    config
  end

  defp validate_augmentation_config!(config) do
    unless config.dedup_threshold >= 0 and config.dedup_threshold <= 1 do
      raise ArgumentError, "dedup_threshold must be between 0 and 1"
    end
    
    unless config.max_summary_ratio > 0 and config.max_summary_ratio <= 1 do
      raise ArgumentError, "max_summary_ratio must be between 0 and 1"
    end
    
    config
  end

  defp validate_generation_config!(config) do
    unless config.max_tokens > 0 and config.max_tokens <= 10000 do
      raise ArgumentError, "max_tokens must be between 1 and 10000"
    end
    
    unless config.temperature >= 0 and config.temperature <= 2 do
      raise ArgumentError, "temperature must be between 0 and 2"
    end
    
    config
  end

  defp valid_retrieval_config?(config) do
    config.strategy in [:vector_only, :keyword_only, :hybrid, :ensemble] and
    config.max_documents > 0 and
    config.min_relevance_score >= 0 and config.min_relevance_score <= 1
  end

  defp valid_augmentation_config?(config) do
    config.dedup_threshold >= 0 and config.dedup_threshold <= 1 and
    config.max_summary_ratio > 0 and config.max_summary_ratio <= 1
  end

  defp valid_generation_config?(config) do
    config.max_tokens > 0 and
    config.temperature >= 0 and config.temperature <= 2
  end
end
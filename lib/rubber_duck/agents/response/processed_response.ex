defmodule RubberDuck.Agents.Response.ProcessedResponse do
  @moduledoc """
  Data structure representing a processed LLM response.
  
  This structure contains the original response along with all processing
  metadata, parsed content, quality scores, and enhancement information.
  """

  @derive {Jason.Encoder, only: [:id, :format, :quality_score, :metadata, :processing_time, :provider, :model]}
  defstruct [
    :id,                    # UUID for the processed response
    :original_response,     # Original response from LLM provider
    :parsed_content,        # Parsed and structured content
    :format,               # Detected format (:json, :markdown, :xml, :text, etc.)
    :quality_score,        # Overall quality score (0.0 - 1.0)
    :metadata,             # Additional metadata and processing info
    :enhanced_content,     # Content after enhancement pipeline
    :processing_time,      # Time taken to process (in milliseconds)
    :cache_key,           # Key used for caching this response
    :validation_results,   # Results from validation checks
    :created_at,          # Processing timestamp
    :provider,            # LLM provider used (:openai, :anthropic, :local)
    :model,               # Specific model used
    :request_id,          # Original request ID for tracing
    :enhancement_log,     # Log of applied enhancements
    :error_log            # Any errors encountered during processing
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    original_response: String.t(),
    parsed_content: term(),
    format: format_type(),
    quality_score: float(),
    metadata: map(),
    enhanced_content: String.t(),
    processing_time: integer(),
    cache_key: String.t(),
    validation_results: validation_results(),
    created_at: DateTime.t(),
    provider: atom(),
    model: String.t(),
    request_id: String.t(),
    enhancement_log: [enhancement_entry()],
    error_log: [error_entry()]
  }

  @type format_type :: 
    :json | :xml | :markdown | :html | :yaml | :code | :text | :unknown

  @type validation_results :: %{
    is_valid: boolean(),
    completeness_score: float(),
    readability_score: float(),
    safety_score: float(),
    issues: [String.t()]
  }

  @type enhancement_entry :: %{
    type: atom(),
    applied_at: DateTime.t(),
    before_quality: float(),
    after_quality: float(),
    metadata: map()
  }

  @type error_entry :: %{
    type: atom(),
    message: String.t(),
    occurred_at: DateTime.t(),
    context: map()
  }

  @doc """
  Creates a new ProcessedResponse from an original response.
  
  ## Examples
  
      iex> response = "Hello, world!"
      iex> RubberDuck.Agents.Response.ProcessedResponse.new(response, "req-123", :openai, "gpt-4")
      %RubberDuck.Agents.Response.ProcessedResponse{
        original_response: "Hello, world!",
        request_id: "req-123",
        provider: :openai,
        model: "gpt-4"
      }
  """
  def new(original_response, request_id, provider, model) when is_binary(original_response) do
    now = DateTime.utc_now()
    
    %__MODULE__{
      id: generate_id(),
      original_response: original_response,
      parsed_content: nil,
      format: :unknown,
      quality_score: 0.0,
      metadata: %{},
      enhanced_content: original_response,
      processing_time: 0,
      cache_key: generate_cache_key(original_response, %{}),
      validation_results: %{
        is_valid: false,
        completeness_score: 0.0,
        readability_score: 0.0,
        safety_score: 0.0,
        issues: []
      },
      created_at: now,
      provider: provider,
      model: model,
      request_id: request_id,
      enhancement_log: [],
      error_log: []
    }
  end

  @doc """
  Updates the processed response with parsed content and format.
  """
  def set_parsed_content(%__MODULE__{} = response, parsed_content, format) do
    %{response |
      parsed_content: parsed_content,
      format: format,
      metadata: Map.put(response.metadata, :parsing_completed_at, DateTime.utc_now())
    }
  end

  @doc """
  Updates the quality score and validation results.
  """
  def set_quality_score(%__MODULE__{} = response, quality_score, validation_results) do
    %{response |
      quality_score: quality_score,
      validation_results: validation_results,
      metadata: Map.put(response.metadata, :validation_completed_at, DateTime.utc_now())
    }
  end

  @doc """
  Updates the enhanced content after applying enhancement pipeline.
  """
  def set_enhanced_content(%__MODULE__{} = response, enhanced_content) do
    %{response |
      enhanced_content: enhanced_content,
      metadata: Map.put(response.metadata, :enhancement_completed_at, DateTime.utc_now())
    }
  end

  @doc """
  Sets the final processing time.
  """
  def set_processing_time(%__MODULE__{} = response, processing_time) do
    %{response | processing_time: processing_time}
  end

  @doc """
  Adds an enhancement log entry.
  """
  def add_enhancement_log(%__MODULE__{} = response, enhancement_type, before_quality, after_quality, metadata \\ %{}) do
    entry = %{
      type: enhancement_type,
      applied_at: DateTime.utc_now(),
      before_quality: before_quality,
      after_quality: after_quality,
      metadata: metadata
    }
    
    %{response | enhancement_log: [entry | response.enhancement_log]}
  end

  @doc """
  Adds an error log entry.
  """
  def add_error_log(%__MODULE__{} = response, error_type, message, context \\ %{}) do
    entry = %{
      type: error_type,
      message: message,
      occurred_at: DateTime.utc_now(),
      context: context
    }
    
    %{response | error_log: [entry | response.error_log]}
  end

  @doc """
  Checks if the response processing was successful.
  """
  def successful?(%__MODULE__{validation_results: %{is_valid: is_valid}, quality_score: score}) do
    is_valid and score > 0.5
  end

  @doc """
  Gets a summary of the processed response for logging/debugging.
  """
  def get_summary(%__MODULE__{} = response) do
    %{
      id: response.id,
      request_id: response.request_id,
      format: response.format,
      quality_score: response.quality_score,
      processing_time: response.processing_time,
      provider: response.provider,
      model: response.model,
      enhancements_applied: length(response.enhancement_log),
      errors_encountered: length(response.error_log),
      is_successful: successful?(response),
      original_length: String.length(response.original_response),
      enhanced_length: String.length(response.enhanced_content || "")
    }
  end

  @doc """
  Calculates content improvement metrics.
  """
  def calculate_improvement(%__MODULE__{} = response) do
    original_length = String.length(response.original_response)
    enhanced_length = String.length(response.enhanced_content || response.original_response)
    
    %{
      length_change_percent: if(original_length > 0, do: (enhanced_length - original_length) / original_length * 100, else: 0),
      quality_improvement: response.quality_score - 0.5, # Assuming baseline quality of 0.5
      enhancements_count: length(response.enhancement_log),
      processing_efficiency: if(response.processing_time > 0, do: enhanced_length / response.processing_time, else: 0)
    }
  end

  @doc """
  Determines if the response should be cached based on quality and other factors.
  """
  def cacheable?(%__MODULE__{} = response) do
    response.quality_score >= 0.7 and 
    successful?(response) and
    length(response.error_log) == 0 and
    String.length(response.enhanced_content || "") > 10
  end

  @doc """
  Gets the final content to return to the user.
  """
  def get_final_content(%__MODULE__{enhanced_content: nil, original_response: original}), do: original
  def get_final_content(%__MODULE__{enhanced_content: enhanced}) when is_binary(enhanced), do: enhanced
  def get_final_content(%__MODULE__{original_response: original}), do: original

  @doc """
  Converts the processed response to a client-friendly format.
  """
  def to_client_response(%__MODULE__{} = response) do
    %{
      id: response.id,
      content: get_final_content(response),
      format: response.format,
      quality_score: response.quality_score,
      provider: response.provider,
      model: response.model,
      processing_time: response.processing_time,
      metadata: %{
        request_id: response.request_id,
        created_at: response.created_at,
        enhancements_applied: length(response.enhancement_log),
        cache_key: response.cache_key
      }
    }
  end

  # Private helper functions

  defp generate_id do
    # Use a simple timestamp-based ID since UUID might not be available
    timestamp = System.monotonic_time(:nanosecond)
    random = :rand.uniform(1000000)
    "resp_#{timestamp}_#{random}"
  end

  defp generate_cache_key(content, options) do
    # Create a simple hash-based cache key
    data = %{content: content, options: options}
    :crypto.hash(:md5, :erlang.term_to_binary(data))
    |> Base.encode16(case: :lower)
  end
end
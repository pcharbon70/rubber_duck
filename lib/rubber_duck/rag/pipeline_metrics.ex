defmodule RubberDuck.RAG.PipelineMetrics do
  @moduledoc """
  Metrics tracking and analysis for RAG pipeline performance.
  
  Provides comprehensive metrics collection, analysis, and optimization
  recommendations for the RAG pipeline.
  """

  defstruct [
    :pipeline_id,
    :start_time,
    :end_time,
    :stages,
    :documents_retrieved,
    :documents_used,
    :total_tokens,
    :relevance_scores,
    :errors,
    :metadata
  ]

  @type t :: %__MODULE__{
    pipeline_id: String.t(),
    start_time: DateTime.t(),
    end_time: DateTime.t() | nil,
    stages: map(),
    documents_retrieved: integer(),
    documents_used: integer(),
    total_tokens: integer(),
    relevance_scores: list(float()),
    errors: list(map()),
    metadata: map()
  }

  @doc """
  Starts tracking metrics for a new pipeline execution.
  """
  def start_tracking(pipeline_id) do
    %__MODULE__{
      pipeline_id: pipeline_id,
      start_time: DateTime.utc_now(),
      end_time: nil,
      stages: %{},
      documents_retrieved: 0,
      documents_used: 0,
      total_tokens: 0,
      relevance_scores: [],
      errors: [],
      metadata: %{}
    }
  end

  @doc """
  Records the start of a pipeline stage.
  """
  def start_stage(metrics, stage_name) do
    put_in(metrics.stages[stage_name], %{
      start_time: System.monotonic_time(:millisecond),
      end_time: nil,
      success: nil,
      metadata: %{}
    })
  end

  @doc """
  Records the completion of a pipeline stage.
  """
  def complete_stage(metrics, stage_name, success \\ true, metadata \\ %{}) do
    stage = metrics.stages[stage_name]
    
    if stage do
      updated_stage = %{stage |
        end_time: System.monotonic_time(:millisecond),
        success: success,
        metadata: metadata,
        duration_ms: System.monotonic_time(:millisecond) - stage.start_time
      }
      
      put_in(metrics.stages[stage_name], updated_stage)
    else
      metrics
    end
  end

  @doc """
  Records retrieval metrics.
  """
  def record_retrieval(metrics, documents) do
    relevance_scores = Enum.map(documents, & &1.relevance_score)
    
    %{metrics |
      documents_retrieved: length(documents),
      relevance_scores: relevance_scores
    }
  end

  @doc """
  Records augmentation metrics.
  """
  def record_augmentation(metrics, augmented_context) do
    %{metrics |
      documents_used: length(augmented_context.documents),
      total_tokens: augmented_context.total_tokens
    }
  end

  @doc """
  Records an error during pipeline execution.
  """
  def record_error(metrics, stage, error_type, message) do
    error = %{
      stage: stage,
      type: error_type,
      message: message,
      timestamp: DateTime.utc_now()
    }
    
    %{metrics | errors: [error | metrics.errors]}
  end

  @doc """
  Completes metric tracking for the pipeline.
  """
  def complete_tracking(metrics) do
    %{metrics | end_time: DateTime.utc_now()}
  end

  @doc """
  Calculates summary statistics for the pipeline execution.
  """
  def calculate_summary(metrics) do
    total_duration = if metrics.end_time do
      DateTime.diff(metrics.end_time, metrics.start_time, :millisecond)
    else
      nil
    end
    
    stage_durations = metrics.stages
    |> Enum.map(fn {name, stage} -> {name, stage[:duration_ms] || 0} end)
    |> Map.new()
    
    %{
      pipeline_id: metrics.pipeline_id,
      total_duration_ms: total_duration,
      stage_durations: stage_durations,
      documents_retrieved: metrics.documents_retrieved,
      documents_used: metrics.documents_used,
      document_reduction_rate: calculate_reduction_rate(metrics),
      avg_relevance_score: calculate_avg_relevance(metrics),
      total_tokens: metrics.total_tokens,
      success: length(metrics.errors) == 0,
      error_count: length(metrics.errors)
    }
  end

  @doc """
  Analyzes metrics to provide optimization recommendations.
  """
  def analyze_for_optimization(metrics_list) when is_list(metrics_list) do
    # Aggregate metrics
    aggregated = aggregate_metrics(metrics_list)
    
    recommendations = []
    
    # Check retrieval performance
    recommendations = if aggregated.avg_retrieval_time > 500 do
      ["Consider enabling retrieval caching" | recommendations]
    else
      recommendations
    end
    
    # Check document usage efficiency
    recommendations = if aggregated.document_usage_rate < 0.5 do
      ["Increase retrieval relevance threshold to reduce unused documents" | recommendations]
    else
      recommendations
    end
    
    # Check relevance scores
    recommendations = if aggregated.avg_relevance_score < 0.6 do
      ["Consider using ensemble retrieval strategy for better relevance" | recommendations]
    else
      recommendations
    end
    
    # Check token efficiency
    recommendations = if aggregated.avg_tokens_per_doc > 500 do
      ["Enable document summarization to reduce token usage" | recommendations]
    else
      recommendations
    end
    
    %{
      metrics_analyzed: length(metrics_list),
      aggregated_stats: aggregated,
      recommendations: recommendations,
      optimization_potential: calculate_optimization_potential(aggregated)
    }
  end

  @doc """
  Tracks A/B test metrics.
  """
  def track_ab_test(variant, metrics) do
    %{
      variant: variant,
      pipeline_id: metrics.pipeline_id,
      duration_ms: calculate_duration(metrics),
      relevance_score: calculate_avg_relevance(metrics),
      token_efficiency: calculate_token_efficiency(metrics),
      success: length(metrics.errors) == 0
    }
  end

  # Private functions

  defp calculate_reduction_rate(metrics) do
    if metrics.documents_retrieved > 0 do
      1.0 - (metrics.documents_used / metrics.documents_retrieved)
    else
      0.0
    end
  end

  defp calculate_avg_relevance(metrics) do
    if length(metrics.relevance_scores) > 0 do
      Enum.sum(metrics.relevance_scores) / length(metrics.relevance_scores)
    else
      0.0
    end
  end

  defp calculate_duration(metrics) do
    if metrics.end_time do
      DateTime.diff(metrics.end_time, metrics.start_time, :millisecond)
    else
      0
    end
  end

  defp calculate_token_efficiency(metrics) do
    if metrics.documents_used > 0 do
      metrics.total_tokens / metrics.documents_used
    else
      0.0
    end
  end

  defp aggregate_metrics(metrics_list) do
    count = length(metrics_list)
    
    if count == 0 do
      %{
        avg_retrieval_time: 0,
        avg_augmentation_time: 0,
        avg_generation_time: 0,
        document_usage_rate: 0,
        avg_relevance_score: 0,
        avg_tokens_per_doc: 0,
        error_rate: 0
      }
    else
      total_stats = Enum.reduce(metrics_list, initial_aggregate(), fn metrics, acc ->
        %{acc |
          retrieval_time: acc.retrieval_time + get_stage_duration(metrics, :retrieval),
          augmentation_time: acc.augmentation_time + get_stage_duration(metrics, :augmentation),
          generation_time: acc.generation_time + get_stage_duration(metrics, :generation),
          documents_retrieved: acc.documents_retrieved + metrics.documents_retrieved,
          documents_used: acc.documents_used + metrics.documents_used,
          relevance_sum: acc.relevance_sum + Enum.sum(metrics.relevance_scores),
          relevance_count: acc.relevance_count + length(metrics.relevance_scores),
          total_tokens: acc.total_tokens + metrics.total_tokens,
          error_count: acc.error_count + length(metrics.errors)
        }
      end)
      
      %{
        avg_retrieval_time: total_stats.retrieval_time / count,
        avg_augmentation_time: total_stats.augmentation_time / count,
        avg_generation_time: total_stats.generation_time / count,
        document_usage_rate: if(total_stats.documents_retrieved > 0, 
          do: total_stats.documents_used / total_stats.documents_retrieved, 
          else: 0),
        avg_relevance_score: if(total_stats.relevance_count > 0,
          do: total_stats.relevance_sum / total_stats.relevance_count,
          else: 0),
        avg_tokens_per_doc: if(total_stats.documents_used > 0,
          do: total_stats.total_tokens / total_stats.documents_used,
          else: 0),
        error_rate: total_stats.error_count / count
      }
    end
  end

  defp initial_aggregate do
    %{
      retrieval_time: 0,
      augmentation_time: 0,
      generation_time: 0,
      documents_retrieved: 0,
      documents_used: 0,
      relevance_sum: 0.0,
      relevance_count: 0,
      total_tokens: 0,
      error_count: 0
    }
  end

  defp get_stage_duration(metrics, stage_name) do
    case metrics.stages[stage_name] do
      %{duration_ms: duration} -> duration
      _ -> 0
    end
  end

  defp calculate_optimization_potential(aggregated) do
    scores = [
      # Time optimization potential
      if(aggregated.avg_retrieval_time > 300, do: 0.3, else: 0.0),
      
      # Document efficiency potential
      if(aggregated.document_usage_rate < 0.7, do: 0.2, else: 0.0),
      
      # Relevance improvement potential
      if(aggregated.avg_relevance_score < 0.8, do: 0.3, else: 0.0),
      
      # Token optimization potential
      if(aggregated.avg_tokens_per_doc > 400, do: 0.2, else: 0.0)
    ]
    
    Enum.sum(scores)
  end
end
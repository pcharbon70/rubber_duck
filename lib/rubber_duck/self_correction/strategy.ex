defmodule RubberDuck.SelfCorrection.Strategy do
  @moduledoc """
  Behavior for implementing self-correction strategies.
  
  Each strategy focuses on a specific aspect of correction
  (e.g., syntax, semantics, logic) and provides analysis
  and correction suggestions.
  """
  
  @type content_type :: :code | :text | :mixed
  
  @type analysis_result :: %{
    strategy: atom(),
    issues: [issue()],
    corrections: [correction()],
    confidence: float(),
    metadata: map()
  }
  
  @type issue :: %{
    type: atom(),
    severity: :error | :warning | :info,
    description: String.t(),
    location: map(),
    context: map()
  }
  
  @type correction :: %{
    type: atom(),
    description: String.t(),
    changes: [change()],
    confidence: float(),
    impact: :high | :medium | :low
  }
  
  @type change :: %{
    action: :replace | :insert | :delete,
    target: String.t(),
    replacement: String.t() | nil,
    location: map()
  }
  
  @doc """
  Returns the name of the strategy.
  """
  @callback name() :: atom()
  
  @doc """
  Returns the types of content this strategy can handle.
  """
  @callback supported_types() :: [content_type()]
  
  @doc """
  Analyzes content for issues and provides corrections.
  
  The evaluation parameter contains quality metrics from the evaluator
  that can guide the analysis.
  """
  @callback analyze(
    content :: String.t(),
    type :: content_type(),
    context :: map(),
    evaluation :: map()
  ) :: analysis_result()
  
  @doc """
  Returns the priority of corrections from this strategy.
  
  Higher priority strategies are applied first.
  """
  @callback priority() :: integer()
  
  @doc """
  Validates that a correction can be safely applied.
  """
  @callback validate_correction(
    content :: String.t(),
    correction :: correction()
  ) :: {:ok, correction()} | {:error, String.t()}
  
  # Helper functions for strategies
  
  @doc """
  Analyzes content using the given strategy module.
  """
  def analyze(strategy_module, content, type, context, evaluation) do
    if type in strategy_module.supported_types() do
      strategy_module.analyze(content, type, context, evaluation)
    else
      %{
        strategy: strategy_module.name(),
        issues: [],
        corrections: [],
        confidence: 0.0,
        metadata: %{unsupported_type: type}
      }
    end
  end
  
  @doc """
  Creates a replacement change.
  """
  def replace_change(target, replacement, location \\ %{}) do
    %{
      action: :replace,
      target: target,
      replacement: replacement,
      location: location
    }
  end
  
  @doc """
  Creates an insertion change.
  """
  def insert_change(target, content, location \\ %{}) do
    %{
      action: :insert,
      target: target,
      replacement: content,
      location: location
    }
  end
  
  @doc """
  Creates a deletion change.
  """
  def delete_change(target, location \\ %{}) do
    %{
      action: :delete,
      target: target,
      replacement: nil,
      location: location
    }
  end
  
  @doc """
  Creates an issue report.
  """
  def issue(type, severity, description, location \\ %{}, context \\ %{}) do
    %{
      type: type,
      severity: severity,
      description: description,
      location: location,
      context: context
    }
  end
  
  @doc """
  Creates a correction suggestion.
  """
  def correction(type, description, changes, confidence, impact \\ :medium) do
    %{
      type: type,
      description: description,
      changes: changes,
      confidence: confidence,
      impact: impact
    }
  end
end
defmodule RubberDuck.Agents.TokenManager.TokenUsage do
  @moduledoc """
  Data structure representing token usage for a single LLM request.
  
  Tracks detailed information about token consumption including provider,
  model, costs, and attribution to users/projects/teams.
  """

  @type t :: %__MODULE__{
    id: String.t(),
    timestamp: DateTime.t(),
    provider: String.t(),
    model: String.t(),
    prompt_tokens: non_neg_integer(),
    completion_tokens: non_neg_integer(),
    total_tokens: non_neg_integer(),
    cost: Decimal.t(),
    currency: String.t(),
    user_id: String.t() | nil,
    project_id: String.t() | nil,
    team_id: String.t() | nil,
    feature: String.t() | nil,
    request_id: String.t(),
    metadata: map()
  }

  defstruct [
    :id,
    :timestamp,
    :provider,
    :model,
    :prompt_tokens,
    :completion_tokens,
    :total_tokens,
    :cost,
    :currency,
    :user_id,
    :project_id,
    :team_id,
    :feature,
    :request_id,
    :metadata
  ]

  @doc """
  Creates a new TokenUsage record.
  
  ## Parameters
  
  - `attrs` - Map containing usage attributes
  
  ## Examples
  
      iex> TokenUsage.new(%{
      ...>   provider: "openai",
      ...>   model: "gpt-4",
      ...>   prompt_tokens: 100,
      ...>   completion_tokens: 50,
      ...>   user_id: "user123"
      ...> })
      %TokenUsage{...}
  """
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: Map.get(attrs, :id, generate_id()),
      timestamp: Map.get(attrs, :timestamp, DateTime.utc_now()),
      provider: Map.fetch!(attrs, :provider),
      model: Map.fetch!(attrs, :model),
      prompt_tokens: Map.fetch!(attrs, :prompt_tokens),
      completion_tokens: Map.fetch!(attrs, :completion_tokens),
      total_tokens: Map.get(attrs, :total_tokens, attrs.prompt_tokens + attrs.completion_tokens),
      cost: Map.get(attrs, :cost, Decimal.new(0)),
      currency: Map.get(attrs, :currency, "USD"),
      user_id: Map.get(attrs, :user_id),
      project_id: Map.get(attrs, :project_id),
      team_id: Map.get(attrs, :team_id),
      feature: Map.get(attrs, :feature),
      request_id: Map.get(attrs, :request_id, generate_id()),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @doc """
  Validates a TokenUsage record.
  
  Returns `{:ok, usage}` if valid, `{:error, errors}` otherwise.
  """
  def validate(%__MODULE__{} = usage) do
    errors = []
    
    errors = if usage.prompt_tokens < 0, do: ["prompt_tokens must be non-negative" | errors], else: errors
    errors = if usage.completion_tokens < 0, do: ["completion_tokens must be non-negative" | errors], else: errors
    errors = if usage.total_tokens != usage.prompt_tokens + usage.completion_tokens,
      do: ["total_tokens mismatch" | errors], else: errors
    errors = if Decimal.lt?(usage.cost, 0), do: ["cost must be non-negative" | errors], else: errors
    errors = if usage.provider == nil or usage.provider == "", do: ["provider is required" | errors], else: errors
    errors = if usage.model == nil or usage.model == "", do: ["model is required" | errors], else: errors
    
    if errors == [] do
      {:ok, usage}
    else
      {:error, errors}
    end
  end

  @doc """
  Calculates the efficiency ratio (tokens per dollar).
  """
  def efficiency_ratio(%__MODULE__{} = usage) do
    if Decimal.gt?(usage.cost, 0) do
      Decimal.div(Decimal.new(usage.total_tokens), usage.cost)
    else
      Decimal.new(0)
    end
  end

  @doc """
  Returns a map suitable for analytics aggregation.
  """
  def to_analytics_map(%__MODULE__{} = usage) do
    %{
      provider: usage.provider,
      model: usage.model,
      prompt_tokens: usage.prompt_tokens,
      completion_tokens: usage.completion_tokens,
      total_tokens: usage.total_tokens,
      cost: Decimal.to_float(usage.cost),
      currency: usage.currency,
      efficiency: Decimal.to_float(efficiency_ratio(usage)),
      timestamp: usage.timestamp,
      user_id: usage.user_id,
      project_id: usage.project_id,
      team_id: usage.team_id,
      feature: usage.feature
    }
  end

  @doc """
  Groups a list of usage records by a specified field.
  """
  def group_by(usage_list, field) when is_list(usage_list) and is_atom(field) do
    Enum.group_by(usage_list, &Map.get(&1, field))
  end

  @doc """
  Calculates total tokens from a list of usage records.
  """
  def total_tokens(usage_list) when is_list(usage_list) do
    Enum.reduce(usage_list, 0, fn usage, acc ->
      acc + usage.total_tokens
    end)
  end

  @doc """
  Calculates total cost from a list of usage records.
  """
  def total_cost(usage_list) when is_list(usage_list) do
    Enum.reduce(usage_list, Decimal.new(0), fn usage, acc ->
      Decimal.add(acc, usage.cost)
    end)
  end

  @doc """
  Filters usage records by date range.
  """
  def filter_by_date(usage_list, start_date, end_date) when is_list(usage_list) do
    Enum.filter(usage_list, fn usage ->
      DateTime.compare(usage.timestamp, start_date) != :lt and
      DateTime.compare(usage.timestamp, end_date) != :gt
    end)
  end

  @doc """
  Returns attribution summary for a usage record.
  """
  def attribution_summary(%__MODULE__{} = usage) do
    %{
      user: usage.user_id || "anonymous",
      project: usage.project_id || "default",
      team: usage.team_id || "default",
      feature: usage.feature || "general"
    }
  end

  defp generate_id do
    "usage_#{System.unique_integer([:positive, :monotonic])}"
  end
end
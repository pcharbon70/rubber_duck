defmodule RubberDuck.LLM.CostTracker do
  @moduledoc """
  Tracks costs and usage across LLM providers.
  """

  alias RubberDuck.LLM.Response

  @type usage_record :: %{
          provider: atom(),
          model: String.t(),
          prompt_tokens: non_neg_integer(),
          completion_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          cost: float(),
          timestamp: DateTime.t()
        }

  @type t :: %__MODULE__{
          records: list(usage_record()),
          total_cost: float(),
          cost_by_provider: %{atom() => float()},
          cost_by_model: %{String.t() => float()},
          token_usage: %{
            prompt_tokens: non_neg_integer(),
            completion_tokens: non_neg_integer(),
            total_tokens: non_neg_integer()
          }
        }

  defstruct records: [],
            total_cost: 0.0,
            cost_by_provider: %{},
            cost_by_model: %{},
            token_usage: %{
              prompt_tokens: 0,
              completion_tokens: 0,
              total_tokens: 0
            }

  @doc """
  Creates a new cost tracker.
  """
  def new do
    %__MODULE__{}
  end

  @doc """
  Records usage from a response.
  """
  def record_usage(%__MODULE__{} = tracker, provider, %Response{} = response) do
    if response.usage do
      cost = Response.calculate_cost(response)

      record = %{
        provider: provider,
        model: response.model,
        prompt_tokens: response.usage.prompt_tokens,
        completion_tokens: response.usage.completion_tokens,
        total_tokens: response.usage.total_tokens,
        cost: cost,
        timestamp: DateTime.utc_now()
      }

      %{
        tracker
        | # Keep last 1000 records
          records: [record | tracker.records] |> Enum.take(1000),
          total_cost: tracker.total_cost + cost,
          cost_by_provider: update_cost_map(tracker.cost_by_provider, provider, cost),
          cost_by_model: update_cost_map(tracker.cost_by_model, response.model, cost),
          token_usage: update_token_usage(tracker.token_usage, response.usage)
      }
    else
      tracker
    end
  end

  @doc """
  Gets a summary of costs and usage.

  Options:
  - `:since` - DateTime to filter records from
  - `:provider` - Filter by specific provider
  - `:model` - Filter by specific model
  """
  def get_summary(%__MODULE__{} = tracker, opts \\ []) do
    filtered_records = filter_records(tracker.records, opts)

    %{
      total_cost: calculate_total_cost(filtered_records),
      record_count: length(filtered_records),
      cost_by_provider: group_costs_by_provider(filtered_records),
      cost_by_model: group_costs_by_model(filtered_records),
      token_usage: calculate_token_usage(filtered_records),
      average_cost_per_request: calculate_average_cost(filtered_records),
      time_range: get_time_range(filtered_records)
    }
  end

  @doc """
  Gets cost for a specific period.
  """
  def get_cost_for_period(%__MODULE__{} = tracker, start_date, end_date) do
    tracker.records
    |> Enum.filter(fn record ->
      DateTime.compare(record.timestamp, start_date) in [:gt, :eq] &&
        DateTime.compare(record.timestamp, end_date) in [:lt, :eq]
    end)
    |> calculate_total_cost()
  end

  @doc """
  Exports usage data as CSV.
  """
  def export_csv(%__MODULE__{} = tracker) do
    headers = "Timestamp,Provider,Model,Prompt Tokens,Completion Tokens,Total Tokens,Cost\n"

    rows =
      tracker.records
      # Oldest first
      |> Enum.reverse()
      |> Enum.map(fn record ->
        [
          DateTime.to_iso8601(record.timestamp),
          record.provider,
          record.model,
          record.prompt_tokens,
          record.completion_tokens,
          record.total_tokens,
          Float.round(record.cost, 4)
        ]
        |> Enum.join(",")
      end)
      |> Enum.join("\n")

    headers <> rows
  end

  # Private functions

  defp update_cost_map(map, key, cost) do
    Map.update(map, key, cost, &(&1 + cost))
  end

  defp update_token_usage(usage, new_usage) do
    %{
      prompt_tokens: usage.prompt_tokens + new_usage.prompt_tokens,
      completion_tokens: usage.completion_tokens + new_usage.completion_tokens,
      total_tokens: usage.total_tokens + new_usage.total_tokens
    }
  end

  defp filter_records(records, opts) do
    records
    |> filter_by_date(opts[:since])
    |> filter_by_provider(opts[:provider])
    |> filter_by_model(opts[:model])
  end

  defp filter_by_date(records, nil), do: records

  defp filter_by_date(records, since) do
    Enum.filter(records, fn record ->
      DateTime.compare(record.timestamp, since) in [:gt, :eq]
    end)
  end

  defp filter_by_provider(records, nil), do: records

  defp filter_by_provider(records, provider) do
    Enum.filter(records, &(&1.provider == provider))
  end

  defp filter_by_model(records, nil), do: records

  defp filter_by_model(records, model) do
    Enum.filter(records, &(&1.model == model))
  end

  defp calculate_total_cost(records) do
    Enum.reduce(records, 0.0, &(&1.cost + &2))
  end

  defp group_costs_by_provider(records) do
    Enum.group_by(records, & &1.provider)
    |> Enum.map(fn {provider, provider_records} ->
      {provider, calculate_total_cost(provider_records)}
    end)
    |> Map.new()
  end

  defp group_costs_by_model(records) do
    Enum.group_by(records, & &1.model)
    |> Enum.map(fn {model, model_records} ->
      {model, calculate_total_cost(model_records)}
    end)
    |> Map.new()
  end

  defp calculate_token_usage(records) do
    Enum.reduce(records, %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}, fn record, acc ->
      %{
        prompt_tokens: acc.prompt_tokens + record.prompt_tokens,
        completion_tokens: acc.completion_tokens + record.completion_tokens,
        total_tokens: acc.total_tokens + record.total_tokens
      }
    end)
  end

  defp calculate_average_cost([]), do: 0.0

  defp calculate_average_cost(records) do
    calculate_total_cost(records) / length(records)
  end

  defp get_time_range([]), do: nil

  defp get_time_range(records) do
    sorted = Enum.sort_by(records, & &1.timestamp, DateTime)

    %{
      start: List.last(sorted).timestamp,
      end: List.first(sorted).timestamp
    }
  end
end

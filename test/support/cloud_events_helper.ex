defmodule RubberDuck.Test.CloudEventsHelper do
  @moduledoc """
  Helper functions for creating valid CloudEvents in tests.
  """
  
  @doc """
  Creates a valid CloudEvent with the given type and optional data.
  
  ## Options
  - `:source` - Event source (default: "test/helper")
  - `:data` - Event data payload
  - `:id` - Event ID (default: generated UUID)
  - `:time` - Event timestamp (default: current time)
  - `:subject` - Event subject
  - `:datacontenttype` - Content type (default: "application/json")
  """
  def cloud_event(type, opts \\ []) do
    %{
      "specversion" => "1.0",
      "id" => Keyword.get_lazy(opts, :id, fn -> Uniq.UUID.uuid4() end),
      "source" => Keyword.get(opts, :source, "test/helper"),
      "type" => type,
      "time" => Keyword.get_lazy(opts, :time, fn -> DateTime.utc_now() |> DateTime.to_iso8601() end)
    }
    |> maybe_add_field("data", Keyword.get(opts, :data))
    |> maybe_add_field("subject", Keyword.get(opts, :subject))
    |> maybe_add_field("datacontenttype", Keyword.get(opts, :datacontenttype))
  end
  
  @doc """
  Creates a CloudEvent for increment action.
  """
  def increment_event(amount \\ 1, opts \\ []) do
    cloud_event("increment", 
      Keyword.merge([
        data: %{"amount" => amount},
        source: "test/increment"
      ], opts)
    )
  end
  
  @doc """
  Creates a CloudEvent for add_message action.
  """
  def add_message_event(message, opts \\ []) do
    cloud_event("add_message",
      Keyword.merge([
        data: %{
          "message" => message,
          "timestamp" => Keyword.get(opts, :timestamp, true)
        },
        source: "test/message"
      ], opts)
    )
  end
  
  @doc """
  Creates a CloudEvent for update_status action.
  """
  def update_status_event(status, opts \\ []) do
    cloud_event("update_status",
      Keyword.merge([
        data: %{
          "status" => to_string(status),
          "reason" => Keyword.get(opts, :reason)
        },
        source: "test/status"
      ], opts)
    )
  end
  
  # Private helpers
  
  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)
end
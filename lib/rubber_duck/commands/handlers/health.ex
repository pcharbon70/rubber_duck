defmodule RubberDuck.Commands.Handlers.Health do
  @moduledoc """
  Handler for health check commands.
  
  Provides system health information including server status,
  memory usage, and service availability.
  """

  @behaviour RubberDuck.Commands.Handler

  alias RubberDuck.Commands.Command

  @impl true
  def execute(%Command{name: :health} = _command) do
    uptime_ms = get_uptime()
    
    health_data = %{
      status: "healthy",
      timestamp: DateTime.utc_now(),
      uptime: %{
        milliseconds: uptime_ms,
        seconds: div(uptime_ms, 1000),
        minutes: div(uptime_ms, 60_000),
        hours: div(uptime_ms, 3_600_000),
        days: div(uptime_ms, 86_400_000)
      },
      memory: get_memory_info(),
      services: check_services()
    }

    {:ok, health_data}
  end

  def execute(_command) do
    {:error, "Invalid command for health handler"}
  end

  @impl true
  def validate(%Command{name: :health}), do: :ok
  def validate(_), do: {:error, "Invalid command for health handler"}

  # Private functions

  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end

  defp get_memory_info do
    memory = :erlang.memory()
    
    %{
      total: Keyword.get(memory, :total, 0),
      processes: Keyword.get(memory, :processes, 0),
      system: Keyword.get(memory, :system, 0),
      atom: Keyword.get(memory, :atom, 0),
      binary: Keyword.get(memory, :binary, 0),
      ets: Keyword.get(memory, :ets, 0)
    }
  end

  defp check_services do
    %{
      database: check_database(),
      # Add other service checks here
    }
  end

  defp check_database do
    try do
      # Simple database connectivity check
      case RubberDuck.Repo.__adapter__.checked_out?(RubberDuck.Repo) do
        true -> "connected"
        false -> 
          # Try a simple query
          case Ecto.Adapters.SQL.query(RubberDuck.Repo, "SELECT 1", []) do
            {:ok, _} -> "connected"
            {:error, _} -> "disconnected"
          end
      end
    rescue
      _ -> "unavailable"
    end
  end
end
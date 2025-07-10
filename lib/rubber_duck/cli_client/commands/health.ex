defmodule RubberDuck.CLIClient.Commands.Health do
  @moduledoc """
  Health check command for RubberDuck CLI.

  Displays server health information including uptime, memory usage,
  active connections, and provider status.
  """

  alias RubberDuck.CLIClient.Client

  def run(_args, _opts) do
    case Client.send_command("health", %{}) do
      {:ok, health_data} ->
        {:ok, format_health_data(health_data)}

      {:error, reason} ->
        {:error, "Failed to get health status: #{inspect(reason)}"}
    end
  end

  defp format_health_data(data) do
    %{
      type: :health_status,
      status: data["status"],
      server_time: data["server_time"],
      uptime: format_uptime(data["uptime"]),
      memory: format_memory(data["memory"]),
      connections: data["connections"],
      providers: format_providers(data["providers"])
    }
  end

  defp format_uptime(uptime) when is_map(uptime) do
    days = Map.get(uptime, "days", 0)
    hours = Map.get(uptime, "hours", 0)
    minutes = Map.get(uptime, "minutes", 0)

    parts = []
    parts = if days > 0, do: ["#{days}d" | parts], else: parts
    parts = if hours > 0, do: ["#{hours}h" | parts], else: parts
    parts = if minutes > 0 or (days == 0 and hours == 0), do: ["#{minutes}m" | parts], else: parts

    Enum.reverse(parts) |> Enum.join(" ")
  end

  defp format_uptime(_), do: "unknown"

  defp format_memory(memory) when is_map(memory) do
    %{
      total_mb: Map.get(memory, "total_mb", 0),
      processes_mb: Map.get(memory, "processes_mb", 0),
      ets_mb: Map.get(memory, "ets_mb", 0),
      binary_mb: Map.get(memory, "binary_mb", 0),
      system_mb: Map.get(memory, "system_mb", 0)
    }
  end

  defp format_memory(_), do: %{}

  defp format_providers(providers) when is_list(providers) do
    Enum.map(providers, fn provider ->
      %{
        name: Map.get(provider, "name"),
        status: Map.get(provider, "status"),
        health: Map.get(provider, "health")
      }
    end)
  end

  defp format_providers(_), do: []
end

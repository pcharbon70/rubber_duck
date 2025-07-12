defmodule RubberDuck.Commands.Handlers.LLM do
  @moduledoc """
  Handler for LLM management commands.
  
  Provides commands for managing LLM provider connections, status monitoring,
  and configuration changes through the ConnectionManager.
  """

  @behaviour RubberDuck.Commands.Handler

  alias RubberDuck.Commands.{Command, Handler}
  alias RubberDuck.LLM.ConnectionManager

  @impl true
  def execute(%Command{name: :llm, subcommand: subcommand, args: args, options: options} = command) do
    with :ok <- validate(command) do
      case subcommand do
        :status -> show_status(args, options)
        :connect -> connect_provider(args, options)
        :disconnect -> disconnect_provider(args, options)
        :enable -> enable_provider(args, options)
        :disable -> disable_provider(args, options)
        _ -> {:error, "Unknown LLM subcommand: #{subcommand}"}
      end
    end
  end

  # Handle legacy calls without subcommand - default to status
  def execute(%Command{name: :llm, subcommand: nil} = command) do
    execute(%{command | subcommand: :status})
  end

  def execute(_command) do
    {:error, "Invalid command for LLM handler"}
  end

  @impl true
  def validate(%Command{name: :llm, subcommand: subcommand}) do
    valid_subcommands = [:status, :connect, :disconnect, :enable, :disable, nil]
    
    if subcommand in valid_subcommands do
      :ok
    else
      {:error, "Invalid LLM subcommand: #{subcommand}"}
    end
  end
  
  def validate(_), do: {:error, "Invalid command for LLM handler"}

  # Private functions

  defp show_status(_args, options) do
    case ConnectionManager.status() do
      status when is_map(status) ->
        format_status(status, options)

      error ->
        {:error, "Failed to get status: #{inspect(error)}"}
    end
  end

  defp connect_provider(args, _options) do
    provider = get_provider_arg(args)

    if provider do
      try do
        provider_atom = String.to_existing_atom(provider)

        case ConnectionManager.connect(provider_atom) do
          :ok ->
            {:ok, %{
              type: "llm_connection",
              message: "Successfully connected to #{provider}",
              provider: provider,
              timestamp: DateTime.utc_now()
            }}

          {:ok, :already_connected} ->
            {:ok, %{
              type: "llm_connection",
              message: "Already connected to #{provider}",
              provider: provider,
              timestamp: DateTime.utc_now()
            }}

          {:error, reason} ->
            {:error, "Failed to connect to #{provider}: #{inspect(reason)}"}
        end
      rescue
        ArgumentError ->
          {:error, "Unknown provider: #{provider}"}
      end
    else
      # Connect all providers
      case ConnectionManager.connect_all() do
        :ok ->
          {:ok, %{
            type: "llm_connection",
            message: "Connected to all configured providers",
            timestamp: DateTime.utc_now()
          }}

        error ->
          {:error, "Failed to connect: #{inspect(error)}"}
      end
    end
  end

  defp disconnect_provider(args, _options) do
    provider = get_provider_arg(args)

    if provider do
      try do
        provider_atom = String.to_existing_atom(provider)

        case ConnectionManager.disconnect(provider_atom) do
          :ok ->
            {:ok, %{
              type: "llm_disconnection",
              message: "Disconnected from #{provider}",
              provider: provider,
              timestamp: DateTime.utc_now()
            }}

          {:ok, :already_disconnected} ->
            {:ok, %{
              type: "llm_disconnection",
              message: "Already disconnected from #{provider}",
              provider: provider,
              timestamp: DateTime.utc_now()
            }}

          error ->
            {:error, "Failed to disconnect: #{inspect(error)}"}
        end
      rescue
        ArgumentError ->
          {:error, "Unknown provider: #{provider}"}
      end
    else
      # Disconnect all providers
      case ConnectionManager.disconnect_all() do
        :ok ->
          {:ok, %{
            type: "llm_disconnection",
            message: "Disconnected from all providers",
            timestamp: DateTime.utc_now()
          }}

        error ->
          {:error, "Failed to disconnect: #{inspect(error)}"}
      end
    end
  end

  defp enable_provider(args, _options) do
    provider = get_provider_arg(args)

    if provider do
      try do
        provider_atom = String.to_existing_atom(provider)

        case ConnectionManager.set_enabled(provider_atom, true) do
          :ok ->
            {:ok, %{
              type: "llm_config",
              message: "Enabled provider: #{provider}",
              provider: provider,
              timestamp: DateTime.utc_now()
            }}

          error ->
            {:error, "Failed to enable provider: #{inspect(error)}"}
        end
      rescue
        ArgumentError ->
          {:error, "Unknown provider: #{provider}"}
      end
    else
      {:error, "Provider name required for enable command"}
    end
  end

  defp disable_provider(args, _options) do
    provider = get_provider_arg(args)

    if provider do
      try do
        provider_atom = String.to_existing_atom(provider)

        case ConnectionManager.set_enabled(provider_atom, false) do
          :ok ->
            {:ok, %{
              type: "llm_config",
              message: "Disabled provider: #{provider}",
              provider: provider,
              timestamp: DateTime.utc_now()
            }}

          error ->
            {:error, "Failed to disable provider: #{inspect(error)}"}
        end
      rescue
        ArgumentError ->
          {:error, "Unknown provider: #{provider}"}
      end
    else
      {:error, "Provider name required for disable command"}
    end
  end

  defp get_provider_arg(args) do
    Map.get(args, :provider)
  end

  defp format_status(status, options) do
    providers =
      Enum.map(status, fn {name, info} ->
        %{
          name: name,
          status: format_connection_status(info.status),
          enabled: info.enabled,
          health: format_health(info.health),
          last_used: format_time(info.last_used),
          errors: info.error_count
        }
      end)

    summary = %{
      total: length(providers),
      connected: Enum.count(providers, &(&1.status == "connected")),
      healthy: Enum.count(providers, &(&1.health == "healthy"))
    }

    {:ok, %{
      type: "llm_status",
      providers: providers,
      summary: summary,
      verbose: Map.get(options, :verbose, false),
      timestamp: DateTime.utc_now()
    }}
  end

  defp format_connection_status(status) do
    to_string(status)
  end

  defp format_health(:healthy), do: "healthy"
  defp format_health(:not_connected), do: "not connected"
  defp format_health(:unknown), do: "unknown"
  defp format_health({:unhealthy, reason}), do: "unhealthy: #{inspect(reason)}"
  defp format_health(_), do: "unknown"

  defp format_time(nil), do: "never"

  defp format_time(%DateTime{} = time) do
    time
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end

  defp format_time(_), do: "unknown"
end
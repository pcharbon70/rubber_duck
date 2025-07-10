defmodule RubberDuck.CLI.Commands.LLM do
  @moduledoc """
  CLI commands for managing LLM connections.
  """

  alias RubberDuck.LLM.ConnectionManager

  @doc """
  Handles LLM management commands.
  """
  def run(subcommand, args, config) when is_atom(subcommand) do
    # Direct call from Runner with subcommand as first arg
    case subcommand do
      :status -> show_status(args, config)
      :connect -> connect_provider(args, config)
      :disconnect -> disconnect_provider(args, config)
      :enable -> enable_provider(args, config)
      :disable -> disable_provider(args, config)
      _ -> {:error, "Unknown LLM subcommand: #{subcommand}"}
    end
  end

  def run(args, config) do
    # Legacy call pattern - default to status
    show_status(args, config)
  end

  defp get_provider_arg(args) do
    # The provider is a named argument in the args map
    args[:provider]
  end

  defp show_status(_args, config) do
    case ConnectionManager.status() do
      status when is_map(status) ->
        format_status(status, config)

      error ->
        {:error, "Failed to get status: #{inspect(error)}"}
    end
  end

  defp connect_provider(args, _config) do
    provider = get_provider_arg(args)

    if provider do
      try do
        provider_atom = String.to_existing_atom(provider)

        case ConnectionManager.connect(provider_atom) do
          :ok ->
            {:ok,
             %{
               type: :llm_connection,
               message: "Successfully connected to #{provider}",
               provider: provider
             }}

          {:ok, :already_connected} ->
            {:ok,
             %{
               type: :llm_connection,
               message: "Already connected to #{provider}",
               provider: provider
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
          {:ok,
           %{
             type: :llm_connection,
             message: "Connected to all configured providers"
           }}

        error ->
          {:error, "Failed to connect: #{inspect(error)}"}
      end
    end
  end

  defp disconnect_provider(args, _config) do
    provider = get_provider_arg(args)

    if provider do
      try do
        provider_atom = String.to_existing_atom(provider)

        case ConnectionManager.disconnect(provider_atom) do
          :ok ->
            {:ok,
             %{
               type: :llm_disconnection,
               message: "Disconnected from #{provider}",
               provider: provider
             }}

          {:ok, :already_disconnected} ->
            {:ok,
             %{
               type: :llm_disconnection,
               message: "Already disconnected from #{provider}",
               provider: provider
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
          {:ok,
           %{
             type: :llm_disconnection,
             message: "Disconnected from all providers"
           }}

        error ->
          {:error, "Failed to disconnect: #{inspect(error)}"}
      end
    end
  end

  defp enable_provider(args, _config) do
    provider = get_provider_arg(args)

    if provider do
      try do
        provider_atom = String.to_existing_atom(provider)

        case ConnectionManager.set_enabled(provider_atom, true) do
          :ok ->
            {:ok,
             %{
               type: :llm_config,
               message: "Enabled provider: #{provider}",
               provider: provider
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

  defp disable_provider(args, _config) do
    provider = get_provider_arg(args)

    if provider do
      try do
        provider_atom = String.to_existing_atom(provider)

        case ConnectionManager.set_enabled(provider_atom, false) do
          :ok ->
            {:ok,
             %{
               type: :llm_config,
               message: "Disabled provider: #{provider}",
               provider: provider
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

  defp format_status(status, config) do
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

    {:ok,
     %{
       type: :llm_status,
       providers: providers,
       summary: summary,
       verbose: config.verbose
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

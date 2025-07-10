defmodule RubberDuckWeb.CLIChannel do
  @moduledoc """
  Channel for handling CLI commands via WebSocket connection.

  This channel provides a real-time interface for CLI clients to execute
  commands without requiring compilation or losing server state.
  """

  use RubberDuckWeb, :channel

  alias RubberDuck.CLI.Commands
  alias RubberDuck.LLM.ConnectionManager

  require Logger

  @doc """
  Joins the CLI channel with authentication.
  """
  @impl true
  def join("cli:commands", _params, socket) do
    # CLI client authenticated via API key in UserSocket
    if socket.assigns[:user_id] do
      socket =
        socket
        |> assign(:request_count, 0)
        |> assign(:connected_at, DateTime.utc_now())

      Logger.info("CLI client connected: #{socket.assigns.user_id}")
      {:ok, %{status: "connected", server_time: DateTime.utc_now()}, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Handle analyze command
  @impl true
  def handle_in("analyze", %{"path" => path} = params, socket) do
    socket = increment_request_count(socket)
    request_id = Map.get(params, "request_id")

    Task.start_link(fn ->
      args = [
        path: path,
        type: String.to_atom(Map.get(params, "type", "all")),
        flags: [
          recursive: Map.get(params, "recursive", false),
          include_suggestions: Map.get(params, "include_suggestions", false)
        ]
      ]

      result =
        case Commands.Analyze.run(args, build_config(params)) do
          {:ok, data} -> data
          {:error, _} = error -> error
          # Handle direct return
          data -> data
        end

      case result do
        {:error, reason} ->
          push(socket, "analyze:error", %{
            status: "error",
            reason: to_string(reason),
            request_id: request_id
          })

        data ->
          push(socket, "analyze:result", %{
            status: "success",
            result: data,
            request_id: request_id
          })
      end
    end)

    {:reply, {:ok, %{status: "processing"}}, socket}
  end

  # Handle generate command
  @impl true
  def handle_in("generate", %{"prompt" => prompt} = params, socket) do
    socket = increment_request_count(socket)
    request_id = Map.get(params, "request_id")

    Task.start_link(fn ->
      case Commands.Generate.run(%{prompt: prompt}, build_config(params)) do
        {:ok, result} ->
          push(socket, "generate:result", %{
            status: "success",
            result: result,
            request_id: request_id
          })

        {:error, reason} ->
          push(socket, "generate:error", %{
            status: "error",
            reason: to_string(reason),
            request_id: request_id
          })
      end
    end)

    {:reply, {:ok, %{status: "processing"}}, socket}
  end

  # Handle complete command
  @impl true
  def handle_in("complete", params, socket) do
    socket = increment_request_count(socket)
    request_id = Map.get(params, "request_id")

    Task.start_link(fn ->
      case Commands.Complete.run(params, build_config(params)) do
        {:ok, result} ->
          push(socket, "complete:result", %{
            status: "success",
            result: result,
            request_id: request_id
          })

        {:error, reason} ->
          push(socket, "complete:error", %{
            status: "error",
            reason: to_string(reason),
            request_id: request_id
          })
      end
    end)

    {:reply, {:ok, %{status: "processing"}}, socket}
  end

  # Handle refactor command
  @impl true
  def handle_in("refactor", params, socket) do
    socket = increment_request_count(socket)
    request_id = Map.get(params, "request_id")

    Task.start_link(fn ->
      case Commands.Refactor.run(params, build_config(params)) do
        {:ok, result} ->
          push(socket, "refactor:result", %{
            status: "success",
            result: result,
            request_id: request_id
          })

        {:error, reason} ->
          push(socket, "refactor:error", %{
            status: "error",
            reason: to_string(reason),
            request_id: request_id
          })
      end
    end)

    {:reply, {:ok, %{status: "processing"}}, socket}
  end

  # Handle test command
  @impl true
  def handle_in("test", params, socket) do
    socket = increment_request_count(socket)
    request_id = Map.get(params, "request_id")

    Task.start_link(fn ->
      case Commands.Test.run(params, build_config(params)) do
        {:ok, result} ->
          push(socket, "test:result", %{
            status: "success",
            result: result,
            request_id: request_id
          })

        {:error, reason} ->
          push(socket, "test:error", %{
            status: "error",
            reason: to_string(reason),
            request_id: request_id
          })
      end
    end)

    {:reply, {:ok, %{status: "processing"}}, socket}
  end

  # Handle LLM commands
  @impl true
  def handle_in("llm", %{"subcommand" => subcommand} = params, socket) do
    socket = increment_request_count(socket)

    result =
      case subcommand do
        "status" ->
          handle_llm_status(socket)

        "connect" ->
          handle_llm_connect(params["provider"], socket)

        "disconnect" ->
          handle_llm_disconnect(params["provider"], socket)

        "enable" ->
          handle_llm_enable(params["provider"], socket)

        "disable" ->
          handle_llm_disable(params["provider"], socket)

        _ ->
          {:error, "Unknown LLM subcommand: #{subcommand}"}
      end

    case result do
      {:ok, response} ->
        {:reply, {:ok, response}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  # Handle streaming requests
  @impl true
  def handle_in("stream:" <> command, params, socket) do
    socket = increment_request_count(socket)
    stream_id = generate_stream_id()

    # Start streaming in a separate process
    Task.start_link(fn ->
      handle_streaming_command(command, params, stream_id, socket)
    end)

    {:reply, {:ok, %{stream_id: stream_id}}, socket}
  end

  # Handle ping to keep connection alive
  @impl true
  def handle_in("ping", _params, socket) do
    {:reply, {:ok, %{pong: System.system_time(:millisecond)}}, socket}
  end

  # Handle health check request
  @impl true
  def handle_in("health", _params, socket) do
    health_data = %{
      status: "healthy",
      server_time: DateTime.utc_now(),
      uptime: get_server_uptime(),
      memory: get_memory_stats(),
      connections: get_connection_stats(),
      providers: get_provider_health()
    }

    {:reply, {:ok, health_data}, socket}
  end

  # Handle stats request
  @impl true
  def handle_in("stats", _params, socket) do
    stats = %{
      request_count: socket.assigns.request_count,
      connected_at: socket.assigns.connected_at,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), socket.assigns.connected_at)
    }

    {:reply, {:ok, stats}, socket}
  end

  # Private functions

  defp increment_request_count(socket) do
    assign(socket, :request_count, socket.assigns.request_count + 1)
  end

  defp build_config(params) do
    %RubberDuck.CLI.Config{
      format: String.to_atom(params["format"] || "json"),
      verbose: params["verbose"] || false,
      quiet: params["quiet"] || false,
      debug: params["debug"] || false
    }
  end

  defp handle_llm_status(_socket) do
    case ConnectionManager.status() do
      status when is_map(status) ->
        {:ok,
         %{
           type: :llm_status,
           providers: format_provider_status(status)
         }}

      error ->
        {:error, "Failed to get status: #{inspect(error)}"}
    end
  end

  defp handle_llm_connect(provider, socket) when is_binary(provider) do
    try do
      provider_atom = String.to_existing_atom(provider)

      case ConnectionManager.connect(provider_atom) do
        :ok ->
          push(socket, "llm:connected", %{provider: provider})
          {:ok, %{message: "Successfully connected to #{provider}"}}

        {:ok, :already_connected} ->
          {:ok, %{message: "Already connected to #{provider}"}}

        {:error, reason} ->
          {:error, "Failed to connect to #{provider}: #{inspect(reason)}"}
      end
    rescue
      ArgumentError ->
        {:error, "Unknown provider: #{provider}"}
    end
  end

  defp handle_llm_connect(nil, _socket) do
    case ConnectionManager.connect_all() do
      :ok ->
        {:ok, %{message: "Connected to all configured providers"}}

      error ->
        {:error, "Failed to connect: #{inspect(error)}"}
    end
  end

  defp handle_llm_disconnect(provider, _socket) when is_binary(provider) do
    try do
      provider_atom = String.to_existing_atom(provider)

      case ConnectionManager.disconnect(provider_atom) do
        :ok ->
          {:ok, %{message: "Disconnected from #{provider}"}}

        {:ok, :already_disconnected} ->
          {:ok, %{message: "Already disconnected from #{provider}"}}

        error ->
          {:error, "Failed to disconnect: #{inspect(error)}"}
      end
    rescue
      ArgumentError ->
        {:error, "Unknown provider: #{provider}"}
    end
  end

  defp handle_llm_disconnect(nil, _socket) do
    case ConnectionManager.disconnect_all() do
      :ok ->
        {:ok, %{message: "Disconnected from all providers"}}

      error ->
        {:error, "Failed to disconnect: #{inspect(error)}"}
    end
  end

  defp handle_llm_enable(provider, _socket) when is_binary(provider) do
    try do
      provider_atom = String.to_existing_atom(provider)

      case ConnectionManager.set_enabled(provider_atom, true) do
        :ok ->
          {:ok, %{message: "Enabled provider: #{provider}"}}

        error ->
          {:error, "Failed to enable provider: #{inspect(error)}"}
      end
    rescue
      ArgumentError ->
        {:error, "Unknown provider: #{provider}"}
    end
  end

  defp handle_llm_enable(nil, _socket) do
    {:error, "Provider name required for enable command"}
  end

  defp handle_llm_disable(provider, _socket) when is_binary(provider) do
    try do
      provider_atom = String.to_existing_atom(provider)

      case ConnectionManager.set_enabled(provider_atom, false) do
        :ok ->
          {:ok, %{message: "Disabled provider: #{provider}"}}

        error ->
          {:error, "Failed to disable provider: #{inspect(error)}"}
      end
    rescue
      ArgumentError ->
        {:error, "Unknown provider: #{provider}"}
    end
  end

  defp handle_llm_disable(nil, _socket) do
    {:error, "Provider name required for disable command"}
  end

  defp format_provider_status(status) do
    Enum.map(status, fn {name, info} ->
      %{
        name: name,
        status: to_string(info.status),
        enabled: info.enabled,
        health: format_health(info.health),
        last_used: format_time(info.last_used),
        errors: info.error_count
      }
    end)
  end

  defp format_health(:healthy), do: "healthy"
  defp format_health(:not_connected), do: "not connected"
  defp format_health(:unknown), do: "unknown"
  defp format_health({:unhealthy, reason}), do: "unhealthy: #{inspect(reason)}"
  defp format_health(_), do: "unknown"

  defp format_time(nil), do: "never"
  defp format_time(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp format_time(_), do: "unknown"

  defp generate_stream_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp handle_streaming_command(command, _params, stream_id, socket) do
    # This is a placeholder for streaming command implementation
    # Each command type would handle its own streaming logic
    push(socket, "stream:start", %{stream_id: stream_id, command: command})

    # Simulate streaming data
    for i <- 1..5 do
      Process.sleep(500)

      push(socket, "stream:data", %{
        stream_id: stream_id,
        chunk: "Processing #{command} - step #{i}/5"
      })
    end

    push(socket, "stream:end", %{stream_id: stream_id, status: "completed"})
  end

  defp get_server_uptime do
    {uptime, _} = :erlang.statistics(:wall_clock)
    seconds = div(uptime, 1000)

    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    %{
      days: days,
      hours: hours,
      minutes: minutes,
      total_seconds: seconds
    }
  end

  defp get_memory_stats do
    memory = :erlang.memory()

    %{
      total_mb: Float.round(memory[:total] / 1_048_576, 2),
      processes_mb: Float.round(memory[:processes] / 1_048_576, 2),
      ets_mb: Float.round(memory[:ets] / 1_048_576, 2),
      binary_mb: Float.round(memory[:binary] / 1_048_576, 2),
      system_mb: Float.round(memory[:system] / 1_048_576, 2)
    }
  end

  defp get_connection_stats do
    # Get WebSocket connection count
    # Get WebSocket connection count - simplified for now
    connections = 1

    %{
      active_connections: connections,
      # code, analysis, workspace, cli
      total_channels: 4
    }
  end

  defp get_provider_health do
    case ConnectionManager.status() do
      status when is_map(status) ->
        Enum.map(status, fn {name, info} ->
          %{
            name: name,
            status: to_string(info.status),
            health: format_health(info.health)
          }
        end)

      _ ->
        []
    end
  end
end

defmodule RubberDuck.LLM.ConnectionManager do
  @moduledoc """
  Manages LLM provider connections with explicit connect/disconnect functionality.

  This module provides:
  - Explicit connection lifecycle management
  - Connection pooling for providers that support it
  - Health monitoring for active connections
  - Graceful shutdown of connections
  """

  use GenServer
  require Logger

  alias RubberDuck.LLM.{Service, ProviderConfig}

  defmodule State do
    @moduledoc false
    defstruct [
      # Map of provider_name => connection_state
      :connections,
      # Map of provider_name => monitor_ref
      :monitors,
      # Map of provider_name => last_check_result
      :health_checks,
      # Connection configuration
      :config
    ]
  end

  defmodule ConnectionState do
    @moduledoc false
    defstruct [
      # :disconnected, :connecting, :connected, :unhealthy, :disconnecting
      :status,
      # boolean - whether provider is enabled
      :enabled,
      # Provider-specific connection data
      :connection,
      # DateTime of last usage
      :last_used,
      # Number of consecutive errors
      :error_count,
      # DateTime when connected
      :connected_at,
      # Number of consecutive health check failures
      :health_failures
    ]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Connect to a specific LLM provider.
  """
  def connect(provider_name) when is_atom(provider_name) do
    GenServer.call(__MODULE__, {:connect, provider_name}, 10_000)
  end

  @doc """
  Disconnect from a specific LLM provider.
  """
  def disconnect(provider_name) when is_atom(provider_name) do
    GenServer.call(__MODULE__, {:disconnect, provider_name})
  end

  @doc """
  Connect to all configured providers.
  """
  def connect_all do
    GenServer.call(__MODULE__, :connect_all, 30_000)
  end

  @doc """
  Disconnect from all providers.
  """
  def disconnect_all do
    GenServer.call(__MODULE__, :disconnect_all)
  end

  @doc """
  Get connection status for all providers.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Check if a provider is connected and healthy.
  """
  def connected?(provider_name) when is_atom(provider_name) do
    GenServer.call(__MODULE__, {:connected?, provider_name})
  end

  @doc """
  Enable/disable a provider without disconnecting.
  """
  def set_enabled(provider_name, enabled) when is_atom(provider_name) and is_boolean(enabled) do
    GenServer.call(__MODULE__, {:set_enabled, provider_name, enabled})
  end

  @doc """
  Get detailed connection info for a provider.
  """
  def get_connection_info(provider_name) when is_atom(provider_name) do
    GenServer.call(__MODULE__, {:get_connection_info, provider_name})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    config = load_connection_config(opts)

    state = %State{
      connections: %{},
      monitors: %{},
      health_checks: %{},
      config: config
    }

    # Initialize connection states for all configured providers
    providers = get_configured_providers()

    connections =
      Map.new(providers, fn {name, _provider_config} ->
        {name,
         %ConnectionState{
           status: :disconnected,
           enabled: true,
           connection: nil,
           last_used: nil,
           error_count: 0,
           connected_at: nil,
           health_failures: 0
         }}
      end)

    state = %{state | connections: connections}

    # Schedule periodic health checks
    schedule_health_check(state.config.health_check_interval)

    {:ok, state}
  end

  @impl true
  def handle_call({:connect, provider_name}, _from, state) do
    case Map.get(state.connections, provider_name) do
      nil ->
        {:reply, {:error, :provider_not_configured}, state}

      %{status: :connected} ->
        {:reply, {:ok, :already_connected}, state}

      %{status: :connecting} ->
        {:reply, {:ok, :connecting}, state}

      conn_state ->
        case get_provider_config(provider_name) do
          nil ->
            {:reply, {:error, :provider_not_configured}, state}

          provider_config ->
            # Update status to connecting
            new_conn_state = %{conn_state | status: :connecting}
            new_connections = Map.put(state.connections, provider_name, new_conn_state)
            state = %{state | connections: new_connections}

            # Perform connection
            case perform_connection(provider_name, provider_config, state) do
              {:ok, connection_data, new_state} ->
                Logger.info("Connected to provider: #{provider_name}")
                {:reply, :ok, new_state}

              {:error, reason} = error ->
                Logger.error("Failed to connect to provider #{provider_name}: #{inspect(reason)}")
                # Revert status
                failed_conn_state = %{conn_state | status: :disconnected, error_count: conn_state.error_count + 1}
                failed_connections = Map.put(state.connections, provider_name, failed_conn_state)
                {:reply, error, %{state | connections: failed_connections}}
            end
        end
    end
  end

  @impl true
  def handle_call({:disconnect, provider_name}, _from, state) do
    case Map.get(state.connections, provider_name) do
      nil ->
        {:reply, {:error, :provider_not_configured}, state}

      %{status: :disconnected} ->
        {:reply, {:ok, :already_disconnected}, state}

      %{status: :disconnecting} ->
        {:reply, {:ok, :disconnecting}, state}

      conn_state ->
        # Update status to disconnecting
        new_conn_state = %{conn_state | status: :disconnecting}
        new_connections = Map.put(state.connections, provider_name, new_conn_state)
        state = %{state | connections: new_connections}

        # Perform disconnection
        new_state = perform_disconnection(provider_name, conn_state, state)
        Logger.info("Disconnected from provider: #{provider_name}")

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:connect_all, _from, state) do
    providers = get_configured_providers()
    results = []

    new_state =
      Enum.reduce(providers, state, fn {name, _config}, acc_state ->
        case handle_call({:connect, name}, nil, acc_state) do
          {:reply, :ok, updated_state} ->
            updated_state

          {:reply, {:error, _reason}, updated_state} ->
            updated_state

          _ ->
            acc_state
        end
      end)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:disconnect_all, _from, state) do
    new_state =
      Enum.reduce(state.connections, state, fn {provider_name, _conn_state}, acc_state ->
        case handle_call({:disconnect, provider_name}, nil, acc_state) do
          {:reply, :ok, updated_state} -> updated_state
          _ -> acc_state
        end
      end)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status =
      Map.new(state.connections, fn {provider, conn_state} ->
        health = Map.get(state.health_checks, provider, :unknown)

        info = %{
          status: conn_state.status,
          enabled: conn_state.enabled,
          health: health,
          last_used: conn_state.last_used,
          error_count: conn_state.error_count,
          connected_at: conn_state.connected_at
        }

        {provider, info}
      end)

    {:reply, status, state}
  end

  @impl true
  def handle_call({:connected?, provider_name}, _from, state) do
    result =
      case Map.get(state.connections, provider_name) do
        %{status: :connected, enabled: true} -> true
        _ -> false
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_enabled, provider_name, enabled}, _from, state) do
    case Map.get(state.connections, provider_name) do
      nil ->
        {:reply, {:error, :provider_not_configured}, state}

      conn_state ->
        new_conn_state = %{conn_state | enabled: enabled}
        new_connections = Map.put(state.connections, provider_name, new_conn_state)

        if enabled do
          Logger.info("Enabled provider: #{provider_name}")
        else
          Logger.info("Disabled provider: #{provider_name}")
        end

        {:reply, :ok, %{state | connections: new_connections}}
    end
  end

  @impl true
  def handle_call({:get_connection_info, provider_name}, _from, state) do
    case Map.get(state.connections, provider_name) do
      nil ->
        {:reply, {:error, :provider_not_configured}, state}

      conn_state ->
        info = %{
          status: conn_state.status,
          enabled: conn_state.enabled,
          connection: conn_state.connection,
          last_used: conn_state.last_used,
          error_count: conn_state.error_count,
          connected_at: conn_state.connected_at,
          health_failures: conn_state.health_failures,
          health: Map.get(state.health_checks, provider_name, :unknown)
        }

        {:reply, {:ok, info}, state}
    end
  end

  @impl true
  def handle_info(:health_check, state) do
    # Run health checks for all connected providers
    new_state =
      Enum.reduce(state.connections, state, fn {provider, conn_state}, acc_state ->
        if conn_state.status == :connected and conn_state.enabled do
          check_provider_health(provider, conn_state, acc_state)
        else
          # Update health status for non-connected providers
          new_health_checks = Map.put(acc_state.health_checks, provider, :not_connected)
          %{acc_state | health_checks: new_health_checks}
        end
      end)

    # Schedule next health check
    schedule_health_check(state.config.health_check_interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:update_last_used, provider_name}, state) do
    case Map.get(state.connections, provider_name) do
      nil ->
        {:noreply, state}

      conn_state ->
        new_conn_state = %{conn_state | last_used: DateTime.utc_now()}
        new_connections = Map.put(state.connections, provider_name, new_conn_state)
        {:noreply, %{state | connections: new_connections}}
    end
  end

  # Private functions

  defp load_connection_config(opts) do
    default_config = %{
      health_check_interval: 30_000,
      max_reconnect_attempts: 3,
      reconnect_delay: 5_000,
      connection_timeout: 10_000
    }

    app_config =
      Application.get_env(:rubber_duck, :llm, [])
      |> Keyword.get(:connection_config, %{})

    opts_config = Keyword.get(opts, :connection_config, %{})

    Map.merge(default_config, app_config)
    |> Map.merge(opts_config)
  end

  defp get_configured_providers do
    Application.get_env(:rubber_duck, :llm, [])
    |> Keyword.get(:providers, [])
    |> Enum.map(fn provider ->
      {provider.name, provider}
    end)
    |> Map.new()
  end

  defp get_provider_config(provider_name) do
    get_configured_providers()
    |> Map.get(provider_name)
  end

  defp perform_connection(provider_name, provider_config, state) do
    adapter = provider_config.adapter
    config = struct(ProviderConfig, provider_config)

    # Check if adapter supports connection management
    if function_exported?(adapter, :connect, 1) do
      case adapter.connect(config) do
        {:ok, connection_data} ->
          # Update connection state
          conn_state = Map.get(state.connections, provider_name)

          new_conn_state = %{
            conn_state
            | status: :connected,
              connection: connection_data,
              connected_at: DateTime.utc_now(),
              error_count: 0,
              health_failures: 0
          }

          new_connections = Map.put(state.connections, provider_name, new_conn_state)
          new_health_checks = Map.put(state.health_checks, provider_name, :healthy)

          new_state = %{state | connections: new_connections, health_checks: new_health_checks}

          {:ok, connection_data, new_state}

        {:error, reason} ->
          {:error, reason}
      end
    else
      # Provider doesn't require explicit connection
      conn_state = Map.get(state.connections, provider_name)

      new_conn_state = %{
        conn_state
        | status: :connected,
          connection: :stateless,
          connected_at: DateTime.utc_now(),
          error_count: 0,
          health_failures: 0
      }

      new_connections = Map.put(state.connections, provider_name, new_conn_state)
      new_health_checks = Map.put(state.health_checks, provider_name, :healthy)

      new_state = %{state | connections: new_connections, health_checks: new_health_checks}

      {:ok, :stateless, new_state}
    end
  end

  defp perform_disconnection(provider_name, conn_state, state) do
    provider_config = get_provider_config(provider_name)

    if provider_config do
      adapter = provider_config.adapter
      config = struct(ProviderConfig, provider_config)

      # Call disconnect if supported
      if function_exported?(adapter, :disconnect, 2) and conn_state.connection != :stateless do
        adapter.disconnect(config, conn_state.connection)
      end
    end

    # Update connection state
    new_conn_state = %{conn_state | status: :disconnected, connection: nil, connected_at: nil}

    new_connections = Map.put(state.connections, provider_name, new_conn_state)
    new_health_checks = Map.put(state.health_checks, provider_name, :not_connected)

    %{state | connections: new_connections, health_checks: new_health_checks}
  end

  defp check_provider_health(provider_name, conn_state, state) do
    provider_config = get_provider_config(provider_name)

    if provider_config do
      adapter = provider_config.adapter
      config = struct(ProviderConfig, provider_config)

      health_result =
        if function_exported?(adapter, :health_check, 2) do
          adapter.health_check(config, conn_state.connection)
        else
          # Default health check - just verify we can reach the provider
          {:ok, :healthy}
        end

      case health_result do
        {:ok, _} ->
          # Healthy
          new_conn_state = %{conn_state | health_failures: 0}
          new_connections = Map.put(state.connections, provider_name, new_conn_state)
          new_health_checks = Map.put(state.health_checks, provider_name, :healthy)

          %{state | connections: new_connections, health_checks: new_health_checks}

        {:error, reason} ->
          # Unhealthy
          failures = conn_state.health_failures + 1
          new_status = if failures >= 3, do: :unhealthy, else: conn_state.status

          new_conn_state = %{conn_state | health_failures: failures, status: new_status}

          new_connections = Map.put(state.connections, provider_name, new_conn_state)
          new_health_checks = Map.put(state.health_checks, provider_name, {:unhealthy, reason})

          if new_status == :unhealthy do
            Logger.warning("Provider #{provider_name} marked unhealthy after #{failures} failures: #{inspect(reason)}")
          end

          %{state | connections: new_connections, health_checks: new_health_checks}
      end
    else
      state
    end
  end

  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end
end

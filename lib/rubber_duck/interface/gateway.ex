defmodule RubberDuck.Interface.Gateway do
  @moduledoc """
  Central gateway for routing requests to appropriate interface adapters.
  
  This GenServer manages adapter registration, request routing, circuit breaking,
  and cross-interface metrics collection. It provides a unified entry point for
  all interface interactions while delegating to specific adapters.
  """

  use GenServer

  alias RubberDuck.Interface.{Behaviour, ErrorHandler, Transformer}
  alias RubberDuck.EventBroadcasting.EventBroadcaster
  alias RubberDuck.EventSchemas

  require Logger

  @type adapter_config :: %{
    module: module(),
    pid: pid() | nil,
    config: map(),
    status: :starting | :running | :stopping | :stopped | :failed,
    start_time: integer(),
    restart_count: integer()
  }

  @type circuit_breaker_state :: %{
    state: :closed | :half_open | :open,
    failure_count: non_neg_integer(),
    last_failure_time: integer() | nil,
    success_count: non_neg_integer(),
    half_open_start: integer() | nil
  }

  @type gateway_state :: %{
    adapters: %{atom() => adapter_config()},
    circuit_breakers: %{atom() => circuit_breaker_state()},
    metrics: %{atom() => map()},
    config: map()
  }

  # Client API

  @doc """
  Starts the Interface Gateway GenServer.
  
  ## Options
  - `:adapters` - List of {interface, {module, config}} tuples
  - `:circuit_breaker` - Circuit breaker configuration
  - `:metrics` - Metrics collection configuration
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a new adapter with the gateway.
  
  ## Parameters
  - `interface` - Interface identifier (e.g., :cli, :web, :lsp)
  - `adapter_module` - Module implementing the InterfaceBehaviour
  - `config` - Adapter-specific configuration
  
  ## Returns
  - `:ok` - Adapter registered successfully
  - `{:error, reason}` - Registration failed
  """
  def register_adapter(interface, adapter_module, config \\ []) do
    GenServer.call(__MODULE__, {:register_adapter, interface, adapter_module, config})
  end

  @doc """
  Unregisters an adapter from the gateway.
  
  ## Parameters
  - `interface` - Interface identifier to unregister
  
  ## Returns
  - `:ok` - Adapter unregistered successfully
  - `{:error, reason}` - Unregistration failed
  """
  def unregister_adapter(interface) do
    GenServer.call(__MODULE__, {:unregister_adapter, interface})
  end

  @doc """
  Routes a request to the appropriate adapter.
  
  ## Parameters
  - `request` - Request to route (will be normalized)
  - `interface` - Target interface (optional, can be inferred)
  - `options` - Routing options
  
  ## Returns
  - `{:ok, response}` - Request processed successfully
  - `{:error, error}` - Request processing failed
  - `{:async, ref}` - Asynchronous processing started
  """
  def route_request(request, interface \\ nil, options \\ []) do
    GenServer.call(__MODULE__, {:route_request, request, interface, options}, 
                   Keyword.get(options, :timeout, 30_000))
  end

  @doc """
  Lists all registered adapters and their status.
  """
  def list_adapters do
    GenServer.call(__MODULE__, :list_adapters)
  end

  @doc """
  Gets capabilities for a specific adapter.
  """
  def adapter_capabilities(interface) do
    GenServer.call(__MODULE__, {:adapter_capabilities, interface})
  end

  @doc """
  Gets gateway and adapter metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Performs health check on all adapters.
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end

  @doc """
  Gets gateway information and status.
  """
  def get_info do
    GenServer.call(__MODULE__, :get_info)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = %{
      circuit_breaker: %{
        threshold: 5,
        timeout: 60_000,
        half_open_max_calls: 3
      },
      metrics: %{
        window: :timer.minutes(5),
        max_errors: 100
      },
      adapter_restart: %{
        max_restarts: 3,
        max_seconds: 60
      }
    }
    |> Map.merge(Keyword.get(opts, :config, %{}))

    state = %{
      adapters: %{},
      circuit_breakers: %{},
      metrics: %{},
      config: config
    }

    # Register initial adapters if provided
    initial_adapters = Keyword.get(opts, :adapters, [])
    state = Enum.reduce(initial_adapters, state, fn {interface, {module, adapter_config}}, acc ->
      case register_adapter_internal(acc, interface, module, adapter_config) do
        {:ok, new_state} -> new_state
        {:error, reason} ->
          Logger.warning("Failed to register initial adapter #{interface}: #{inspect(reason)}")
          acc
      end
    end)

    {:ok, state}
  end

  @impl true
  def handle_call({:register_adapter, interface, adapter_module, config}, _from, state) do
    case register_adapter_internal(state, interface, adapter_module, config) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister_adapter, interface}, _from, state) do
    case unregister_adapter_internal(state, interface) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:route_request, request, interface, options}, from, state) do
    # Normalize request first
    actual_interface = interface || infer_interface(request)
    
    case Transformer.normalize_request(request, actual_interface) do
      {:ok, normalized_request} ->
        handle_normalized_request(normalized_request, actual_interface, options, from, state)
      {:error, reason} ->
        error = ErrorHandler.create_error(:validation_error, "Request normalization failed: #{reason}")
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call(:list_adapters, _from, state) do
    adapters = Enum.map(state.adapters, fn {interface, config} ->
      %{
        interface: interface,
        module: config.module,
        status: config.status,
        start_time: config.start_time,
        restart_count: config.restart_count,
        circuit_breaker: Map.get(state.circuit_breakers, interface, %{state: :closed})
      }
    end)
    
    {:reply, adapters, state}
  end

  @impl true
  def handle_call({:adapter_capabilities, interface}, _from, state) do
    case get_adapter_pid(state, interface) do
      {:ok, pid} ->
        try do
          capabilities = GenServer.call(pid, :capabilities, 5000)
          {:reply, {:ok, capabilities}, state}
        catch
          :exit, reason ->
            {:reply, {:error, {:adapter_unavailable, reason}}, state}
        end
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      gateway: %{
        adapters_count: map_size(state.adapters),
        active_adapters: count_active_adapters(state),
        total_requests: get_total_requests(state),
        circuit_breakers: get_circuit_breaker_summary(state)
      },
      adapters: state.metrics
    }
    
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    health_status = Enum.reduce(state.adapters, %{}, fn {interface, adapter_config}, acc ->
      status = case adapter_config.status do
        :running ->
          case get_adapter_pid(state, interface) do
            {:ok, pid} ->
              try do
                {health, metadata} = GenServer.call(pid, :health_check, 5000)
                %{status: health, metadata: metadata}
              catch
                :exit, reason ->
                  %{status: :unhealthy, reason: reason}
              end
            {:error, reason} ->
              %{status: :unhealthy, reason: reason}
          end
        status ->
          %{status: :unhealthy, reason: "Adapter status: #{status}"}
      end
      
      Map.put(acc, interface, status)
    end)
    
    overall_health = if Enum.all?(health_status, fn {_, %{status: status}} -> status == :healthy end) do
      :healthy
    else
      :degraded
    end
    
    {:reply, {overall_health, health_status}, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      status: :running,
      adapters: map_size(state.adapters),
      uptime: System.monotonic_time(:millisecond) - System.monotonic_time(:millisecond),
      memory: :erlang.process_info(self(), :memory) |> elem(1),
      config: state.config
    }
    
    {:reply, info, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle adapter process termination
    case find_adapter_by_pid(state, pid) do
      {:ok, interface} ->
        Logger.warning("Adapter #{interface} terminated: #{inspect(reason)}")
        new_state = handle_adapter_termination(state, interface, reason)
        {:noreply, new_state}
      :not_found ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:restart_adapter, interface}, state) do
    case restart_adapter_internal(state, interface) do
      {:ok, new_state} ->
        {:noreply, new_state}
      {:error, reason} ->
        Logger.error("Failed to restart adapter #{interface}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Private functions

  defp register_adapter_internal(state, interface, adapter_module, config) do
    if Map.has_key?(state.adapters, interface) do
      {:error, :adapter_already_registered}
    else
      case start_adapter(adapter_module, config) do
        {:ok, pid} ->
          adapter_config = %{
            module: adapter_module,
            pid: pid,
            config: config,
            status: :running,
            start_time: System.monotonic_time(:millisecond),
            restart_count: 0
          }
          
          # Monitor the adapter process
          Process.monitor(pid)
          
          # Initialize circuit breaker
          circuit_breaker = %{
            state: :closed,
            failure_count: 0,
            last_failure_time: nil,
            success_count: 0,
            half_open_start: nil
          }
          
          new_state = state
          |> put_in([:adapters, interface], adapter_config)
          |> put_in([:circuit_breakers, interface], circuit_breaker)
          |> put_in([:metrics, interface], %{})
          
          # Broadcast adapter registration event
          broadcast_adapter_event(interface, :registered, %{module: adapter_module})
          
          {:ok, new_state}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp unregister_adapter_internal(state, interface) do
    case Map.get(state.adapters, interface) do
      nil ->
        {:error, :adapter_not_found}
      adapter_config ->
        # Stop the adapter
        if adapter_config.pid do
          GenServer.stop(adapter_config.pid, :normal, 5000)
        end
        
        new_state = state
        |> Map.update!(:adapters, &Map.delete(&1, interface))
        |> Map.update!(:circuit_breakers, &Map.delete(&1, interface))
        |> Map.update!(:metrics, &Map.delete(&1, interface))
        
        # Broadcast adapter unregistration event
        broadcast_adapter_event(interface, :unregistered, %{})
        
        {:ok, new_state}
    end
  end

  defp handle_normalized_request(request, interface, options, from, state) do
    case check_circuit_breaker(state, interface) do
      :allow ->
        case get_adapter_pid(state, interface) do
          {:ok, pid} ->
            # Extract context
            {:ok, context} = Transformer.extract_context(request, interface)
            
            # Route to adapter
            try do
              case GenServer.call(pid, {:handle_request, request, context}, 30_000) do
                {:ok, response, _adapter_state} ->
                  # Update circuit breaker and metrics
                  new_state = record_success(state, interface)
                  
                  # Transform response for interface
                  case GenServer.call(pid, {:format_response, response, request}) do
                    {:ok, formatted_response} ->
                      {:reply, {:ok, formatted_response}, new_state}
                    {:error, format_error} ->
                      error = ErrorHandler.create_error(:internal_error, "Response formatting failed: #{inspect(format_error)}")
                      {:reply, {:error, error}, new_state}
                  end
                  
                {:error, error, _adapter_state} ->
                  # Update circuit breaker and metrics
                  new_state = record_failure(state, interface)
                  
                  # Transform error for interface
                  transformed_error = ErrorHandler.transform_error(error, interface)
                  {:reply, {:error, transformed_error}, new_state}
                  
                {:async, ref, _adapter_state} ->
                  # Handle async response
                  {:reply, {:async, ref}, state}
              end
            catch
              :exit, reason ->
                new_state = record_failure(state, interface)
                error = ErrorHandler.create_error(:timeout, "Adapter request timeout: #{inspect(reason)}")
                {:reply, {:error, error}, new_state}
            end
          {:error, reason} ->
            error = ErrorHandler.create_error(:unavailable, "Adapter unavailable: #{inspect(reason)}")
            {:reply, {:error, error}, state}
        end
      :deny ->
        error = ErrorHandler.create_error(:unavailable, "Circuit breaker is open")
        {:reply, {:error, error}, state}
    end
  end

  defp start_adapter(adapter_module, config) do
    try do
      case adapter_module.init(config) do
        {:ok, adapter_state} ->
          # Start the adapter as a GenServer (simplified for now)
          pid = spawn_link(fn -> 
            adapter_loop(adapter_module, adapter_state)
          end)
          {:ok, pid}
        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error -> {:error, {:init_failed, error}}
    end
  end

  defp adapter_loop(module, state) do
    receive do
      {:handle_request, request, context, reply_to} ->
        case module.handle_request(request, context, state) do
          {status, response, new_state} ->
            GenServer.reply(reply_to, {status, response, new_state})
            adapter_loop(module, new_state)
          other ->
            GenServer.reply(reply_to, other)
            adapter_loop(module, state)
        end
      {:format_response, response, request, reply_to} ->
        result = module.format_response(response, request, state)
        GenServer.reply(reply_to, result)
        adapter_loop(module, state)
      {:capabilities, reply_to} ->
        capabilities = module.capabilities()
        GenServer.reply(reply_to, capabilities)
        adapter_loop(module, state)
      {:health_check, reply_to} ->
        health = module.health_check(state)
        GenServer.reply(reply_to, health)
        adapter_loop(module, state)
      {:stop, reason} ->
        module.shutdown(reason, state)
        exit(reason)
    end
  end

  defp get_adapter_pid(state, interface) do
    case Map.get(state.adapters, interface) do
      nil -> {:error, :adapter_not_found}
      %{pid: nil} -> {:error, :adapter_not_running}
      %{pid: pid, status: :running} -> {:ok, pid}
      %{status: status} -> {:error, {:adapter_status, status}}
    end
  end

  defp check_circuit_breaker(state, interface) do
    case Map.get(state.circuit_breakers, interface) do
      nil -> :allow
      %{state: :closed} -> :allow
      %{state: :half_open, success_count: count} when count < 3 -> :allow
      %{state: :open, last_failure_time: last_failure} ->
        timeout = state.config.circuit_breaker.timeout
        if System.monotonic_time(:millisecond) - last_failure > timeout do
          :allow
        else
          :deny
        end
      _ -> :deny
    end
  end

  defp record_success(state, interface) do
    update_in(state, [:circuit_breakers, interface], fn breaker ->
      case breaker.state do
        :half_open ->
          if breaker.success_count + 1 >= 3 do
            %{breaker | state: :closed, success_count: 0, failure_count: 0}
          else
            %{breaker | success_count: breaker.success_count + 1}
          end
        _ ->
          %{breaker | failure_count: 0, success_count: 0}
      end
    end)
    |> update_metrics(interface, :success)
  end

  defp record_failure(state, interface) do
    update_in(state, [:circuit_breakers, interface], fn breaker ->
      new_failure_count = breaker.failure_count + 1
      threshold = state.config.circuit_breaker.threshold
      
      if new_failure_count >= threshold do
        %{breaker | 
          state: :open, 
          failure_count: new_failure_count,
          last_failure_time: System.monotonic_time(:millisecond)
        }
      else
        %{breaker | failure_count: new_failure_count}
      end
    end)
    |> update_metrics(interface, :failure)
  end

  defp update_metrics(state, interface, status) do
    update_in(state, [:metrics, interface], fn metrics ->
      Map.update(metrics, status, 1, &(&1 + 1))
    end)
  end

  defp infer_interface(request) do
    # Simple interface inference based on request structure
    cond do
      Map.has_key?(request, "command") -> :cli
      Map.has_key?(request, "method") and String.contains?(Map.get(request, "method", ""), "/") -> :lsp
      Map.has_key?(request, "headers") -> :web
      true -> :generic
    end
  end

  defp count_active_adapters(state) do
    Enum.count(state.adapters, fn {_, adapter} -> adapter.status == :running end)
  end

  defp get_total_requests(state) do
    Enum.reduce(state.metrics, 0, fn {_, metrics}, acc ->
      success = Map.get(metrics, :success, 0)
      failure = Map.get(metrics, :failure, 0)
      acc + success + failure
    end)
  end

  defp get_circuit_breaker_summary(state) do
    Enum.reduce(state.circuit_breakers, %{}, fn {interface, breaker}, acc ->
      Map.put(acc, interface, breaker.state)
    end)
  end

  defp find_adapter_by_pid(state, pid) do
    case Enum.find(state.adapters, fn {_, adapter} -> adapter.pid == pid end) do
      {interface, _} -> {:ok, interface}
      nil -> :not_found
    end
  end

  defp handle_adapter_termination(state, interface, reason) do
    # Update adapter status
    new_state = put_in(state, [:adapters, interface, :status], :failed)
    
    # Schedule restart if configured
    if should_restart_adapter?(new_state, interface) do
      Process.send_after(self(), {:restart_adapter, interface}, 5000)
    end
    
    # Broadcast adapter failure event
    broadcast_adapter_event(interface, :failed, %{reason: reason})
    
    new_state
  end

  defp should_restart_adapter?(state, interface) do
    adapter = state.adapters[interface]
    max_restarts = state.config.adapter_restart.max_restarts
    
    adapter.restart_count < max_restarts
  end

  defp restart_adapter_internal(state, interface) do
    case Map.get(state.adapters, interface) do
      nil ->
        {:error, :adapter_not_found}
      adapter_config ->
        case start_adapter(adapter_config.module, adapter_config.config) do
          {:ok, pid} ->
            Process.monitor(pid)
            
            new_adapter_config = %{adapter_config |
              pid: pid,
              status: :running,
              restart_count: adapter_config.restart_count + 1
            }
            
            new_state = put_in(state, [:adapters, interface], new_adapter_config)
            
            broadcast_adapter_event(interface, :restarted, %{restart_count: new_adapter_config.restart_count})
            
            {:ok, new_state}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp broadcast_adapter_event(interface, event, metadata) do
    event_payload = %{
      interface: interface,
      event: event,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
    
    EventBroadcaster.broadcast_async(%{
      topic: "interface.adapter.#{event}",
      payload: event_payload,
      priority: :normal,
      metadata: %{component: "interface_gateway"}
    })
  end
end
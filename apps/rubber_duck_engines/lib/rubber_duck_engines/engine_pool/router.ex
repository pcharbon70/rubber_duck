defmodule RubberDuckEngines.EnginePool.Router do
  @moduledoc """
  Request router for engine pool operations.

  Handles routing of analysis requests to appropriate engine pools,
  load balancing, and provides a unified interface for pool operations.
  """

  use GenServer

  alias RubberDuckEngines.EnginePool

  # Client API

  @doc """
  Starts the router.
  """
  def start_link(init_arg \\ []) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Routes an engine checkout request to the appropriate pool.
  """
  def checkout_engine(analysis_type, opts \\ []) do
    GenServer.call(__MODULE__, {:checkout_engine, analysis_type, opts})
  end

  @doc """
  Routes an engine checkin request to the appropriate pool.
  """
  def checkin_engine(engine_pid, analysis_type) do
    GenServer.cast(__MODULE__, {:checkin_engine, engine_pid, analysis_type})
  end

  @doc """
  Gets comprehensive pool statistics.
  """
  def pool_stats do
    GenServer.call(__MODULE__, :pool_stats)
  end

  @doc """
  Performs health check on all pools.
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end

  @doc """
  Routes an analysis request to the best available engine.
  """
  def route_analysis_request(analysis_request, opts \\ []) do
    GenServer.call(__MODULE__, {:route_analysis, analysis_request, opts})
  end

  # Server implementation

  @impl true
  def init(_init_arg) do
    # Register with the pool registry
    Registry.register(EnginePool.Registry, __MODULE__, %{role: :router})

    state = %{
      routing_stats: %{
        total_requests: 0,
        successful_routes: 0,
        failed_routes: 0,
        average_response_time: 0
      },
      pool_mapping: %{
        code_analysis: :code_analysis,
        documentation: :documentation,
        testing: :testing,
        # Add more mappings as needed
        code_review: :code_analysis,
        doc_generation: :documentation,
        test_generation: :testing
      }
    }

    emit_telemetry(:router_started, state.routing_stats, %{})
    {:ok, state}
  end

  @impl true
  def handle_call({:checkout_engine, analysis_type, opts}, from, state) do
    start_time = System.monotonic_time()

    case map_analysis_type_to_pool(analysis_type, state) do
      {:ok, pool_type} ->
        timeout = Keyword.get(opts, :timeout, 5000)

        case EnginePool.Worker.checkout_engine(pool_type, timeout) do
          {:ok, engine_pid} ->
            duration = System.monotonic_time() - start_time
            new_state = update_routing_stats(state, :success, duration)

            emit_telemetry(
              :engine_routed,
              %{
                analysis_type: analysis_type,
                pool_type: pool_type,
                engine_pid: engine_pid,
                client: from
              },
              %{duration: duration}
            )

            {:reply, {:ok, engine_pid}, new_state}

          {:error, reason} ->
            new_state = update_routing_stats(state, :failure, 0)

            emit_telemetry(
              :engine_routing_failed,
              %{
                analysis_type: analysis_type,
                pool_type: pool_type,
                reason: reason
              },
              %{}
            )

            {:reply, {:error, reason}, new_state}
        end

      {:error, :unknown_analysis_type} ->
        new_state = update_routing_stats(state, :failure, 0)

        emit_telemetry(
          :engine_routing_failed,
          %{
            analysis_type: analysis_type,
            reason: :unknown_analysis_type
          },
          %{}
        )

        {:reply, {:error, :unknown_analysis_type}, new_state}
    end
  end

  @impl true
  def handle_call(:pool_stats, _from, state) do
    pool_stats = collect_all_pool_stats()

    comprehensive_stats = %{
      router_stats: state.routing_stats,
      pool_stats: pool_stats,
      timestamp: DateTime.utc_now()
    }

    emit_telemetry(:pool_stats_collected, comprehensive_stats, %{})
    {:reply, comprehensive_stats, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    health_status = perform_health_check()

    emit_telemetry(:health_check_performed, health_status, %{})
    {:reply, health_status, state}
  end

  @impl true
  def handle_call({:route_analysis, analysis_request, opts}, from, state) do
    start_time = System.monotonic_time()
    analysis_type = Map.get(analysis_request, :type, :unknown)

    case checkout_engine(analysis_type, opts) do
      {:ok, engine_pid} ->
        # Execute analysis on the engine
        timeout = Keyword.get(opts, :timeout, 30_000)

        task =
          Task.async(fn ->
            GenServer.call(engine_pid, {:analyze, analysis_request}, timeout)
          end)

        try do
          result = Task.await(task, timeout)

          # Return engine to pool
          checkin_engine(engine_pid, analysis_type)

          duration = System.monotonic_time() - start_time
          new_state = update_routing_stats(state, :success, duration)

          emit_telemetry(
            :analysis_completed,
            %{
              analysis_type: analysis_type,
              engine_pid: engine_pid,
              client: from
            },
            %{duration: duration}
          )

          {:reply, {:ok, result}, new_state}
        catch
          :exit, {:timeout, _} ->
            # Return engine to pool even on timeout
            checkin_engine(engine_pid, analysis_type)

            new_state = update_routing_stats(state, :failure, 0)

            emit_telemetry(
              :analysis_timeout,
              %{
                analysis_type: analysis_type,
                engine_pid: engine_pid
              },
              %{}
            )

            {:reply, {:error, :timeout}, new_state}
        end

      {:error, reason} ->
        new_state = update_routing_stats(state, :failure, 0)

        emit_telemetry(
          :analysis_routing_failed,
          %{
            analysis_type: analysis_type,
            reason: reason
          },
          %{}
        )

        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_cast({:checkin_engine, engine_pid, analysis_type}, state) do
    case map_analysis_type_to_pool(analysis_type, state) do
      {:ok, pool_type} ->
        EnginePool.Worker.checkin_engine(pool_type, engine_pid)

        emit_telemetry(
          :engine_returned,
          %{
            analysis_type: analysis_type,
            pool_type: pool_type,
            engine_pid: engine_pid
          },
          %{}
        )

      {:error, _} ->
        emit_telemetry(
          :engine_return_failed,
          %{
            analysis_type: analysis_type,
            engine_pid: engine_pid,
            reason: :unknown_analysis_type
          },
          %{}
        )
    end

    {:noreply, state}
  end

  # Private helper functions

  defp map_analysis_type_to_pool(analysis_type, state) do
    case Map.get(state.pool_mapping, analysis_type) do
      nil -> {:error, :unknown_analysis_type}
      pool_type -> {:ok, pool_type}
    end
  end

  defp collect_all_pool_stats do
    pool_types = [:code_analysis, :documentation, :testing]

    pool_types
    |> Enum.map(fn pool_type ->
      case EnginePool.Worker.pool_stats(pool_type) do
        stats when is_map(stats) -> {pool_type, stats}
        _ -> {pool_type, %{status: :unavailable}}
      end
    end)
    |> Map.new()
  end

  defp perform_health_check do
    pool_types = [:code_analysis, :documentation, :testing]

    health_results =
      pool_types
      |> Enum.map(fn pool_type ->
        health_status = check_pool_health(pool_type)
        {pool_type, health_status}
      end)
      |> Map.new()

    overall_status = determine_overall_health(health_results)

    %{
      overall_status: overall_status,
      pool_health: health_results,
      timestamp: DateTime.utc_now()
    }
  end

  defp check_pool_health(pool_type) do
    try do
      case EnginePool.Worker.pool_stats(pool_type) do
        %{available_count: available, busy_count: busy} when available >= 0 and busy >= 0 ->
          %{status: :healthy, available: available, busy: busy}

        _ ->
          %{status: :unhealthy, reason: :invalid_stats}
      end
    catch
      :exit, {:timeout, _} ->
        %{status: :unhealthy, reason: :timeout}

      _type, reason ->
        %{status: :unhealthy, reason: reason}
    end
  end

  defp determine_overall_health(health_results) do
    statuses = health_results |> Map.values() |> Enum.map(& &1.status)

    cond do
      Enum.all?(statuses, &(&1 == :healthy)) -> :healthy
      Enum.any?(statuses, &(&1 == :healthy)) -> :degraded
      true -> :unhealthy
    end
  end

  defp update_routing_stats(state, result, duration) do
    new_stats =
      state.routing_stats
      |> Map.update!(:total_requests, &(&1 + 1))
      |> then(fn stats ->
        case result do
          :success ->
            stats
            |> Map.update!(:successful_routes, &(&1 + 1))
            |> Map.put(:average_response_time, calculate_new_average(stats, duration))

          :failure ->
            Map.update!(stats, :failed_routes, &(&1 + 1))
        end
      end)

    %{state | routing_stats: new_stats}
  end

  defp calculate_new_average(stats, new_duration) do
    total = stats.total_requests
    current_avg = stats.average_response_time

    if total == 0 do
      new_duration
    else
      (current_avg * total + new_duration) / (total + 1)
    end
  end

  defp emit_telemetry(event, metadata, measurements) do
    :telemetry.execute(
      [:rubber_duck_engines, :engine_pool, :router, event],
      measurements,
      metadata
    )
  end
end

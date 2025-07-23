defmodule RubberDuck.Projects.WatcherManager do
  @moduledoc """
  Manages multiple project file watchers with resource limits and LRU eviction.

  Provides centralized control for file watchers including:
  - Resource pooling with configurable limits
  - LRU eviction for inactive watchers
  - Activity tracking and statistics
  - Automatic cleanup of inactive watchers
  - Priority-based allocation
  """

  use GenServer
  require Logger

  alias RubberDuck.Projects.FileWatcher.Supervisor, as: FWSupervisor

  @default_max_watchers 20
  @default_inactive_timeout_minutes 30
  @default_cleanup_interval_minutes 5
  @default_queue_timeout_ms 5000

  defmodule WatcherInfo do
    @moduledoc false
    defstruct [
      :project_id,
      :pid,
      :started_at,
      :last_activity,
      :event_count,
      :subscriber_count,
      :priority,
      :root_path
    ]
  end

  defmodule State do
    @moduledoc false
    defstruct watchers: %{},
              max_watchers: 20,
              inactive_timeout_minutes: 30,
              cleanup_interval_minutes: 5,
              queue_timeout_ms: 5000,
              queue: :queue.new(),
              stats: %{
                total_started: 0,
                total_evicted: 0,
                total_stopped: 0,
                start_time: nil
              },
              cleanup_timer: nil
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a file watcher for a project, subject to resource limits.

  Returns:
  - `{:ok, :started}` if watcher was started immediately
  - `{:ok, :queued}` if request was queued due to capacity
  - `{:ok, :already_running}` if watcher already exists
  - `{:error, reason}` on failure
  """
  @spec start_watcher(String.t(), map()) :: {:ok, :started | :queued | :already_running} | {:error, term()}
  def start_watcher(project_id, opts) when is_binary(project_id) and is_map(opts) do
    GenServer.call(__MODULE__, {:start_watcher, project_id, opts})
  end

  @doc """
  Stops a file watcher for a project.
  """
  @spec stop_watcher(String.t()) :: :ok | {:error, :not_found}
  def stop_watcher(project_id) when is_binary(project_id) do
    GenServer.call(__MODULE__, {:stop_watcher, project_id})
  end

  @doc """
  Updates activity timestamp for a project.
  """
  @spec touch_activity(String.t()) :: :ok | {:error, :not_found}
  def touch_activity(project_id) when is_binary(project_id) do
    GenServer.cast(__MODULE__, {:touch_activity, project_id})
  end

  @doc """
  Gets information about a specific watcher.
  """
  @spec get_info(String.t()) :: {:ok, WatcherInfo.t()} | {:error, :not_found}
  def get_info(project_id) when is_binary(project_id) do
    GenServer.call(__MODULE__, {:get_info, project_id})
  end

  @doc """
  Gets statistics about the watcher manager.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Lists all active watchers.
  """
  @spec list_watchers() :: [WatcherInfo.t()]
  def list_watchers do
    GenServer.call(__MODULE__, :list_watchers)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %State{
      max_watchers: opts[:max_watchers] || @default_max_watchers,
      inactive_timeout_minutes: opts[:inactive_timeout_minutes] || @default_inactive_timeout_minutes,
      cleanup_interval_minutes: opts[:cleanup_interval_minutes] || @default_cleanup_interval_minutes,
      queue_timeout_ms: opts[:queue_timeout_ms] || @default_queue_timeout_ms,
      stats: %{
        total_started: 0,
        total_evicted: 0,
        total_stopped: 0,
        start_time: DateTime.utc_now()
      }
    }

    # Schedule periodic cleanup
    state = schedule_cleanup(state)

    Logger.info("WatcherManager started with max_watchers=#{state.max_watchers}")
    {:ok, state}
  end

  @impl true
  def handle_call({:start_watcher, project_id, opts}, from, state) do
    case Map.get(state.watchers, project_id) do
      nil ->
        if map_size(state.watchers) < state.max_watchers do
          # Start immediately
          start_watcher_immediate(project_id, opts, from, state)
        else
          # Try eviction or queue
          handle_at_capacity(project_id, opts, from, state)
        end

      %WatcherInfo{} ->
        # Already running
        {:reply, {:ok, :already_running}, state}
    end
  end

  def handle_call({:stop_watcher, project_id}, _from, state) do
    case Map.get(state.watchers, project_id) do
      %WatcherInfo{} ->
        state = do_stop_watcher(project_id, state, :manual)
        {:reply, :ok, state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:get_info, project_id}, _from, state) do
    case Map.get(state.watchers, project_id) do
      %WatcherInfo{} = info ->
        {:reply, {:ok, info}, state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:get_stats, _from, state) do
    uptime =
      if state.stats.start_time do
        DateTime.diff(DateTime.utc_now(), state.stats.start_time)
      else
        0
      end

    stats = %{
      active_watchers: map_size(state.watchers),
      queued_requests: :queue.len(state.queue),
      total_started: state.stats.total_started,
      total_evicted: state.stats.total_evicted,
      total_stopped: state.stats.total_stopped,
      uptime_seconds: uptime,
      max_watchers: state.max_watchers
    }

    {:reply, stats, state}
  end

  def handle_call(:list_watchers, _from, state) do
    watchers =
      Map.values(state.watchers)
      |> Enum.sort_by(& &1.last_activity, {:desc, DateTime})

    {:reply, watchers, state}
  end

  @impl true
  def handle_cast({:touch_activity, project_id}, state) do
    state =
      case Map.get(state.watchers, project_id) do
        %WatcherInfo{} = info ->
          updated_info = %{info | last_activity: DateTime.utc_now(), event_count: info.event_count + 1}
          put_in(state.watchers[project_id], updated_info)

        nil ->
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_timer, state) do
    state = perform_cleanup(state)
    state = schedule_cleanup(state)
    {:noreply, state}
  end

  def handle_info({:process_queue_timeout, from}, state) do
    # Timeout waiting in queue
    GenServer.reply(from, {:error, :queue_timeout})

    # Remove from queue
    queue = :queue.filter(fn {_project_id, _opts, f, _timer_ref} -> f != from end, state.queue)
    state = %{state | queue: queue}

    emit_telemetry(:queue_timeout, %{queue_length: :queue.len(queue)})

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # A watcher process died
    state =
      case find_watcher_by_pid(state.watchers, pid) do
        {project_id, _info} ->
          Logger.warning("Watcher for project #{project_id} died unexpectedly")
          remove_watcher(project_id, state)

        nil ->
          state
      end

    # Try to process queue
    state = process_queue(state)

    {:noreply, state}
  end

  # Private functions

  defp start_watcher_immediate(project_id, opts, _from, state) do
    case FWSupervisor.start_watcher(project_id, opts) do
      {:ok, pid} ->
        Process.monitor(pid)

        info = %WatcherInfo{
          project_id: project_id,
          pid: pid,
          started_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now(),
          event_count: 0,
          subscriber_count: 0,
          priority: opts[:priority] || :normal,
          root_path: opts.root_path
        }

        state = put_in(state.watchers[project_id], info)
        state = update_in(state.stats.total_started, &(&1 + 1))

        emit_telemetry(:watcher_started, %{project_id: project_id})

        {:reply, {:ok, :started}, state}

      {:error, {:already_started, pid}} ->
        # The watcher was already started (race condition)
        # Add it to our tracking
        info = %WatcherInfo{
          project_id: project_id,
          pid: pid,
          started_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now(),
          event_count: 0,
          subscriber_count: 0,
          priority: opts[:priority] || :normal,
          root_path: opts.root_path
        }

        state = put_in(state.watchers[project_id], info)
        {:reply, {:ok, :started}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp handle_at_capacity(project_id, opts, from, state) do
    # Try LRU eviction for low priority requests
    if opts[:priority] == :high || !can_evict?(state) do
      # Queue the request
      state = queue_request(project_id, opts, from, state)
      {:reply, {:ok, :queued}, state}
    else
      # Evict LRU and start new watcher
      state = evict_lru(state)
      start_watcher_immediate(project_id, opts, from, state)
    end
  end

  defp can_evict?(state) do
    # Only evict if we have watchers older than 5 minutes
    threshold = DateTime.add(DateTime.utc_now(), -300, :second)

    Enum.any?(state.watchers, fn {_id, info} ->
      DateTime.compare(info.last_activity, threshold) == :lt
    end)
  end

  defp evict_lru(state) do
    # Find least recently used watcher
    {project_id, _info} =
      state.watchers
      |> Enum.min_by(fn {_id, info} -> info.last_activity end, DateTime)

    Logger.info("Evicting LRU watcher for project #{project_id}")

    state = do_stop_watcher(project_id, state, :evicted)
    update_in(state.stats.total_evicted, &(&1 + 1))
  end

  defp queue_request(project_id, opts, from, state) do
    # Add to queue with timeout
    timer_ref = Process.send_after(self(), {:process_queue_timeout, from}, state.queue_timeout_ms)

    queue_item = {project_id, opts, from, timer_ref}
    queue = :queue.in(queue_item, state.queue)

    state = %{state | queue: queue}

    emit_telemetry(:request_queued, %{
      project_id: project_id,
      queue_length: :queue.len(queue)
    })

    # Return the updated state
    state
  end

  defp process_queue(state) do
    case :queue.out(state.queue) do
      {{:value, {project_id, opts, from, timer_ref}}, queue} ->
        Process.cancel_timer(timer_ref)

        state = %{state | queue: queue}

        # Try to start the queued watcher
        case FWSupervisor.start_watcher(project_id, opts) do
          {:ok, pid} ->
            Process.monitor(pid)

            info = %WatcherInfo{
              project_id: project_id,
              pid: pid,
              started_at: DateTime.utc_now(),
              last_activity: DateTime.utc_now(),
              event_count: 0,
              subscriber_count: 0,
              priority: opts[:priority] || :normal,
              root_path: opts.root_path
            }

            state = put_in(state.watchers[project_id], info)
            state = update_in(state.stats.total_started, &(&1 + 1))

            # Reply to the waiting caller
            GenServer.reply(from, {:ok, :started})

            emit_telemetry(:watcher_started, %{project_id: project_id})

            state

          {:error, {:already_started, pid}} ->
            # The watcher was already started (race condition)
            info = %WatcherInfo{
              project_id: project_id,
              pid: pid,
              started_at: DateTime.utc_now(),
              last_activity: DateTime.utc_now(),
              event_count: 0,
              subscriber_count: 0,
              priority: opts[:priority] || :normal,
              root_path: opts.root_path
            }

            state = put_in(state.watchers[project_id], info)
            GenServer.reply(from, {:ok, :started})
            state

          {:error, reason} ->
            GenServer.reply(from, {:error, reason})
            # Try next in queue
            process_queue(state)
        end

      {:empty, _} ->
        state
    end
  end

  defp do_stop_watcher(project_id, state, reason) do
    case Map.get(state.watchers, project_id) do
      %WatcherInfo{} ->
        FWSupervisor.stop_watcher(project_id)

        emit_telemetry(:watcher_stopped, %{
          project_id: project_id,
          reason: reason
        })

        state = update_in(state.watchers, &Map.delete(&1, project_id))

        if reason == :manual do
          update_in(state.stats.total_stopped, &(&1 + 1))
        else
          state
        end

      nil ->
        state
    end
  end

  defp remove_watcher(project_id, state) do
    update_in(state.watchers, &Map.delete(&1, project_id))
  end

  defp find_watcher_by_pid(watchers, pid) do
    Enum.find(watchers, fn {_id, info} -> info.pid == pid end)
  end

  defp schedule_cleanup(state) do
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end

    timer =
      Process.send_after(
        self(),
        :cleanup_timer,
        state.cleanup_interval_minutes * 60 * 1000
      )

    %{state | cleanup_timer: timer}
  end

  defp perform_cleanup(state) do
    cutoff =
      DateTime.add(
        DateTime.utc_now(),
        -state.inactive_timeout_minutes * 60,
        :second
      )

    inactive_projects =
      state.watchers
      |> Enum.filter(fn {_id, info} ->
        DateTime.compare(info.last_activity, cutoff) == :lt
      end)
      |> Enum.map(fn {id, _} -> id end)

    state =
      Enum.reduce(inactive_projects, state, fn project_id, acc ->
        Logger.info("Cleaning up inactive watcher for project #{project_id}")
        do_stop_watcher(project_id, acc, :inactive)
      end)

    if length(inactive_projects) > 0 do
      emit_telemetry(:cleanup_completed, %{
        cleaned_count: length(inactive_projects),
        remaining_count: map_size(state.watchers)
      })
    end

    # Process any queued requests
    process_queue(state)
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:rubber_duck, :watcher_manager, event],
      %{count: 1},
      metadata
    )
  end
end


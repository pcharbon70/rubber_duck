defmodule RubberDuck.DistributedLock do
  use GenServer
  require Logger

  @moduledoc """
  Provides distributed locking mechanisms using Mnesia's global locks and
  timeout-based lease management. Ensures critical sections are properly
  coordinated across cluster nodes.
  """

  defstruct [
    :locks,
    :leases,
    :cleanup_interval
  ]

  @cleanup_interval 30_000
  @default_lease_timeout 60_000
  @lock_table :distributed_locks

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Acquire a distributed lock with optional timeout
  """
  def acquire_lock(lock_name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    lease_duration = Keyword.get(opts, :lease_duration, @default_lease_timeout)
    
    GenServer.call(__MODULE__, {:acquire_lock, lock_name, lease_duration}, timeout)
  end

  @doc """
  Release a distributed lock
  """
  def release_lock(lock_name) do
    GenServer.call(__MODULE__, {:release_lock, lock_name})
  end

  @doc """
  Execute a function while holding a distributed lock
  """
  def with_lock(lock_name, fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    lease_duration = Keyword.get(opts, :lease_duration, @default_lease_timeout)
    
    case acquire_lock(lock_name, timeout: timeout, lease_duration: lease_duration) do
      {:ok, lock_token} ->
        try do
          result = fun.()
          release_lock(lock_name)
          {:ok, result}
        rescue
          error ->
            release_lock(lock_name)
            {:error, {:function_error, error}}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get information about current locks
  """
  def list_locks do
    GenServer.call(__MODULE__, :list_locks)
  end

  @doc """
  Check if a lock is currently held
  """
  def lock_held?(lock_name) do
    GenServer.call(__MODULE__, {:lock_held, lock_name})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create locks table if it doesn't exist
    create_lock_table()
    
    # Schedule periodic cleanup
    schedule_cleanup()

    state = %__MODULE__{
      locks: %{},
      leases: %{},
      cleanup_interval: @cleanup_interval
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:acquire_lock, lock_name, lease_duration}, {pid, _tag}, state) do
    case try_acquire_global_lock(lock_name, pid, lease_duration) do
      {:ok, lock_token} ->
        # Monitor the requesting process
        Process.monitor(pid)
        
        # Update local state
        new_locks = Map.put(state.locks, lock_name, %{
          token: lock_token,
          holder: pid,
          acquired_at: System.system_time(:millisecond),
          lease_expires_at: System.system_time(:millisecond) + lease_duration
        })
        
        {:reply, {:ok, lock_token}, %{state | locks: new_locks}}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:release_lock, lock_name}, {pid, _tag}, state) do
    case Map.get(state.locks, lock_name) do
      %{holder: ^pid} = lock_info ->
        case release_global_lock(lock_name, lock_info.token) do
          :ok ->
            new_locks = Map.delete(state.locks, lock_name)
            {:reply, :ok, %{state | locks: new_locks}}
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      
      %{holder: other_pid} ->
        Logger.warning("Process #{inspect(pid)} attempted to release lock held by #{inspect(other_pid)}")
        {:reply, {:error, :not_owner}, state}
      
      nil ->
        {:reply, {:error, :not_held}, state}
    end
  end

  @impl true
  def handle_call(:list_locks, _from, state) do
    locks_info = Enum.map(state.locks, fn {name, info} ->
      %{
        name: name,
        holder: info.holder,
        acquired_at: info.acquired_at,
        expires_at: info.lease_expires_at,
        node: node()
      }
    end)
    
    {:reply, locks_info, state}
  end

  @impl true
  def handle_call({:lock_held, lock_name}, _from, state) do
    held = Map.has_key?(state.locks, lock_name)
    {:reply, held, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Process holding locks has died, release them
    expired_locks = Enum.filter(state.locks, fn {_name, info} -> 
      info.holder == pid 
    end)
    
    Enum.each(expired_locks, fn {lock_name, lock_info} ->
      Logger.info("Releasing lock #{lock_name} due to process death")
      release_global_lock(lock_name, lock_info.token)
    end)
    
    new_locks = Enum.reduce(expired_locks, state.locks, fn {lock_name, _}, acc ->
      Map.delete(acc, lock_name)
    end)
    
    {:noreply, %{state | locks: new_locks}}
  end

  @impl true
  def handle_info(:cleanup_expired_locks, state) do
    current_time = System.system_time(:millisecond)
    
    {expired_locks, valid_locks} = Enum.split_with(state.locks, fn {_name, info} ->
      info.lease_expires_at < current_time
    end)
    
    # Release expired locks
    Enum.each(expired_locks, fn {lock_name, lock_info} ->
      Logger.info("Releasing expired lock: #{lock_name}")
      release_global_lock(lock_name, lock_info.token)
    end)
    
    # Clean up global lock table
    cleanup_global_lock_table()
    
    # Schedule next cleanup
    schedule_cleanup()
    
    {:noreply, %{state | locks: Map.new(valid_locks)}}
  end

  # Private Functions

  defp create_lock_table do
    case :mnesia.create_table(@lock_table, [
      attributes: [:lock_name, :holder_node, :holder_pid, :token, :acquired_at, :expires_at],
      type: :set,
      ram_copies: [node() | Node.list()]
    ]) do
      {:atomic, :ok} -> 
        Logger.debug("Created distributed locks table")
      {:aborted, {:already_exists, @lock_table}} -> 
        :ok
      {:aborted, reason} ->
        Logger.error("Failed to create locks table: #{inspect(reason)}")
    end
  end

  defp try_acquire_global_lock(lock_name, holder_pid, lease_duration) do
    expires_at = System.system_time(:millisecond) + lease_duration
    token = generate_lock_token()
    
    transaction_fun = fn ->
      case :mnesia.read(@lock_table, lock_name) do
        [] ->
          # Lock is available
          lock_record = {@lock_table, lock_name, node(), holder_pid, token, 
                        System.system_time(:millisecond), expires_at}
          :mnesia.write(lock_record)
          {:ok, token}
        
        [{@lock_table, ^lock_name, _holder_node, _holder_pid, _token, _acquired_at, lock_expires_at}] ->
          current_time = System.system_time(:millisecond)
          if lock_expires_at < current_time do
            # Lock has expired, we can take it
            lock_record = {@lock_table, lock_name, node(), holder_pid, token, 
                          current_time, expires_at}
            :mnesia.write(lock_record)
            {:ok, token}
          else
            # Lock is still held
            {:error, :already_held}
          end
      end
    end

    case :mnesia.transaction(transaction_fun) do
      {:atomic, result} -> result
      {:aborted, reason} -> {:error, {:transaction_failed, reason}}
    end
  end

  defp release_global_lock(lock_name, expected_token) do
    transaction_fun = fn ->
      case :mnesia.read(@lock_table, lock_name) do
        [{@lock_table, ^lock_name, holder_node, _holder_pid, ^expected_token, _acquired_at, _expires_at}] 
        when holder_node == node() ->
          :mnesia.delete({@lock_table, lock_name})
          :ok
        
        [{@lock_table, ^lock_name, _holder_node, _holder_pid, different_token, _acquired_at, _expires_at}] ->
          Logger.warning("Lock token mismatch for #{lock_name}: expected #{expected_token}, found #{different_token}")
          {:error, :token_mismatch}
        
        [] ->
          # Lock already released
          :ok
      end
    end

    case :mnesia.transaction(transaction_fun) do
      {:atomic, result} -> result
      {:aborted, reason} -> {:error, {:transaction_failed, reason}}
    end
  end

  defp cleanup_global_lock_table do
    current_time = System.system_time(:millisecond)
    
    transaction_fun = fn ->
      # Find all expired locks
      expired_locks = :mnesia.select(@lock_table, [
        {
          {@lock_table, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6"},
          [{:<, :"$6", current_time}],
          [:"$1"]
        }
      ])
      
      # Delete expired locks
      Enum.each(expired_locks, fn lock_name ->
        :mnesia.delete({@lock_table, lock_name})
      end)
      
      length(expired_locks)
    end

    case :mnesia.transaction(transaction_fun) do
      {:atomic, count} when count > 0 ->
        Logger.debug("Cleaned up #{count} expired locks from global table")
      _ ->
        :ok
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired_locks, @cleanup_interval)
  end

  defp generate_lock_token do
    :crypto.strong_rand_bytes(16) |> Base.encode64()
  end
end
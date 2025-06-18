defmodule RubberDuck.ConflictResolver do
  require Logger

  @moduledoc """
  Handles conflict resolution for concurrent updates in the distributed system.
  Provides multiple resolution strategies including last-writer-wins, merge-based
  resolution, and manual resolution queuing for complex conflicts.
  """

  defstruct [
    :strategy,
    :pending_conflicts,
    :resolution_history,
    :custom_resolvers
  ]


  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(_opts) do
    # This module doesn't need a process, it's just utility functions
    :ignore
  end

  @doc """
  Resolve a conflict between two versions of a record
  """
  def resolve_conflict(table, local_record, remote_record, strategy \\ :last_writer_wins) do
    case strategy do
      :last_writer_wins ->
        resolve_last_writer_wins(local_record, remote_record)
      :merge_compatible ->
        resolve_merge_compatible(table, local_record, remote_record)
      :manual_review ->
        queue_for_manual_resolution(table, local_record, remote_record)
      :custom ->
        resolve_with_custom_logic(table, local_record, remote_record)
    end
  end

  @doc """
  Detect conflicts between two records
  """
  def detect_conflict(local_record, remote_record) do
    case {local_record, remote_record} do
      {nil, remote} -> {:no_conflict, remote}
      {local, nil} -> {:no_conflict, local}
      {local, remote} when local == remote -> {:no_conflict, local}
      {local, remote} -> 
        conflict_type = analyze_conflict_type(local, remote)
        {:conflict, conflict_type, local, remote}
    end
  end

  @doc """
  Register a custom resolver for a specific table or record type
  """
  def register_custom_resolver(table, resolver_fun) when is_function(resolver_fun, 2) do
    Agent.update(__MODULE__, fn state ->
      custom_resolvers = Map.put(state.custom_resolvers, table, resolver_fun)
      %{state | custom_resolvers: custom_resolvers}
    end)
  end

  @doc """
  Get pending conflicts that require manual resolution
  """
  def get_pending_conflicts do
    Agent.get(__MODULE__, fn state -> state.pending_conflicts end)
  end

  @doc """
  Manually resolve a pending conflict
  """
  def resolve_pending_conflict(conflict_id, resolution) do
    Agent.update(__MODULE__, fn state ->
      case Map.pop(state.pending_conflicts, conflict_id) do
        {nil, _} ->
          state
        {conflict, updated_pending} ->
          # Record the resolution
          history_entry = %{
            conflict_id: conflict_id,
            conflict: conflict,
            resolution: resolution,
            resolved_at: DateTime.utc_now(),
            resolved_by: :manual
          }
          
          updated_history = [history_entry | state.resolution_history]
          
          %{state | 
            pending_conflicts: updated_pending,
            resolution_history: updated_history
          }
      end
    end)
  end


  # Private Functions

  defp resolve_last_writer_wins(local_record, remote_record) do
    local_timestamp = get_record_timestamp(local_record)
    remote_timestamp = get_record_timestamp(remote_record)

    resolution = cond do
      local_timestamp > remote_timestamp ->
        {:resolved, local_record, :local_newer}
      remote_timestamp > local_timestamp ->
        {:resolved, remote_record, :remote_newer}
      true ->
        # Same timestamp, use node name as tiebreaker
        local_node = get_record_node(local_record)
        remote_node = get_record_node(remote_record)
        
        if local_node > remote_node do
          {:resolved, local_record, :tiebreaker_local}
        else
          {:resolved, remote_record, :tiebreaker_remote}
        end
    end

    log_resolution(local_record, remote_record, resolution)
    resolution
  end

  defp resolve_merge_compatible(table, local_record, remote_record) do
    case table do
      :sessions -> merge_session_records(local_record, remote_record)
      :models -> merge_model_records(local_record, remote_record)
      :model_stats -> merge_stats_records(local_record, remote_record)
      _ -> resolve_last_writer_wins(local_record, remote_record)
    end
  end

  defp merge_session_records(local, remote) do
    # Sessions can merge messages if they don't overlap
    local_messages = get_record_field(local, :messages) || []
    remote_messages = get_record_field(remote, :messages) || []
    
    # Simple merge - combine unique messages by timestamp
    merged_messages = Enum.uniq_by(local_messages ++ remote_messages, fn msg ->
      Map.get(msg, :timestamp, 0)
    end)
    |> Enum.sort_by(fn msg -> Map.get(msg, :timestamp, 0) end)

    # Use most recent metadata
    local_updated = get_record_field(local, :updated_at)
    remote_updated = get_record_field(remote, :updated_at)
    
    {newer_record, metadata_source} = if local_updated > remote_updated do
      {local, :local}
    else
      {remote, :remote}
    end

    merged_record = set_record_field(newer_record, :messages, merged_messages)
    
    {:resolved, merged_record, {:merged, metadata_source}}
  end

  defp merge_model_records(local, remote) do
    # Models are harder to merge - check if only health status differs
    local_health = get_record_field(local, :health_status)
    remote_health = get_record_field(remote, :health_status)
    
    # Remove health fields for comparison
    local_without_health = remove_health_fields(local)
    remote_without_health = remove_health_fields(remote)
    
    if local_without_health == remote_without_health do
      # Only health differs, use most recent health check
      local_timestamp = get_record_timestamp(local)
      remote_timestamp = get_record_timestamp(remote)
      
      if local_timestamp > remote_timestamp do
        {:resolved, local, :health_merged_local}
      else
        {:resolved, remote, :health_merged_remote}
      end
    else
      # Structural differences, fall back to last writer wins
      resolve_last_writer_wins(local, remote)
    end
  end

  defp merge_stats_records(local, remote) do
    # Stats can be merged by combining counters
    local_success = get_record_field(local, :success_count) || 0
    remote_success = get_record_field(remote, :success_count) || 0
    
    local_failure = get_record_field(local, :failure_count) || 0
    remote_failure = get_record_field(remote, :failure_count) || 0
    
    local_latency = get_record_field(local, :total_latency) || 0
    remote_latency = get_record_field(remote, :total_latency) || 0
    
    # Merge the stats
    merged_success = local_success + remote_success
    merged_failure = local_failure + remote_failure
    merged_latency = local_latency + remote_latency
    merged_avg = if merged_success > 0 do
      merged_latency / merged_success
    else
      0
    end

    # Use the structure from the more recent record
    base_record = if get_record_timestamp(local) > get_record_timestamp(remote) do
      local
    else
      remote
    end

    merged_record = base_record
    |> set_record_field(:success_count, merged_success)
    |> set_record_field(:failure_count, merged_failure)
    |> set_record_field(:total_latency, merged_latency)
    |> set_record_field(:average_latency, merged_avg)
    |> set_record_field(:last_updated, DateTime.utc_now())

    {:resolved, merged_record, :stats_merged}
  end

  defp queue_for_manual_resolution(table, local_record, remote_record) do
    conflict_id = generate_conflict_id()
    
    conflict = %{
      id: conflict_id,
      table: table,
      local_record: local_record,
      remote_record: remote_record,
      detected_at: DateTime.utc_now(),
      conflict_type: analyze_conflict_type(local_record, remote_record)
    }

    Agent.update(__MODULE__, fn state ->
      updated_pending = Map.put(state.pending_conflicts, conflict_id, conflict)
      %{state | pending_conflicts: updated_pending}
    end)

    Logger.warning("Conflict queued for manual resolution: #{conflict_id}")
    {:manual_required, conflict_id, conflict}
  end

  defp resolve_with_custom_logic(table, local_record, remote_record) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.custom_resolvers, table) end) do
      nil ->
        Logger.warning("No custom resolver for table #{table}, falling back to last_writer_wins")
        resolve_last_writer_wins(local_record, remote_record)
      resolver_fun ->
        try do
          result = resolver_fun.(local_record, remote_record)
          log_resolution(local_record, remote_record, result)
          result
        rescue
          error ->
            Logger.error("Custom resolver failed: #{inspect(error)}")
            resolve_last_writer_wins(local_record, remote_record)
        end
    end
  end

  defp analyze_conflict_type(local, remote) do
    cond do
      record_fields_differ?(local, remote, [:updated_at, :last_seen]) ->
        :timestamp_only
      record_fields_differ?(local, remote, [:health_status, :health_reason]) ->
        :health_only
      structural_difference?(local, remote) ->
        :structural
      true ->
        :unknown
    end
  end

  defp record_fields_differ?(local, remote, fields) do
    local_others = remove_fields(local, fields)
    remote_others = remove_fields(remote, fields)
    local_others == remote_others
  end

  defp structural_difference?(local, remote) do
    # Check if the core structure differs significantly
    essential_fields = [:session_id, :name, :type, :endpoint, :capabilities]
    
    Enum.any?(essential_fields, fn field ->
      get_record_field(local, field) != get_record_field(remote, field)
    end)
  end

  defp get_record_timestamp(record) do
    case record do
      tuple when is_tuple(tuple) ->
        # Extract timestamp based on table type
        case elem(tuple, 0) do
          :sessions -> elem(tuple, 5)  # updated_at
          :models -> elem(tuple, 7)    # registered_at
          _ -> System.system_time(:microsecond)
        end
      map when is_map(map) ->
        Map.get(map, :updated_at, Map.get(map, :registered_at, System.system_time(:microsecond)))
      _ ->
        System.system_time(:microsecond)
    end
  end

  defp get_record_node(record) do
    case record do
      tuple when is_tuple(tuple) ->
        tuple_size = tuple_size(tuple)
        if tuple_size > 1, do: elem(tuple, tuple_size - 1), else: node()
      map when is_map(map) ->
        Map.get(map, :node, node())
      _ ->
        node()
    end
  end

  defp get_record_field(record, field) do
    case record do
      tuple when is_tuple(tuple) ->
        # This would need table schema information for robust implementation
        nil
      map when is_map(map) ->
        Map.get(map, field)
      _ ->
        nil
    end
  end

  defp set_record_field(record, field, value) do
    case record do
      tuple when is_tuple(tuple) ->
        # This would need table schema information for robust implementation
        record
      map when is_map(map) ->
        Map.put(map, field, value)
      _ ->
        record
    end
  end

  defp remove_health_fields(record) do
    remove_fields(record, [:health_status, :health_reason])
  end

  defp remove_fields(record, fields) do
    case record do
      tuple when is_tuple(tuple) ->
        # For tuples, this would need schema info
        record
      map when is_map(map) ->
        Map.drop(map, fields)
      _ ->
        record
    end
  end

  defp generate_conflict_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end

  defp log_resolution(local_record, remote_record, resolution) do
    Logger.debug("Conflict resolved: #{inspect(resolution)}")
    
    # Record in resolution history
    Agent.update(__MODULE__, fn state ->
      history_entry = %{
        local_record: local_record,
        remote_record: remote_record,
        resolution: resolution,
        resolved_at: DateTime.utc_now(),
        resolved_by: :automatic
      }
      
      updated_history = [history_entry | Enum.take(state.resolution_history, 999)]
      %{state | resolution_history: updated_history}
    end)
  end
end
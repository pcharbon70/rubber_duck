defmodule RubberDuck.Memory.MemoryVersion do
  @moduledoc """
  Data structure for tracking memory versions and changes over time.
  
  This module provides version control capabilities for memory entries,
  including change tracking, diff generation, and rollback support.
  Each version captures what changed, when, why, and by whom.
  """

  defstruct [
    :id,
    :memory_id,
    :version,
    :previous_version,
    :changes,
    :change_type,
    :author,
    :reason,
    :metadata,
    :created_at,
    :size_bytes
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    memory_id: String.t(),
    version: integer(),
    previous_version: integer() | nil,
    changes: map(),
    change_type: change_type(),
    author: String.t(),
    reason: String.t(),
    metadata: map(),
    created_at: DateTime.t(),
    size_bytes: integer()
  }

  @type change_type :: :create | :update | :delete | :restore | :merge
  
  @type change :: %{
    field: String.t(),
    old: any(),
    new: any(),
    operation: :set | :add | :remove | :merge
  }

  @doc """
  Creates a new version record for a memory.
  """
  def new(attrs) do
    changes = attrs[:changes] || %{}
    
    version = %__MODULE__{
      id: generate_id(),
      memory_id: attrs[:memory_id],
      version: attrs[:version],
      previous_version: attrs[:previous_version],
      changes: changes,
      change_type: attrs[:change_type] || :update,
      author: attrs[:author] || "system",
      reason: attrs[:reason] || "Update",
      metadata: attrs[:metadata] || %{},
      created_at: DateTime.utc_now(),
      size_bytes: 0
    }
    
    %{version | size_bytes: calculate_size(version)}
  end

  @doc """
  Creates a version from comparing two memory states.
  """
  def from_diff(old_memory, new_memory, author, reason) do
    changes = generate_diff(old_memory, new_memory)
    
    new(%{
      memory_id: new_memory.id,
      version: new_memory.version,
      previous_version: old_memory.version,
      changes: changes,
      change_type: determine_change_type(old_memory, new_memory),
      author: author,
      reason: reason
    })
  end

  @doc """
  Applies version changes to a memory to recreate a specific version.
  """
  def apply_to_memory(version, memory) do
    Enum.reduce(version.changes, memory, fn {field, change}, acc ->
      apply_change(acc, field, change)
    end)
  end

  @doc """
  Reverts the changes in this version (for rollback).
  """
  def revert(version, memory) do
    Enum.reduce(version.changes, memory, fn {field, change}, acc ->
      revert_change(acc, field, change)
    end)
  end

  @doc """
  Merges multiple versions into a single consolidated version.
  """
  def merge_versions(versions, author \\ "system") do
    # Sort versions by version number
    sorted = Enum.sort_by(versions, & &1.version)
    
    # Merge all changes
    merged_changes = Enum.reduce(sorted, %{}, fn version, acc ->
      Map.merge(acc, version.changes, fn _k, old_change, new_change ->
        merge_changes(old_change, new_change)
      end)
    end)
    
    # Create merged version
    first_version = List.first(sorted)
    last_version = List.last(sorted)
    
    new(%{
      memory_id: first_version.memory_id,
      version: last_version.version,
      previous_version: first_version.previous_version,
      changes: merged_changes,
      change_type: :merge,
      author: author,
      reason: "Merged versions #{first_version.version} to #{last_version.version}",
      metadata: %{
        merged_versions: Enum.map(versions, & &1.id),
        original_authors: Enum.map(versions, & &1.author) |> Enum.uniq()
      }
    })
  end

  @doc """
  Checks if a version can be safely applied to a memory.
  """
  def compatible?(version, memory) do
    # Check if the version's previous_version matches the memory's current version
    version.previous_version == nil or version.previous_version == memory.version
  end

  @doc """
  Returns a human-readable summary of the changes.
  """
  def summary(version) do
    field_count = map_size(version.changes)
    
    %{
      version: version.version,
      change_type: version.change_type,
      fields_changed: field_count,
      author: version.author,
      reason: version.reason,
      created_at: version.created_at,
      size_bytes: version.size_bytes
    }
  end

  @doc """
  Generates a detailed change report.
  """
  def change_report(version) do
    changes = Enum.map(version.changes, fn {field, change} ->
      describe_change(field, change)
    end)
    
    %{
      memory_id: version.memory_id,
      version: version.version,
      previous_version: version.previous_version,
      change_type: version.change_type,
      author: version.author,
      reason: version.reason,
      created_at: version.created_at,
      changes: changes
    }
  end

  @doc """
  Compresses a version for storage efficiency.
  """
  def compress(version) do
    compressed_changes = :zlib.compress(:erlang.term_to_binary(version.changes))
    
    %{version | 
      changes: Base.encode64(compressed_changes),
      metadata: Map.put(version.metadata, :compressed, true)
    }
  end

  @doc """
  Decompresses a compressed version.
  """
  def decompress(version) do
    if Map.get(version.metadata, :compressed) do
      decompressed = Base.decode64!(version.changes)
      changes = :erlang.binary_to_term(:zlib.uncompress(decompressed))
      
      %{version | 
        changes: changes,
        metadata: Map.delete(version.metadata, :compressed)
      }
    else
      version
    end
  end

  # Private functions

  defp generate_id do
    "ver_" <> :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  defp generate_diff(old_memory, new_memory) do
    old_map = memory_to_map(old_memory)
    new_map = memory_to_map(new_memory)
    
    all_keys = MapSet.union(MapSet.new(Map.keys(old_map)), MapSet.new(Map.keys(new_map)))
    
    Enum.reduce(all_keys, %{}, fn key, acc ->
      old_value = Map.get(old_map, key)
      new_value = Map.get(new_map, key)
      
      cond do
        old_value == new_value ->
          # No change
          acc
          
        old_value == nil ->
          # Field added
          Map.put(acc, key, %{
            old: nil,
            new: new_value,
            operation: :add
          })
          
        new_value == nil ->
          # Field removed
          Map.put(acc, key, %{
            old: old_value,
            new: nil,
            operation: :remove
          })
          
        true ->
          # Field changed
          Map.put(acc, key, %{
            old: old_value,
            new: new_value,
            operation: :set
          })
      end
    end)
  end

  defp memory_to_map(memory) do
    # Convert memory to map for diffing, excluding system fields
    memory
    |> Map.from_struct()
    |> Map.drop([:id, :created_at, :updated_at, :version])
  end

  defp determine_change_type(nil, _new), do: :create
  defp determine_change_type(_old, new) do
    if new.deleted_at != nil, do: :delete, else: :update
  end

  defp apply_change(memory, field, %{operation: :set, new: value}) do
    Map.put(memory, String.to_atom(field), value)
  end

  defp apply_change(memory, field, %{operation: :add, new: value}) do
    Map.put(memory, String.to_atom(field), value)
  end

  defp apply_change(memory, field, %{operation: :remove}) do
    Map.delete(memory, String.to_atom(field))
  end

  defp apply_change(memory, field, %{operation: :merge, new: value}) do
    atom_field = String.to_atom(field)
    existing = Map.get(memory, atom_field, %{})
    
    merged = case {existing, value} do
      {map1, map2} when is_map(map1) and is_map(map2) ->
        Map.merge(map1, map2)
      {list1, list2} when is_list(list1) and is_list(list2) ->
        list1 ++ list2
      _ ->
        value
    end
    
    Map.put(memory, atom_field, merged)
  end

  defp revert_change(memory, field, %{operation: :set, old: value}) do
    if value == nil do
      Map.delete(memory, String.to_atom(field))
    else
      Map.put(memory, String.to_atom(field), value)
    end
  end

  defp revert_change(memory, field, %{operation: :add}) do
    Map.delete(memory, String.to_atom(field))
  end

  defp revert_change(memory, field, %{operation: :remove, old: value}) do
    Map.put(memory, String.to_atom(field), value)
  end

  defp revert_change(memory, field, change) do
    # For merge operations, just set the old value
    revert_change(memory, field, %{change | operation: :set})
  end

  defp merge_changes(old_change, new_change) do
    # When merging changes, the newer change takes precedence
    # but we keep the original old value
    %{
      old: old_change.old,
      new: new_change.new,
      operation: determine_merge_operation(old_change, new_change)
    }
  end

  defp determine_merge_operation(old_change, new_change) do
    case {old_change.operation, new_change.operation} do
      {:add, :remove} -> :remove
      {:remove, :add} -> :set
      {_, :remove} -> :remove
      {_, op} -> op
    end
  end

  defp describe_change(field, %{operation: op, old: old, new: new}) do
    case op do
      :add -> "Added #{field}: #{inspect(new)}"
      :remove -> "Removed #{field} (was: #{inspect(old)})"
      :set -> "Changed #{field} from #{inspect(old)} to #{inspect(new)}"
      :merge -> "Merged #{field}: #{inspect(old)} + #{inspect(new)}"
    end
  end

  defp calculate_size(version) do
    :erlang.term_to_binary(version.changes) |> byte_size()
  end
end
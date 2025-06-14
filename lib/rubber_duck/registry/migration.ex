defmodule RubberDuck.Registry.Migration do
  @moduledoc """
  Migration utilities for transitioning from local Registry to global Syn registry.
  Provides tools to migrate existing processes and update registration patterns
  across the distributed system.
  """
  require Logger

  alias RubberDuck.Registry.{GlobalRegistry, SessionRegistry, ModelRegistry}

  @doc """
  Migrates all processes from local Registry to global Syn registry.
  """
  def migrate_to_global_registry do
    Logger.info("Starting migration from local Registry to global Syn registry")
    
    # Get all processes from local registry
    local_processes = get_local_registry_processes()
    
    migration_results = Enum.map(local_processes, fn {key, pid, value} ->
      migrate_single_process(key, pid, value)
    end)
    
    # Summarize results
    successful = Enum.count(migration_results, &match?({:ok, _}, &1))
    failed = Enum.count(migration_results, &match?({:error, _}, &1))
    
    Logger.info("Migration completed: #{successful} successful, #{failed} failed")
    
    %{
      total: length(migration_results),
      successful: successful,
      failed: failed,
      results: migration_results
    }
  end

  @doc """
  Migrates sessions specifically to the new SessionRegistry pattern.
  """
  def migrate_sessions do
    Logger.info("Migrating sessions to SessionRegistry")
    
    session_processes = find_session_processes()
    
    migration_results = Enum.map(session_processes, fn {session_id, pid} ->
      migrate_session(session_id, pid)
    end)
    
    successful = Enum.count(migration_results, &match?({:ok, _}, &1))
    Logger.info("Session migration completed: #{successful}/#{length(migration_results)} successful")
    
    migration_results
  end

  @doc """
  Migrates model processes to the new ModelRegistry pattern.
  """
  def migrate_models do
    Logger.info("Migrating models to ModelRegistry")
    
    model_processes = find_model_processes()
    
    migration_results = Enum.map(model_processes, fn {model_id, pid, config} ->
      migrate_model(model_id, pid, config)
    end)
    
    successful = Enum.count(migration_results, &match?({:ok, _}, &1))
    Logger.info("Model migration completed: #{successful}/#{length(migration_results)} successful")
    
    migration_results
  end

  @doc """
  Validates that all processes have been successfully migrated.
  """
  def validate_migration do
    Logger.info("Validating migration to global registry")
    
    # Check local registry
    remaining_local = get_local_registry_processes()
    
    # Check global registry
    global_processes = GlobalRegistry.list_processes()
    
    validation_results = %{
      remaining_local_processes: length(remaining_local),
      global_processes: length(global_processes),
      migration_complete: length(remaining_local) == 0,
      details: %{
        local_processes: remaining_local,
        global_processes: summarize_global_processes(global_processes)
      }
    }
    
    if validation_results.migration_complete do
      Logger.info("Migration validation successful: all processes migrated")
    else
      Logger.warn("Migration validation found #{length(remaining_local)} remaining local processes")
    end
    
    validation_results
  end

  @doc """
  Provides rollback functionality in case migration needs to be reversed.
  """
  def rollback_migration do
    Logger.warn("Rolling back migration to local Registry")
    
    global_processes = GlobalRegistry.list_processes()
    
    rollback_results = Enum.map(global_processes, fn {name, pid, metadata} ->
      rollback_single_process(name, pid, metadata)
    end)
    
    successful = Enum.count(rollback_results, &match?({:ok, _}, &1))
    Logger.info("Rollback completed: #{successful}/#{length(rollback_results)} successful")
    
    rollback_results
  end

  @doc """
  Updates existing code patterns to use GlobalRegistry instead of local Registry.
  """
  def update_code_patterns do
    Logger.info("Migration complete. Update your code to use the new registry patterns:")
    
    IO.puts("""
    
    Migration Guide:
    ================
    
    OLD PATTERN (Local Registry):
    Registry.register(RubberDuck.Registry, {:session, session_id}, session_data)
    Registry.lookup(RubberDuck.Registry, {:session, session_id})
    
    NEW PATTERN (Global Registry):
    SessionRegistry.create_session(session_id, opts)
    SessionRegistry.find_session(session_id)
    
    OLD PATTERN (Model Registration):
    Registry.register(RubberDuck.Registry, {:model, model_id}, model_config)
    
    NEW PATTERN (Model Registration):
    ModelRegistry.register_model(model_id, model_config)
    
    GENERAL GLOBAL REGISTRY:
    GlobalRegistry.register(name, pid, metadata)
    GlobalRegistry.whereis(name)
    GlobalRegistry.find_by_metadata(criteria)
    
    """)
    
    :ok
  end

  # Private functions

  defp get_local_registry_processes do
    try do
      Registry.select(RubberDuck.Registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    rescue
      _ -> []
    end
  end

  defp migrate_single_process(key, pid, value) do
    try do
      case categorize_process(key, value) do
        {:session, session_id} ->
          migrate_session_process(session_id, pid, value)
        
        {:model, model_id} ->
          migrate_model_process(model_id, pid, value)
        
        {:general, name} ->
          migrate_general_process(name, pid, value)
        
        {:unknown, _} ->
          Logger.warn("Unknown process type for key: #{inspect(key)}")
          {:error, :unknown_process_type}
      end
    rescue
      e ->
        Logger.error("Failed to migrate process #{inspect(key)}: #{inspect(e)}")
        {:error, {:migration_failed, e}}
    end
  end

  defp categorize_process(key, _value) do
    case key do
      {:session, session_id} when is_binary(session_id) ->
        {:session, session_id}
      
      {:model, model_id} when is_binary(model_id) ->
        {:model, model_id}
      
      {type, id} when is_atom(type) ->
        {:general, "#{type}_#{id}"}
      
      name when is_atom(name) or is_binary(name) ->
        {:general, name}
      
      _ ->
        {:unknown, key}
    end
  end

  defp migrate_session_process(session_id, pid, value) do
    # Extract session configuration from value
    session_config = extract_session_config(value)
    
    case SessionRegistry.register_session(session_id, session_config, pid) do
      {:ok, _} ->
        Logger.debug("Migrated session: #{session_id}")
        {:ok, {:session, session_id}}
      
      error ->
        Logger.error("Failed to migrate session #{session_id}: #{inspect(error)}")
        error
    end
  end

  defp migrate_model_process(model_id, pid, value) do
    # Extract model configuration from value
    model_config = extract_model_config(value)
    
    case ModelRegistry.register_model(model_id, model_config, pid) do
      {:ok, _} ->
        Logger.debug("Migrated model: #{model_id}")
        {:ok, {:model, model_id}}
      
      error ->
        Logger.error("Failed to migrate model #{model_id}: #{inspect(error)}")
        error
    end
  end

  defp migrate_general_process(name, pid, value) do
    metadata = extract_general_metadata(value)
    
    case GlobalRegistry.register(name, pid, metadata) do
      :ok ->
        Logger.debug("Migrated general process: #{name}")
        {:ok, {:general, name}}
      
      error ->
        Logger.error("Failed to migrate general process #{name}: #{inspect(error)}")
        error
    end
  end

  defp find_session_processes do
    get_local_registry_processes()
    |> Enum.filter_map(
      fn {key, _pid, _value} -> match?({:session, _}, key) end,
      fn {{:session, session_id}, pid, _value} -> {session_id, pid} end
    )
  end

  defp find_model_processes do
    get_local_registry_processes()
    |> Enum.filter_map(
      fn {key, _pid, _value} -> match?({:model, _}, key) end,
      fn {{:model, model_id}, pid, value} -> 
        {model_id, pid, extract_model_config(value)} 
      end
    )
  end

  defp migrate_session(session_id, pid) do
    # Create session with default configuration
    session_config = %{
      migrated: true,
      original_pid: pid,
      migrated_at: System.monotonic_time(:millisecond)
    }
    
    case SessionRegistry.create_session(session_id, session_config) do
      {:ok, ^session_id, _new_pid} ->
        Logger.debug("Successfully migrated session: #{session_id}")
        {:ok, session_id}
      
      error ->
        Logger.error("Failed to migrate session #{session_id}: #{inspect(error)}")
        error
    end
  end

  defp migrate_model(model_id, pid, config) do
    case ModelRegistry.register_model(model_id, config, pid) do
      {:ok, _} ->
        Logger.debug("Successfully migrated model: #{model_id}")
        {:ok, model_id}
      
      error ->
        Logger.error("Failed to migrate model #{model_id}: #{inspect(error)}")
        error
    end
  end

  defp rollback_single_process(name, pid, metadata) do
    # Convert back to local registry key
    local_key = convert_to_local_key(name, metadata)
    
    try do
      case Registry.register(RubberDuck.Registry, local_key, metadata) do
        {:ok, _} ->
          # Unregister from global registry
          GlobalRegistry.unregister(name)
          {:ok, local_key}
        
        {:error, {:already_registered, _}} ->
          {:ok, :already_exists}
        
        error ->
          error
      end
    rescue
      e ->
        {:error, {:rollback_failed, e}}
    end
  end

  defp convert_to_local_key(name, metadata) do
    case Map.get(metadata, :type) do
      :session ->
        session_id = Map.get(metadata, :session_id, extract_id_from_name(name))
        {:session, session_id}
      
      :ai_model ->
        model_id = Map.get(metadata, :model_id, extract_id_from_name(name))
        {:model, model_id}
      
      _ ->
        name
    end
  end

  defp extract_id_from_name(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> String.split("_", parts: 2)
    |> case do
      [_prefix, id] -> id
      [id] -> id
    end
  end

  defp summarize_global_processes(processes) do
    Enum.group_by(processes, fn {_name, _pid, metadata} ->
      Map.get(metadata, :type, :unknown)
    end)
    |> Enum.map(fn {type, procs} -> {type, length(procs)} end)
    |> Enum.into(%{})
  end

  # Configuration extraction helpers
  
  defp extract_session_config(value) do
    case value do
      config when is_map(config) -> config
      _ -> %{migrated: true, legacy_value: value}
    end
  end

  defp extract_model_config(value) do
    case value do
      config when is_map(config) -> config
      _ -> %{migrated: true, legacy_value: value}
    end
  end

  defp extract_general_metadata(value) do
    case value do
      metadata when is_map(metadata) -> metadata
      _ -> %{migrated: true, legacy_value: value}
    end
  end
end
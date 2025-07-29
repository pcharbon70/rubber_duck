defmodule RubberDuck.Jido.Agents.WorkflowVersioningAsh do
  @moduledoc """
  Version management for workflow definitions using Ash resources.
  
  This module provides:
  - Workflow version tracking
  - Compatibility checking between versions
  - Migration support for workflow state
  - Version history and rollback
  
  ## Versioning Strategy
  
  Workflows are versioned using semantic versioning:
  - Major: Breaking changes (incompatible state)
  - Minor: New features (backward compatible)
  - Patch: Bug fixes (fully compatible)
  
  ## Example
  
      # Register a workflow version
      {:ok, version} = WorkflowVersioning.register_version(
        MyWorkflow,
        "2.0.0",
        compatibility: ">=1.5.0"
      )
      
      # Check compatibility
      {:ok, compatible} = WorkflowVersioning.check_compatibility(
        MyWorkflow,
        "1.8.0",
        "2.0.0"
      )
      
      # Migrate workflow state
      {:ok, migrated} = WorkflowVersioning.migrate_state(
        state,
        from: "1.8.0",
        to: "2.0.0"
      )
  """
  
  require Logger
  alias RubberDuck.Workflows.Version
  
  @type version :: String.t()
  @type compatibility_spec :: String.t()
  
  # Client API
  
  @doc """
  Module doesn't require starting anymore as it uses Ash resources.
  Kept for backward compatibility.
  """
  def start_link(_opts \\ []) do
    {:ok, self()}
  end
  
  @doc """
  Registers a workflow version.
  """
  def register_version(module, version, opts \\ []) do
    attrs = %{
      module: module,
      version: version,
      compatibility: opts[:compatibility] || "*",
      migrations: opts[:migrations] || %{},
      metadata: opts[:metadata] || %{}
    }
    
    case Version
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.create() do
      {:ok, _version} -> 
        Logger.info("Registered workflow version #{module} v#{version}")
        {:ok, version}
      {:error, error} -> 
        {:error, error}
    end
  end
  
  @doc """
  Gets the current version of a workflow.
  """
  def get_current_version(module) do
    case Version
         |> Ash.Query.for_read(:get_current, %{module: module})
         |> Ash.read_one() do
      {:ok, nil} -> {:error, :no_versions}
      {:ok, version} -> {:ok, version.version}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Gets version information.
  """
  def get_version_info(module, version) do
    case Version
         |> Ash.Query.for_read(:get_by_version, %{module: module, version: version})
         |> Ash.read_one() do
      {:ok, nil} -> {:error, :version_not_found}
      {:ok, version_info} -> {:ok, version_info}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Lists all versions of a workflow.
  """
  def list_versions(module) do
    case Version
         |> Ash.Query.for_read(:list_by_module, %{module: module})
         |> Ash.read() do
      {:ok, versions} -> {:ok, versions}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Checks if two versions are compatible.
  """
  def check_compatibility(module, from_version, to_version) do
    with {:ok, _from_info} <- get_version_info(module, from_version),
         {:ok, to_info} <- get_version_info(module, to_version) do
      
      # Check if from_version satisfies to_version's compatibility spec
      compatible = Elixir.Version.match?(from_version, to_info.compatibility)
      
      # Also check if there's a migration path
      has_migration = has_migration_path?(module, from_version, to_version)
      
      result = %{
        compatible: compatible,
        has_migration: has_migration,
        requires_migration: !compatible && has_migration
      }
      
      {:ok, result}
    else
      error -> error
    end
  end
  
  @doc """
  Migrates workflow state from one version to another.
  """
  def migrate_state(state, module, from_version, to_version) do
    # Find migration path
    case find_migration_path(module, from_version, to_version) do
      {:ok, path} ->
        # Apply migrations in sequence
        apply_migrations(state, module, path)
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Registers a migration function between versions.
  """
  def register_migration(module, from_version, to_version, migration_fn) do
    # Store migration function in the from version's migrations map
    case get_version_info(module, from_version) do
      {:ok, version_info} ->
        migrations = Map.put(version_info.migrations, to_version, migration_fn)
        
        version_info
        |> Ash.Changeset.for_update(:update, %{migrations: migrations})
        |> Ash.update()
        |> case do
          {:ok, _} -> 
            Logger.info("Registered migration for #{module} from v#{from_version} to v#{to_version}")
            :ok
          {:error, error} -> 
            {:error, error}
        end
        
      {:error, error} ->
        {:error, error}
    end
  end
  
  # Private functions
  
  defp has_migration_path?(module, from_version, to_version) do
    case find_migration_path(module, from_version, to_version) do
      {:ok, _path} -> true
      _ -> false
    end
  end
  
  defp find_migration_path(module, from_version, to_version) do
    # Check if there's a direct migration in the from version
    case get_version_info(module, from_version) do
      {:ok, version_info} ->
        if Map.has_key?(version_info.migrations, to_version) do
          {:ok, [{from_version, to_version}]}
        else
          # Check for multi-step path (simplified)
          find_intermediate_path(module, from_version, to_version)
        end
        
      {:error, _} ->
        {:error, :version_not_found}
    end
  end
  
  defp find_intermediate_path(module, from_version, to_version) do
    # Get all versions between from and to
    case list_versions(module) do
      {:ok, versions} ->
        # Filter versions in range
        intermediate = versions
        |> Enum.map(& &1.version)
        |> Enum.filter(fn v ->
          Elixir.Version.compare(v, from_version) == :gt &&
          Elixir.Version.compare(v, to_version) == :lt
        end)
        |> Enum.sort(&(Elixir.Version.compare(&1, &2) == :lt))
        
        # Build path
        path = build_migration_path([from_version | intermediate] ++ [to_version])
        
        # Verify all migrations exist
        if all_migrations_exist?(module, path) do
          {:ok, path}
        else
          {:error, :no_migration_path}
        end
        
      _ ->
        {:error, :no_versions}
    end
  end
  
  defp build_migration_path(versions) do
    versions
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] -> {from, to} end)
  end
  
  defp all_migrations_exist?(module, path) do
    Enum.all?(path, fn {from, to} ->
      case get_version_info(module, from) do
        {:ok, version_info} ->
          # Check if migration exists in the version's migrations map
          Map.has_key?(version_info.migrations, to)
        _ ->
          false
      end
    end)
  end
  
  defp apply_migrations(state, module, path) do
    try do
      migrated_state = Enum.reduce(path, state, fn {from, to}, acc_state ->
        case get_version_info(module, from) do
          {:ok, version_info} ->
            migration_fn = Map.get(version_info.migrations, to)
            
            if migration_fn do
              Logger.info("Applying migration from v#{from} to v#{to}")
              
              case migration_fn.(acc_state) do
                {:ok, new_state} -> new_state
                {:error, reason} -> throw({:migration_failed, from, to, reason})
              end
            else
              throw({:migration_not_found, from, to})
            end
            
          _ ->
            throw({:migration_not_found, from, to})
        end
      end)
      
      {:ok, migrated_state}
    catch
      {:migration_failed, from, to, reason} ->
        {:error, {:migration_failed, from, to, reason}}
        
      {:migration_not_found, from, to} ->
        {:error, {:migration_not_found, from, to}}
    end
  end
end
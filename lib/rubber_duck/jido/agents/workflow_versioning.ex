defmodule RubberDuck.Jido.Agents.WorkflowVersioning do
  @moduledoc """
  Version management for workflow definitions.
  
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
  
  use GenServer
  require Logger
  # Use Elixir's built-in Version module for semantic versioning
  # alias RubberDuck.Workflows.Version
  
  @type version :: String.t()
  @type compatibility_spec :: String.t()
  
  @type version_info :: %{
          module: module(),
          version: version(),
          compatibility: compatibility_spec(),
          migrations: %{version() => function()},
          metadata: map(),
          registered_at: DateTime.t()
        }
  
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
      {:ok, _version} -> {:ok, version}
      {:error, error} -> {:error, error}
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
    GenServer.call(__MODULE__, {:check_compatibility, module, from_version, to_version})
  end
  
  @doc """
  Migrates workflow state from one version to another.
  """
  def migrate_state(state, module, from_version, to_version) do
    GenServer.call(__MODULE__, {:migrate, state, module, from_version, to_version})
  end
  
  @doc """
  Registers a migration function between versions.
  """
  def register_migration(module, from_version, to_version, migration_fn) do
    GenServer.call(__MODULE__, {:register_migration, module, from_version, to_version, migration_fn})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table for version registry
    :ets.new(:workflow_versions, [:set, :protected, :named_table])
    :ets.new(:workflow_migrations, [:set, :protected, :named_table])
    
    state = %{
      versions: %{},  # module => %{version => version_info}
      current: %{},   # module => current_version
      migrations: %{} # {module, from, to} => migration_fn
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register, module, version, opts}, _from, state) do
    version_info = %{
      module: module,
      version: version,
      compatibility: opts[:compatibility] || "*",
      migrations: opts[:migrations] || %{},
      metadata: opts[:metadata] || %{},
      registered_at: DateTime.utc_now()
    }
    
    # Validate version format
    case Version.parse(version) do
      {:ok, _parsed} ->
        # Store version info
        :ets.insert(:workflow_versions, {{module, version}, version_info})
        
        # Update current version if newer
        new_state = update_current_version(state, module, version)
        
        Logger.info("Registered workflow version #{module} v#{version}")
        
        {:reply, {:ok, version}, new_state}
        
      :error ->
        {:reply, {:error, :invalid_version_format}, state}
    end
  end
  
  @impl true
  def handle_call({:get_current, module}, _from, state) do
    result = case Map.get(state.current, module) do
      nil -> {:error, :no_versions}
      version -> {:ok, version}
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:get_info, module, version}, _from, state) do
    case :ets.lookup(:workflow_versions, {module, version}) do
      [{{^module, ^version}, info}] -> {:reply, {:ok, info}, state}
      [] -> {:reply, {:error, :version_not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:list_versions, module}, _from, state) do
    versions = :ets.match_object(:workflow_versions, {{module, :_}, :_})
    |> Enum.map(fn {{_mod, _version}, info} -> info end)
    |> Enum.sort_by(& &1.version, {:desc, Version})
    
    {:reply, {:ok, versions}, state}
  end
  
  @impl true
  def handle_call({:check_compatibility, module, from_version, to_version}, _from, state) do
    with {:ok, _from_info} <- get_version_info(module, from_version),
         {:ok, to_info} <- get_version_info(module, to_version) do
      
      # Check if from_version satisfies to_version's compatibility spec
      compatible = Version.match?(from_version, to_info.compatibility)
      
      # Also check if there's a migration path
      has_migration = has_migration_path?(module, from_version, to_version)
      
      result = %{
        compatible: compatible,
        has_migration: has_migration,
        requires_migration: !compatible && has_migration
      }
      
      {:reply, {:ok, result}, state}
    else
      error -> {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:migrate, workflow_state, module, from_version, to_version}, _from, state) do
    # Find migration path
    case find_migration_path(module, from_version, to_version) do
      {:ok, path} ->
        # Apply migrations in sequence
        result = apply_migrations(workflow_state, module, path)
        {:reply, result, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:register_migration, module, from_version, to_version, migration_fn}, _from, state) do
    key = {module, from_version, to_version}
    :ets.insert(:workflow_migrations, {key, migration_fn})
    
    new_state = put_in(state.migrations[key], migration_fn)
    
    Logger.info("Registered migration for #{module} from v#{from_version} to v#{to_version}")
    
    {:reply, :ok, new_state}
  end
  
  # Private functions
  
  defp update_current_version(state, module, version) do
    current = Map.get(state.current, module)
    
    if current == nil || Version.compare(version, current) == :gt do
      %{state | current: Map.put(state.current, module, version)}
    else
      state
    end
  end
  
  defp has_migration_path?(module, from_version, to_version) do
    case find_migration_path(module, from_version, to_version) do
      {:ok, _path} -> true
      _ -> false
    end
  end
  
  defp find_migration_path(module, from_version, to_version) do
    # Simple direct migration check for now
    # In a real implementation, this would find multi-step paths
    key = {module, from_version, to_version}
    
    case :ets.lookup(:workflow_migrations, key) do
      [{^key, _migration_fn}] ->
        {:ok, [{from_version, to_version}]}
        
      [] ->
        # Check for multi-step path (simplified)
        find_intermediate_path(module, from_version, to_version)
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
          Version.compare(v, from_version) == :gt &&
          Version.compare(v, to_version) == :lt
        end)
        |> Enum.sort(&(Version.compare(&1, &2) == :lt))
        
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
      key = {module, from, to}
      case :ets.lookup(:workflow_migrations, key) do
        [{^key, _}] -> true
        [] -> false
      end
    end)
  end
  
  defp apply_migrations(state, module, path) do
    try do
      migrated_state = Enum.reduce(path, state, fn {from, to}, acc_state ->
        key = {module, from, to}
        
        case :ets.lookup(:workflow_migrations, key) do
          [{^key, migration_fn}] ->
            Logger.info("Applying migration from v#{from} to v#{to}")
            
            case migration_fn.(acc_state) do
              {:ok, new_state} -> new_state
              {:error, reason} -> throw({:migration_failed, from, to, reason})
            end
            
          [] ->
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
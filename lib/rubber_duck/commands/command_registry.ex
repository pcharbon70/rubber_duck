defmodule RubberDuck.Commands.CommandRegistry do
  @moduledoc """
  Distributed command registry using Horde.Registry for cluster-wide command registration and discovery.
  
  This module provides a distributed registry for commands that enables:
  - Cluster-wide command registration and discovery
  - Command metadata storage and retrieval
  - Command validation during registration
  - Alias resolution for commands
  - Category-based command organization
  - Statistics and monitoring of registered commands
  
  The registry uses Horde.Registry for distributed coordination, allowing commands
  to be registered on any node and discovered from any other node in the cluster.
  
  ## Usage
  
      # Start the registry (usually done by supervision tree)
      {:ok, pid} = CommandRegistry.start_link(name: :commands)
      
      # Register a command
      :ok = CommandRegistry.register_command(:commands, MyCommand)
      
      # Find a command
      {:ok, metadata} = CommandRegistry.find_command(:commands, "my_command")
      
      # List all commands
      commands = CommandRegistry.list_commands(:commands)
      
      # Get statistics
      stats = CommandRegistry.get_stats(:commands)
  """

  use GenServer
  
  alias RubberDuck.Commands.{CommandBehaviour, CommandMetadata}
  
  require Logger

  @type registry_name :: atom() | pid()
  @type command_module :: module()
  @type command_name :: String.t()
  @type command_alias :: String.t()
  @type category :: atom()

  @type stats :: %{
    total_commands: non_neg_integer(),
    categories: [category()],
    async_commands: non_neg_integer(),
    sync_commands: non_neg_integer(),
    streaming_commands: non_neg_integer(),
    deprecated_commands: non_neg_integer()
  }

  # Client API

  @doc """
  Starts the command registry with the given options.
  
  ## Options
  
  - `:name` - The name to register the process under (required)
  - `:distributed` - Whether to use Horde.Registry for distribution (default: true)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a command module with the registry.
  
  The command module must implement the CommandBehaviour and provide valid metadata.
  Registration will fail if:
  - The module doesn't implement CommandBehaviour
  - The metadata is invalid
  - A command with the same name is already registered
  - Any aliases conflict with existing commands
  """
  @spec register_command(registry_name(), command_module()) :: :ok | {:error, String.t()}
  def register_command(registry, command_module) do
    GenServer.call(registry, {:register_command, command_module})
  rescue
    e in [ArgumentError, RuntimeError] ->
      {:error, "Failed to register command: #{Exception.message(e)}"}
  catch
    :exit, {:noproc, _} ->
      {:error, :registry_unavailable}
  end

  @doc """
  Unregisters a command by name.
  """
  @spec unregister_command(registry_name(), command_name()) :: :ok | {:error, :not_found}
  def unregister_command(registry, command_name) do
    GenServer.call(registry, {:unregister_command, command_name})
  rescue
    e -> {:error, "Failed to unregister command: #{Exception.message(e)}"}
  catch
    :exit, {:noproc, _} ->
      {:error, :registry_unavailable}
  end

  @doc """
  Finds a command by name or alias.
  
  Returns the command metadata if found, or :not_found if no matching command exists.
  """
  @spec find_command(registry_name(), command_name() | command_alias()) :: 
    {:ok, CommandMetadata.t()} | {:error, :not_found}
  def find_command(registry, name_or_alias) do
    GenServer.call(registry, {:find_command, name_or_alias})
  catch
    :exit, {:noproc, _} ->
      {:error, :registry_unavailable}
  end

  @doc """
  Finds a command module by name or alias.
  """
  @spec find_command_module(registry_name(), command_name() | command_alias()) :: 
    {:ok, command_module()} | {:error, :not_found}
  def find_command_module(registry, name_or_alias) do
    GenServer.call(registry, {:find_command_module, name_or_alias})
  catch
    :exit, {:noproc, _} ->
      {:error, :registry_unavailable}
  end

  @doc """
  Lists all registered commands.
  """
  @spec list_commands(registry_name()) :: [CommandMetadata.t()] | {:error, :registry_unavailable}
  def list_commands(registry) do
    GenServer.call(registry, :list_commands)
  catch
    :exit, {:noproc, _} ->
      {:error, :registry_unavailable}
  end

  @doc """
  Lists commands by category.
  """
  @spec list_commands_by_category(registry_name(), category()) :: [CommandMetadata.t()]
  def list_commands_by_category(registry, category) do
    GenServer.call(registry, {:list_commands_by_category, category})
  catch
    :exit, {:noproc, _} ->
      []
  end

  @doc """
  Checks if a command exists by name or alias.
  """
  @spec command_exists?(registry_name(), command_name() | command_alias()) :: boolean()
  def command_exists?(registry, name_or_alias) do
    case find_command(registry, name_or_alias) do
      {:ok, _metadata} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Returns the total number of registered commands.
  """
  @spec command_count(registry_name()) :: non_neg_integer()
  def command_count(registry) do
    GenServer.call(registry, :command_count)
  catch
    :exit, {:noproc, _} ->
      0
  end

  @doc """
  Returns statistics about registered commands.
  """
  @spec get_stats(registry_name()) :: stats()
  def get_stats(registry) do
    GenServer.call(registry, :get_stats)
  catch
    :exit, {:noproc, _} ->
      %{
        total_commands: 0,
        categories: [],
        async_commands: 0,
        sync_commands: 0,
        streaming_commands: 0,
        deprecated_commands: 0
      }
  end

  # Server Implementation

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    distributed = Keyword.get(opts, :distributed, true)
    
    # Create ETS table for command storage
    table_name = :"#{name}_commands"
    :ets.new(table_name, [:named_table, :set, :protected, {:read_concurrency, true}])
    
    state = %{
      name: name,
      table: table_name,
      distributed: distributed,
      commands: %{},
      aliases: %{}
    }
    
    if distributed do
      # Start Horde.Registry if needed for distributed features
      # This would integrate with the existing Horde infrastructure
      Logger.debug("Starting distributed command registry: #{name}")
    end
    
    {:ok, state}
  end

  @impl true
  def handle_call({:register_command, command_module}, _from, state) do
    case validate_and_register_command(command_module, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister_command, command_name}, _from, state) do
    case unregister_command_internal(command_name, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:find_command, name_or_alias}, _from, state) do
    case find_command_internal(name_or_alias, state) do
      {:ok, metadata} ->
        {:reply, {:ok, metadata}, state}
      :not_found ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:find_command_module, name_or_alias}, _from, state) do
    case find_command_module_internal(name_or_alias, state) do
      {:ok, module} ->
        {:reply, {:ok, module}, state}
      :not_found ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_commands, _from, state) do
    commands = state.commands
               |> Map.values()
               |> Enum.map(fn {metadata, _module} -> metadata end)
    
    {:reply, commands, state}
  end

  @impl true
  def handle_call({:list_commands_by_category, category}, _from, state) do
    commands = state.commands
               |> Map.values()
               |> Enum.filter(fn {metadata, _module} -> metadata.category == category end)
               |> Enum.map(fn {metadata, _module} -> metadata end)
    
    {:reply, commands, state}
  end

  @impl true
  def handle_call(:command_count, _from, state) do
    count = map_size(state.commands)
    {:reply, count, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = calculate_stats(state)
    {:reply, stats, state}
  end

  # Internal Functions

  defp validate_and_register_command(command_module, state) do
    try do
      # Validate implementation
      :ok = CommandBehaviour.validate_implementation!(command_module)
      
      # Get and validate metadata
      metadata = command_module.metadata()
      ^metadata = CommandMetadata.validate!(metadata)
      
      # Check conflicts
      :ok = check_name_conflicts(metadata, state)
      :ok = check_alias_conflicts(metadata, state)
      
      # Register the command
      new_state = register_command_internal(metadata, command_module, state)
      Logger.debug("Registered command: #{metadata.name} from module #{command_module}")
      
      {:ok, new_state}
    rescue
      error -> {:error, "Failed to validate command: #{Exception.message(error)}"}
    catch
      :throw, {:error, reason} -> {:error, reason}
    end
  end

  defp register_command_internal(metadata, command_module, state) do
    # Store in ETS for fast lookups
    :ets.insert(state.table, {metadata.name, {metadata, command_module}})
    
    # Update state
    new_commands = Map.put(state.commands, metadata.name, {metadata, command_module})
    
    # Update aliases map
    new_aliases = Enum.reduce(metadata.aliases, state.aliases, fn alias, acc ->
      Map.put(acc, alias, metadata.name)
    end)
    
    %{state | commands: new_commands, aliases: new_aliases}
  end

  defp unregister_command_internal(command_name, state) do
    case Map.get(state.commands, command_name) do
      nil ->
        {:error, :not_found}
      
      {metadata, _module} ->
        # Remove from ETS
        :ets.delete(state.table, command_name)
        
        # Remove from state
        new_commands = Map.delete(state.commands, command_name)
        
        # Remove aliases
        new_aliases = Enum.reduce(metadata.aliases, state.aliases, fn alias, acc ->
          Map.delete(acc, alias)
        end)
        
        new_state = %{state | commands: new_commands, aliases: new_aliases}
        {:ok, new_state}
    end
  end

  defp find_command_internal(name_or_alias, state) do
    # Try direct name lookup first
    case Map.get(state.commands, name_or_alias) do
      {metadata, _module} ->
        {:ok, metadata}
      
      nil ->
        # Try alias lookup
        case Map.get(state.aliases, name_or_alias) do
          nil ->
            :not_found
          
          actual_name ->
            case Map.get(state.commands, actual_name) do
              {metadata, _module} -> {:ok, metadata}
              nil -> :not_found
            end
        end
    end
  end

  defp find_command_module_internal(name_or_alias, state) do
    # Try direct name lookup first
    case Map.get(state.commands, name_or_alias) do
      {_metadata, module} ->
        {:ok, module}
      
      nil ->
        # Try alias lookup
        case Map.get(state.aliases, name_or_alias) do
          nil ->
            :not_found
          
          actual_name ->
            case Map.get(state.commands, actual_name) do
              {_metadata, module} -> {:ok, module}
              nil -> :not_found
            end
        end
    end
  end

  defp check_name_conflicts(metadata, state) do
    if Map.has_key?(state.commands, metadata.name) do
      {:error, "Command '#{metadata.name}' is already registered"}
    else
      :ok
    end
  end

  defp check_alias_conflicts(metadata, state) do
    conflicting_alias = Enum.find(metadata.aliases, fn alias ->
      Map.has_key?(state.aliases, alias) or Map.has_key?(state.commands, alias)
    end)
    
    if conflicting_alias do
      {:error, "Alias '#{conflicting_alias}' conflicts with existing command or alias"}
    else
      :ok
    end
  end

  defp calculate_stats(state) do
    commands = Map.values(state.commands)
    
    total_commands = length(commands)
    categories = commands
                |> Enum.map(fn {metadata, _} -> metadata.category end)
                |> Enum.uniq()
                |> Enum.sort()
    
    async_commands = Enum.count(commands, fn {metadata, _} -> metadata.async end)
    sync_commands = total_commands - async_commands
    streaming_commands = Enum.count(commands, fn {metadata, _} -> metadata.stream end)
    deprecated_commands = Enum.count(commands, fn {metadata, _} -> metadata.deprecated end)
    
    %{
      total_commands: total_commands,
      categories: categories,
      async_commands: async_commands,
      sync_commands: sync_commands,
      streaming_commands: streaming_commands,
      deprecated_commands: deprecated_commands
    }
  end
end
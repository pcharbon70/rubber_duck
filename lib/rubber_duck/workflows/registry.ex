defmodule RubberDuck.Workflows.Registry do
  @moduledoc """
  Registry for managing and discovering workflows.

  Provides functionality for:
  - Registering workflows by name
  - Looking up workflows
  - Listing available workflows
  - Workflow metadata management
  """

  use GenServer

  require Logger
  alias RubberDuck.Status

  @table_name :workflow_registry

  # Client API

  @doc """
  Starts the workflow registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a workflow module.
  """
  def register(workflow_module, opts \\ []) when is_atom(workflow_module) do
    GenServer.call(__MODULE__, {:register, workflow_module, opts})
  end

  @doc """
  Unregisters a workflow.
  """
  def unregister(name) do
    GenServer.call(__MODULE__, {:unregister, name})
  end

  @doc """
  Looks up a workflow by name.
  """
  def lookup(name) do
    case :ets.lookup(@table_name, name) do
      [{^name, workflow_info}] -> {:ok, workflow_info}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Lists all registered workflows.
  """
  def list_workflows(opts \\ []) do
    pattern = build_match_pattern(opts)

    @table_name
    |> :ets.match(pattern)
    |> Enum.map(fn [info] -> info end)
  end

  @doc """
  Lists workflows by tag.
  """
  def list_by_tag(tag) do
    list_workflows(tag: tag)
  end

  @doc """
  Gets workflow metadata.
  """
  def get_metadata(name) do
    case lookup(name) do
      {:ok, info} -> {:ok, info.metadata}
      error -> error
    end
  end

  @doc """
  Updates workflow metadata.
  """
  def update_metadata(name, metadata) do
    GenServer.call(__MODULE__, {:update_metadata, name, metadata})
  end

  @doc """
  Manually trigger workflow discovery.
  This should be called after the application has fully started.
  """
  def discover_and_register_workflows do
    GenServer.cast(__MODULE__, :discover_workflows)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast lookups
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true
    ])

    # Don't auto-discover workflows to avoid circular dependencies
    # Workflows should register themselves explicitly

    state = %{
      workflows: %{},
      stats: %{
        registrations: 0,
        lookups: 0
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register, workflow_module, opts}, _from, state) do
    name = opts[:name] || workflow_module.name()

    workflow_info = %{
      module: workflow_module,
      name: name,
      description: workflow_module.description(),
      version: workflow_module.version(),
      tags: opts[:tags] || [],
      metadata: opts[:metadata] || %{},
      registered_at: DateTime.utc_now()
    }

    # Store in ETS
    :ets.insert(@table_name, {name, workflow_info})

    # Update state
    new_state = %{
      state
      | workflows: Map.put(state.workflows, name, workflow_info),
        stats: %{state.stats | registrations: state.stats.registrations + 1}
    }

    Logger.info("Registered workflow: #{name}")

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unregister, name}, _from, state) do
    :ets.delete(@table_name, name)

    new_state = %{state | workflows: Map.delete(state.workflows, name)}

    Logger.info("Unregistered workflow: #{name}")

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:update_metadata, name, metadata}, _from, state) do
    case :ets.lookup(@table_name, name) do
      [{^name, workflow_info}] ->
        updated_info = %{workflow_info | metadata: metadata}
        :ets.insert(@table_name, {name, updated_info})

        new_state = %{state | workflows: Map.put(state.workflows, name, updated_info)}

        {:reply, :ok, new_state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_cast(:discover_workflows, state) do
    discover_workflows()
    {:noreply, state}
  end

  # Private functions

  defp discover_workflows do
    # Auto-discover workflow modules
    # This is a simplified version - in production, you might want to
    # scan specific directories or use compile-time discovery

    with {:ok, modules} <- :application.get_key(:rubber_duck, :modules) do
      workflow_modules =
        modules
        |> Enum.filter(&workflow_module?/1)

      # Register each workflow module
      Enum.each(workflow_modules, fn module ->
        try do
          register(module)
        rescue
          e ->
            Logger.warning("Failed to register workflow #{inspect(module)}: #{inspect(e)}")

            # Report to status system if we have a session/conversation context
            # Since this is during registration/startup, we won't have a conversation_id
            # But we can still track this as a system-level error
            Status.error(
              # No conversation context
              nil,
              "Workflow registration failed",
              Status.build_error_metadata(
                :registration_error,
                Exception.message(e),
                %{
                  module: inspect(module),
                  error_type: e.__struct__,
                  stage: "auto_registration"
                }
              )
            )
        end
      end)
    end
  end

  defp workflow_module?(module) do
    # Check if module implements the Workflow behavior
    Code.ensure_loaded?(module) &&
      function_exported?(module, :__info__, 1) &&
      RubberDuck.Workflows.Workflow in (module.__info__(:attributes)[:behaviour] || [])
  end

  defp build_match_pattern(opts) do
    base_pattern = %{
      module: :_,
      name: :_,
      description: :_,
      version: :_,
      tags: :_,
      metadata: :_,
      registered_at: :_
    }

    pattern =
      if tag = opts[:tag] do
        # Match workflows that have the specified tag
        %{base_pattern | tags: {:contains, tag}}
      else
        base_pattern
      end

    {:"$1", pattern}
  end
end

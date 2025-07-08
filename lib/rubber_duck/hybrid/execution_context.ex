defmodule RubberDuck.Hybrid.ExecutionContext do
  @moduledoc """
  Unified execution context for engine-workflow hybrid execution.

  This module provides a shared execution context that bridges the gap between
  engine-level operations and workflow-level orchestration, enabling seamless
  communication and state sharing across both architectural layers.
  """

  defstruct [
    :execution_id,
    :engine_context,
    :workflow_context,
    :shared_state,
    :telemetry_metadata,
    :resource_allocation,
    :started_at,
    :parent_context
  ]

  @type t :: %__MODULE__{
          execution_id: String.t(),
          engine_context: map(),
          workflow_context: map(),
          shared_state: map(),
          telemetry_metadata: map(),
          resource_allocation: map(),
          started_at: DateTime.t(),
          parent_context: t() | nil
        }

  @doc """
  Creates a new unified execution context for hybrid execution.

  ## Options
  - `:execution_id` - Unique identifier for this execution
  - `:engine_context` - Initial engine context
  - `:workflow_context` - Initial workflow context
  - `:shared_state` - Initial shared state
  - `:parent_context` - Parent context for nested executions
  """
  @spec create_hybrid_context(keyword()) :: t()
  def create_hybrid_context(opts \\ []) do
    %__MODULE__{
      execution_id: opts[:execution_id] || generate_execution_id(),
      engine_context: opts[:engine_context] || %{},
      workflow_context: opts[:workflow_context] || %{},
      shared_state: opts[:shared_state] || %{},
      telemetry_metadata: build_telemetry_metadata(opts),
      resource_allocation: opts[:resource_allocation] || %{},
      started_at: DateTime.utc_now(),
      parent_context: opts[:parent_context]
    }
  end

  @doc """
  Merges separate engine and workflow contexts into a unified context.

  This function intelligently combines context from both layers, resolving
  conflicts and ensuring consistent state across the hybrid execution.
  """
  @spec merge_contexts(map(), map()) :: t()
  def merge_contexts(engine_context, workflow_context) do
    shared_state = merge_shared_state(engine_context, workflow_context)

    %__MODULE__{
      execution_id: generate_execution_id(),
      engine_context: engine_context,
      workflow_context: workflow_context,
      shared_state: shared_state,
      telemetry_metadata: build_merged_telemetry(engine_context, workflow_context),
      resource_allocation: merge_resource_allocation(engine_context, workflow_context),
      started_at: DateTime.utc_now(),
      parent_context: nil
    }
  end

  @doc """
  Updates the engine context within the hybrid context.
  """
  @spec update_engine_context(t(), map()) :: t()
  def update_engine_context(%__MODULE__{} = context, engine_context) do
    %{context | engine_context: engine_context}
  end

  @doc """
  Updates the workflow context within the hybrid context.
  """
  @spec update_workflow_context(t(), map()) :: t()
  def update_workflow_context(%__MODULE__{} = context, workflow_context) do
    %{context | workflow_context: workflow_context}
  end

  @doc """
  Updates the shared state, merging with existing state.
  """
  @spec update_shared_state(t(), map()) :: t()
  def update_shared_state(%__MODULE__{} = context, state_updates) do
    updated_state = Map.merge(context.shared_state, state_updates)
    %{context | shared_state: updated_state}
  end

  @doc """
  Adds telemetry metadata to the context.
  """
  @spec add_telemetry_metadata(t(), map()) :: t()
  def add_telemetry_metadata(%__MODULE__{} = context, metadata) do
    updated_metadata = Map.merge(context.telemetry_metadata, metadata)
    %{context | telemetry_metadata: updated_metadata}
  end

  @doc """
  Creates a child context for nested hybrid executions.
  """
  @spec create_child_context(t(), keyword()) :: t()
  def create_child_context(%__MODULE__{} = parent_context, opts \\ []) do
    opts
    |> Keyword.put(:parent_context, parent_context)
    |> Keyword.put_new(:shared_state, parent_context.shared_state)
    |> create_hybrid_context()
  end

  @doc """
  Extracts engine-specific context for engine execution.
  """
  @spec extract_engine_context(t()) :: map()
  def extract_engine_context(%__MODULE__{} = context) do
    context.engine_context
    |> Map.put(:execution_id, context.execution_id)
    |> Map.put(:shared_state, context.shared_state)
    |> Map.put(:telemetry_metadata, context.telemetry_metadata)
  end

  @doc """
  Extracts workflow-specific context for workflow execution.
  """
  @spec extract_workflow_context(t()) :: map()
  def extract_workflow_context(%__MODULE__{} = context) do
    context.workflow_context
    |> Map.put(:execution_id, context.execution_id)
    |> Map.put(:shared_state, context.shared_state)
    |> Map.put(:telemetry_metadata, context.telemetry_metadata)
  end

  @doc """
  Gets the execution duration so far.
  """
  @spec execution_duration(t()) :: integer()
  def execution_duration(%__MODULE__{started_at: started_at}) do
    DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
  end

  @doc """
  Checks if this context has a parent (nested execution).
  """
  @spec has_parent?(t()) :: boolean()
  def has_parent?(%__MODULE__{parent_context: parent_context}) do
    not is_nil(parent_context)
  end

  @doc """
  Gets the root context (traverses up the parent chain).
  """
  @spec get_root_context(t()) :: t()
  def get_root_context(%__MODULE__{parent_context: nil} = context), do: context

  def get_root_context(%__MODULE__{parent_context: parent_context}) do
    get_root_context(parent_context)
  end

  # Private functions

  defp generate_execution_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  defp build_telemetry_metadata(opts) do
    %{
      started_at: DateTime.utc_now(),
      execution_type: :hybrid,
      parent_execution_id: opts[:parent_context] && opts[:parent_context].execution_id
    }
  end

  defp merge_shared_state(engine_context, workflow_context) do
    engine_shared = Map.get(engine_context, :shared_state, %{})
    workflow_shared = Map.get(workflow_context, :shared_state, %{})

    Map.merge(engine_shared, workflow_shared)
  end

  defp build_merged_telemetry(engine_context, workflow_context) do
    engine_telemetry = Map.get(engine_context, :telemetry_metadata, %{})
    workflow_telemetry = Map.get(workflow_context, :telemetry_metadata, %{})

    Map.merge(engine_telemetry, workflow_telemetry)
    |> Map.put(:merged_at, DateTime.utc_now())
    |> Map.put(:execution_type, :hybrid)
  end

  defp merge_resource_allocation(engine_context, workflow_context) do
    engine_resources = Map.get(engine_context, :resource_allocation, %{})
    workflow_resources = Map.get(workflow_context, :resource_allocation, %{})

    # Merge resource allocations, preferring workflow resources in case of conflicts
    Map.merge(engine_resources, workflow_resources)
  end
end

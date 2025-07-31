defmodule RubberDuck.Agents.TokenManager.TokenProvenance do
  @moduledoc """
  Comprehensive provenance tracking for token usage.
  
  Captures the complete lineage, context, and purpose of every token request,
  enabling detailed audit trails, cost attribution, and optimization analysis.
  """

  @type t :: %__MODULE__{
    id: String.t(),
    usage_id: String.t(),
    request_id: String.t(),
    timestamp: DateTime.t(),
    
    # Lineage information
    parent_request_id: String.t() | nil,
    root_request_id: String.t(),
    workflow_id: String.t() | nil,
    session_id: String.t() | nil,
    conversation_id: String.t() | nil,
    depth: non_neg_integer(),
    
    # Agent context
    agent_id: String.t(),
    agent_type: String.t(),
    signal_type: String.t(),
    signal_trail: [String.t()],
    
    # Purpose and intent
    task_type: String.t(),
    intent: String.t(),
    purpose: String.t() | nil,
    prompt_template_id: String.t() | nil,
    prompt_version: String.t() | nil,
    
    # Content references
    input_hash: String.t() | nil,
    output_hash: String.t() | nil,
    code_references: [String.t()],
    document_references: [String.t()],
    
    # System context
    system_version: String.t(),
    environment: String.t(),
    
    # Metadata
    tags: [String.t()],
    metadata: map()
  }

  defstruct [
    :id,
    :usage_id,
    :request_id,
    :timestamp,
    :parent_request_id,
    :root_request_id,
    :workflow_id,
    :session_id,
    :conversation_id,
    :depth,
    :agent_id,
    :agent_type,
    :signal_type,
    :signal_trail,
    :task_type,
    :intent,
    :purpose,
    :prompt_template_id,
    :prompt_version,
    :input_hash,
    :output_hash,
    :code_references,
    :document_references,
    :system_version,
    :environment,
    :tags,
    :metadata
  ]

  @doc """
  Creates a new TokenProvenance record.
  
  ## Parameters
  
  - `attrs` - Map containing provenance attributes
  
  ## Examples
  
      iex> TokenProvenance.new(%{
      ...>   usage_id: "usage_123",
      ...>   request_id: "req_123",
      ...>   agent_id: "agent_456",
      ...>   agent_type: "provider",
      ...>   task_type: "code_generation",
      ...>   intent: "implement_feature"
      ...> })
      %TokenProvenance{...}
  """
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: Map.get(attrs, :id, generate_id()),
      usage_id: Map.fetch!(attrs, :usage_id),
      request_id: Map.fetch!(attrs, :request_id),
      timestamp: Map.get(attrs, :timestamp, DateTime.utc_now()),
      
      # Lineage
      parent_request_id: Map.get(attrs, :parent_request_id),
      root_request_id: Map.get(attrs, :root_request_id, attrs[:request_id]),
      workflow_id: Map.get(attrs, :workflow_id),
      session_id: Map.get(attrs, :session_id),
      conversation_id: Map.get(attrs, :conversation_id),
      depth: Map.get(attrs, :depth, calculate_depth(attrs)),
      
      # Agent context
      agent_id: Map.fetch!(attrs, :agent_id),
      agent_type: Map.fetch!(attrs, :agent_type),
      signal_type: Map.get(attrs, :signal_type, "unknown"),
      signal_trail: Map.get(attrs, :signal_trail, []),
      
      # Purpose
      task_type: Map.fetch!(attrs, :task_type),
      intent: Map.fetch!(attrs, :intent),
      purpose: Map.get(attrs, :purpose),
      prompt_template_id: Map.get(attrs, :prompt_template_id),
      prompt_version: Map.get(attrs, :prompt_version),
      
      # Content
      input_hash: Map.get(attrs, :input_hash),
      output_hash: Map.get(attrs, :output_hash),
      code_references: Map.get(attrs, :code_references, []),
      document_references: Map.get(attrs, :document_references, []),
      
      # System
      system_version: Map.get(attrs, :system_version, get_system_version()),
      environment: Map.get(attrs, :environment, get_environment()),
      
      # Metadata
      tags: Map.get(attrs, :tags, []),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @doc """
  Validates a TokenProvenance record.
  
  Returns `{:ok, provenance}` if valid, `{:error, errors}` otherwise.
  """
  def validate(%__MODULE__{} = provenance) do
    errors = []
    
    errors = if provenance.usage_id == nil or provenance.usage_id == "", 
      do: ["usage_id is required" | errors], else: errors
    errors = if provenance.request_id == nil or provenance.request_id == "", 
      do: ["request_id is required" | errors], else: errors
    errors = if provenance.agent_id == nil or provenance.agent_id == "", 
      do: ["agent_id is required" | errors], else: errors
    errors = if provenance.agent_type == nil or provenance.agent_type == "", 
      do: ["agent_type is required" | errors], else: errors
    errors = if provenance.task_type == nil or provenance.task_type == "", 
      do: ["task_type is required" | errors], else: errors
    errors = if provenance.intent == nil or provenance.intent == "", 
      do: ["intent is required" | errors], else: errors
    
    # Validate depth consistency
    errors = if provenance.parent_request_id == nil and provenance.depth > 0,
      do: ["depth must be 0 for root requests" | errors], else: errors
    
    if errors == [] do
      {:ok, provenance}
    else
      {:error, errors}
    end
  end

  @doc """
  Checks if this is a root request (no parent).
  """
  def root?(%__MODULE__{parent_request_id: nil}), do: true
  def root?(%__MODULE__{}), do: false

  @doc """
  Checks if this request is part of a workflow.
  """
  def in_workflow?(%__MODULE__{workflow_id: nil}), do: false
  def in_workflow?(%__MODULE__{}), do: true

  @doc """
  Checks if this request is part of a conversation.
  """
  def in_conversation?(%__MODULE__{conversation_id: nil}), do: false
  def in_conversation?(%__MODULE__{}), do: true

  @doc """
  Returns a summary of the provenance for logging/display.
  """
  def summary(%__MODULE__{} = provenance) do
    %{
      request_id: provenance.request_id,
      agent: "#{provenance.agent_type}/#{provenance.agent_id}",
      task: "#{provenance.task_type}/#{provenance.intent}",
      lineage: build_lineage_summary(provenance),
      context: build_context_summary(provenance)
    }
  end

  @doc """
  Builds a hash of the content for deduplication.
  """
  def content_hash(input_content, output_content \\ nil) do
    content = if output_content do
      "#{input_content}::#{output_content}"
    else
      input_content
    end
    
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
    |> String.slice(0..15)
  end

  @doc """
  Adds a tag to the provenance.
  """
  def add_tag(%__MODULE__{tags: tags} = provenance, tag) when is_binary(tag) do
    %{provenance | tags: Enum.uniq([tag | tags])}
  end

  @doc """
  Adds metadata to the provenance.
  """
  def add_metadata(%__MODULE__{metadata: metadata} = provenance, key, value) do
    %{provenance | metadata: Map.put(metadata, key, value)}
  end

  @doc """
  Groups a list of provenance records by a field.
  """
  def group_by(provenance_list, field) when is_list(provenance_list) and is_atom(field) do
    Enum.group_by(provenance_list, &Map.get(&1, field))
  end

  @doc """
  Filters provenance records by task type.
  """
  def filter_by_task_type(provenance_list, task_type) when is_list(provenance_list) do
    Enum.filter(provenance_list, &(&1.task_type == task_type))
  end

  @doc """
  Filters provenance records by workflow.
  """
  def filter_by_workflow(provenance_list, workflow_id) when is_list(provenance_list) do
    Enum.filter(provenance_list, &(&1.workflow_id == workflow_id))
  end

  @doc """
  Builds a signal trail string for display.
  """
  def signal_trail_string(%__MODULE__{signal_trail: trail}) do
    Enum.join(trail, " → ")
  end

  ## Private Functions

  defp calculate_depth(%{parent_request_id: nil}), do: 0
  defp calculate_depth(%{depth: depth}) when is_integer(depth), do: depth
  defp calculate_depth(_), do: 1  # Default depth if parent exists but not specified

  defp build_lineage_summary(provenance) do
    %{
      parent: provenance.parent_request_id,
      root: provenance.root_request_id,
      depth: provenance.depth,
      workflow: provenance.workflow_id,
      session: provenance.session_id,
      conversation: provenance.conversation_id
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp build_context_summary(provenance) do
    %{
      signal: provenance.signal_type,
      template: provenance.prompt_template_id,
      environment: provenance.environment,
      tags: provenance.tags
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == [] end)
    |> Map.new()
  end

  defp get_system_version do
    Application.spec(:rubber_duck, :vsn) |> to_string()
  rescue
    _ -> "unknown"
  end

  defp get_environment do
    Application.get_env(:rubber_duck, :environment, "development")
  end

  defp generate_id do
    "prov_#{System.unique_integer([:positive, :monotonic])}"
  end
end
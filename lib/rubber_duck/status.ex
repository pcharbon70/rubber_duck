defmodule RubberDuck.Status do
  @moduledoc """
  Public API for sending status updates from anywhere in the system.
  All functions are fire-and-forget for maximum performance.
  
  Status updates are broadcast to Phoenix channels based on conversation
  and category, allowing real-time monitoring of system operations without
  impacting performance.
  
  ## Categories
  
  - `:engine` - LLM engine processing updates
  - `:tool` - Tool execution status
  - `:workflow` - Workflow orchestration updates
  - `:progress` - General progress indicators
  - `:error` - Error notifications
  - `:info` - General information
  
  ## Examples
  
      # From an engine
      Status.engine(conversation_id, "Processing with GPT-4", %{model: "gpt-4"})
      
      # From a tool
      Status.tool(conversation_id, "Executing web search", %{query: "elixir"})
      
      # System-wide message
      Status.info(nil, "System initialized")
  """

  alias RubberDuck.Status.Broadcaster

  @doc """
  Send a status update for a conversation.
  
  ## Parameters
    - conversation_id: The conversation identifier (nil for system-wide)
    - category: The message category atom
    - text: The status message
    - metadata: Optional metadata map
  
  ## Examples
      
      Status.update("conv-123", :engine, "Processing", %{step: 1})
      Status.update(nil, :info, "Ready")
  """
  @spec update(String.t() | nil, atom(), String.t(), map()) :: :ok
  def update(conversation_id, category, text, metadata \\ %{}) do
    Broadcaster.broadcast(conversation_id, category, text, metadata)
    :ok
  end

  @doc """
  Send an engine status update.
  """
  @spec engine(String.t() | nil, String.t(), map()) :: :ok
  def engine(conversation_id, text, metadata \\ %{}) do
    update(conversation_id, :engine, text, metadata)
  end

  @doc """
  Send a tool status update.
  """
  @spec tool(String.t() | nil, String.t(), map()) :: :ok
  def tool(conversation_id, text, metadata \\ %{}) do
    update(conversation_id, :tool, text, metadata)
  end

  @doc """
  Send a workflow status update.
  """
  @spec workflow(String.t() | nil, String.t(), map()) :: :ok
  def workflow(conversation_id, text, metadata \\ %{}) do
    update(conversation_id, :workflow, text, metadata)
  end

  @doc """
  Send a progress status update.
  """
  @spec progress(String.t() | nil, String.t(), map()) :: :ok
  def progress(conversation_id, text, metadata \\ %{}) do
    update(conversation_id, :progress, text, metadata)
  end

  @doc """
  Send an error status update.
  """
  @spec error(String.t() | nil, String.t(), map()) :: :ok
  def error(conversation_id, text, metadata \\ %{}) do
    update(conversation_id, :error, text, metadata)
  end

  @doc """
  Send an info status update.
  """
  @spec info(String.t() | nil, String.t(), map()) :: :ok
  def info(conversation_id, text, metadata \\ %{}) do
    update(conversation_id, :info, text, metadata)
  end
end
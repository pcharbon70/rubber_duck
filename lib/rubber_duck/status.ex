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

  # Metadata Builders

  @doc """
  Build standardized metadata for LLM operations.
  
  ## Examples
      
      Status.engine(conv_id, "Processing", build_llm_metadata("gpt-4", "openai"))
  """
  @spec build_llm_metadata(String.t(), String.t(), map()) :: map()
  def build_llm_metadata(model, provider, extra \\ %{}) do
    %{
      model: model,
      provider: provider,
      timestamp: DateTime.utc_now()
    }
    |> Map.merge(extra)
  end

  @doc """
  Build standardized metadata for tool operations.
  
  ## Examples
      
      Status.tool(conv_id, "Executing", build_tool_metadata("web_search", %{query: "elixir"}))
  """
  @spec build_tool_metadata(String.t(), map(), map()) :: map()
  def build_tool_metadata(tool_name, params, extra \\ %{}) do
    %{
      tool: tool_name,
      params: sanitize_params(params),
      timestamp: DateTime.utc_now()
    }
    |> Map.merge(extra)
  end

  @doc """
  Build standardized metadata for workflow operations.
  
  ## Examples
      
      Status.workflow(conv_id, "Step completed", build_workflow_metadata("analysis", 3, 5))
  """
  @spec build_workflow_metadata(String.t(), integer(), integer(), map()) :: map()
  def build_workflow_metadata(workflow_name, current_step, total_steps, extra \\ %{}) do
    %{
      workflow: workflow_name,
      progress: "#{current_step}/#{total_steps}",
      percentage: round(current_step / total_steps * 100),
      timestamp: DateTime.utc_now()
    }
    |> Map.merge(extra)
  end

  @doc """
  Build standardized metadata for error reporting.
  
  ## Examples
      
      Status.error(conv_id, "Failed", build_error_metadata(:timeout, "Operation timed out"))
  """
  @spec build_error_metadata(atom() | String.t(), String.t(), map()) :: map()
  def build_error_metadata(error_type, reason, extra \\ %{}) do
    %{
      error_type: error_type,
      reason: reason,
      timestamp: DateTime.utc_now()
    }
    |> Map.merge(extra)
  end

  # Convenience Functions

  @doc """
  Send a status update with timing information.
  
  ## Examples
      
      start_time = System.monotonic_time(:millisecond)
      # ... do work ...
      Status.with_timing(conv_id, :tool, "Completed", start_time, %{tool: "search"})
  """
  @spec with_timing(String.t() | nil, atom(), String.t(), integer(), map()) :: :ok
  def with_timing(conversation_id, category, text, start_time, metadata \\ %{}) do
    duration_ms = System.monotonic_time(:millisecond) - start_time
    
    enhanced_metadata = Map.merge(metadata, %{
      duration_ms: duration_ms,
      duration_human: format_duration(duration_ms)
    })
    
    update(conversation_id, category, text, enhanced_metadata)
  end

  @doc """
  Send a progress update with percentage.
  
  ## Examples
      
      Status.progress_percentage(conv_id, "Processing documents", 3, 10)
  """
  @spec progress_percentage(String.t() | nil, String.t(), integer(), integer(), map()) :: :ok
  def progress_percentage(conversation_id, text, current, total, metadata \\ %{}) do
    percentage = if total > 0, do: round(current / total * 100), else: 0
    
    enhanced_metadata = Map.merge(metadata, %{
      current: current,
      total: total,
      percentage: percentage,
      progress: "#{current}/#{total}"
    })
    
    progress(conversation_id, "#{text} (#{percentage}%)", enhanced_metadata)
  end

  @doc """
  Send bulk status updates efficiently.
  
  ## Examples
      
      Status.bulk_update(conv_id, [
        {:engine, "Starting", %{model: "gpt-4"}},
        {:tool, "Preparing", %{tool: "search"}},
        {:progress, "Initializing", %{}}
      ])
  """
  @spec bulk_update(String.t() | nil, list({atom(), String.t(), map()})) :: :ok
  def bulk_update(conversation_id, updates) do
    Enum.each(updates, fn {category, text, metadata} ->
      update(conversation_id, category, text, metadata)
    end)
    :ok
  end

  @doc """
  Send a conditional status update (only if enabled).
  
  ## Examples
      
      Status.maybe_update(true, conv_id, :info, "Debug info", %{})
  """
  @spec maybe_update(boolean(), String.t() | nil, atom(), String.t(), map()) :: :ok
  def maybe_update(condition, conversation_id, category, text, metadata \\ %{})
  def maybe_update(true, conversation_id, category, text, metadata) do
    update(conversation_id, category, text, metadata)
  end
  def maybe_update(false, _conversation_id, _category, _text, _metadata), do: :ok

  # Private Helpers

  defp sanitize_params(params) when is_map(params) do
    params
    |> Enum.map(fn
      {k, v} when is_binary(v) and byte_size(v) > 100 ->
        {k, String.slice(v, 0, 100) <> "..."}
      
      {k, v} when is_map(v) ->
        {k, sanitize_params(v)}
        
      {k, v} ->
        {k, v}
    end)
    |> Map.new()
  end
  defp sanitize_params(params), do: params

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration(ms), do: "#{Float.round(ms / 60000, 1)}m"
end
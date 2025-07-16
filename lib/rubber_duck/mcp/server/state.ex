defmodule RubberDuck.MCP.Server.State do
  @moduledoc """
  State structure for the MCP server.
  
  Maintains server configuration and runtime state including:
  - Transport configuration
  - Filter functions for tools and resources
  - Session tracking
  - Performance metrics
  """
  
  @type tool_filter :: (String.t() -> boolean()) | nil
  @type resource_filter :: (String.t() -> boolean()) | nil
  
  @type t :: %__MODULE__{
    transport: atom(),
    tool_filter: tool_filter(),
    resource_filter: resource_filter(),
    start_time: integer(),
    request_count: non_neg_integer(),
    active_sessions: MapSet.t(String.t()),
    last_activity: integer() | nil
  }
  
  defstruct [
    :transport,
    :tool_filter,
    :resource_filter,
    :last_activity,
    start_time: nil,
    request_count: 0,
    active_sessions: MapSet.new()
  ]
  
  @doc """
  Records a new request and updates metrics.
  """
  def record_request(%__MODULE__{} = state) do
    %{state | 
      request_count: state.request_count + 1,
      last_activity: System.monotonic_time(:second)
    }
  end
  
  @doc """
  Adds a session to the active sessions set.
  """
  def add_session(%__MODULE__{} = state, session_id) do
    %{state | active_sessions: MapSet.put(state.active_sessions, session_id)}
  end
  
  @doc """
  Removes a session from the active sessions set.
  """
  def remove_session(%__MODULE__{} = state, session_id) do
    %{state | active_sessions: MapSet.delete(state.active_sessions, session_id)}
  end
  
  @doc """
  Gets server uptime in seconds.
  """
  def uptime(%__MODULE__{start_time: nil}), do: 0
  def uptime(%__MODULE__{start_time: start_time}) do
    System.monotonic_time(:second) - start_time
  end
  
  @doc """
  Checks if a tool should be exposed based on the filter.
  """
  def tool_allowed?(%__MODULE__{tool_filter: nil}, _tool_name), do: true
  def tool_allowed?(%__MODULE__{tool_filter: filter}, tool_name) when is_function(filter, 1) do
    filter.(tool_name)
  end
  
  @doc """
  Checks if a resource should be exposed based on the filter.
  """
  def resource_allowed?(%__MODULE__{resource_filter: nil}, _resource_uri), do: true
  def resource_allowed?(%__MODULE__{resource_filter: filter}, resource_uri) when is_function(filter, 1) do
    filter.(resource_uri)
  end
end
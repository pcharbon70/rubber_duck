defmodule RubberDuck.Tool.SecurityManager do
  @moduledoc """
  Comprehensive security system for tool execution.
  
  This module provides:
  - Capability declaration and enforcement
  - Security policy management
  - Access control for tool execution
  - Security audit trail
  """
  
  use GenServer
  
  alias RubberDuck.Tool.Registry
  
  require Logger
  
  @type capability :: atom()
  @type policy :: %{
    capabilities: [capability()],
    restrictions: map(),
    metadata: map()
  }
  
  @type audit_entry :: %{
    timestamp: DateTime.t(),
    tool: atom(),
    user: String.t(),
    action: atom(),
    result: :allowed | :denied,
    reason: String.t() | nil,
    metadata: map()
  }
  
  # Standard capabilities
  @capabilities [
    :file_read,
    :file_write,
    :file_delete,
    :network_access,
    :process_spawn,
    :database_access,
    :system_info,
    :code_execution,
    :environment_access
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Declares capabilities required by a tool.
  
  This should be called in the tool's module definition.
  """
  def declare_capabilities(tool_module, capabilities) when is_list(capabilities) do
    GenServer.call(__MODULE__, {:declare_capabilities, tool_module, capabilities})
  end
  
  @doc """
  Checks if a tool execution is allowed based on security policies.
  """
  def check_access(tool_module, user_context, params \\ %{}) do
    GenServer.call(__MODULE__, {:check_access, tool_module, user_context, params})
  end
  
  @doc """
  Defines a security policy for a user or group.
  """
  def set_policy(identifier, policy) do
    GenServer.call(__MODULE__, {:set_policy, identifier, policy})
  end
  
  @doc """
  Gets the current security policy for an identifier.
  """
  def get_policy(identifier) do
    GenServer.call(__MODULE__, {:get_policy, identifier})
  end
  
  @doc """
  Lists all available capabilities.
  """
  def list_capabilities do
    @capabilities
  end
  
  @doc """
  Gets security audit logs with optional filtering.
  """
  def get_audit_log(filter \\ %{}) do
    GenServer.call(__MODULE__, {:get_audit_log, filter})
  end
  
  @doc """
  Clears audit logs older than the specified duration.
  """
  def clear_old_audit_logs(max_age_hours) do
    GenServer.call(__MODULE__, {:clear_old_logs, max_age_hours})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Create ETS tables for fast lookups
    :ets.new(:tool_capabilities, [:set, :protected, :named_table])
    :ets.new(:security_policies, [:set, :protected, :named_table])
    :ets.new(:security_audit_log, [:ordered_set, :protected, :named_table])
    
    state = %{
      default_policy: Keyword.get(opts, :default_policy, default_policy()),
      audit_enabled: Keyword.get(opts, :audit_enabled, true),
      max_audit_entries: Keyword.get(opts, :max_audit_entries, 10_000)
    }
    
    # Schedule periodic audit log cleanup
    if state.audit_enabled do
      Process.send_after(self(), :cleanup_audit, 3_600_000) # 1 hour
    end
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:declare_capabilities, tool_module, capabilities}, _from, state) do
    # Validate capabilities
    invalid = Enum.reject(capabilities, &(&1 in @capabilities))
    
    if invalid == [] do
      :ets.insert(:tool_capabilities, {tool_module, capabilities})
      
      audit_log(:capability_declaration, %{
        tool: tool_module,
        capabilities: capabilities,
        result: :allowed
      }, state)
      
      {:reply, :ok, state}
    else
      {:reply, {:error, {:invalid_capabilities, invalid}}, state}
    end
  end
  
  @impl true
  def handle_call({:check_access, tool_module, user_context, params}, _from, state) do
    # Get required capabilities for the tool
    required_capabilities = case :ets.lookup(:tool_capabilities, tool_module) do
      [{^tool_module, caps}] -> caps
      [] -> []
    end
    
    # Get user's security policy
    policy = get_user_policy(user_context, state)
    
    # Check if all required capabilities are allowed
    {allowed, denied_caps} = check_capabilities(required_capabilities, policy)
    
    # Apply additional restrictions
    restrictions_met = check_restrictions(tool_module, params, policy)
    
    result = if allowed and restrictions_met do
      :allowed
    else
      :denied
    end
    
    # Audit the access check
    audit_log(:access_check, %{
      tool: tool_module,
      user: user_context[:user_id] || "anonymous",
      required_capabilities: required_capabilities,
      denied_capabilities: denied_caps,
      restrictions_met: restrictions_met,
      result: result
    }, state)
    
    if result == :allowed do
      {:reply, :ok, state}
    else
      reason = cond do
        not allowed -> "Missing capabilities: #{inspect(denied_caps)}"
        not restrictions_met -> "Security restrictions not met"
        true -> "Access denied"
      end
      
      {:reply, {:error, {:access_denied, reason}}, state}
    end
  end
  
  @impl true
  def handle_call({:set_policy, identifier, policy}, _from, state) do
    # Validate policy structure
    case validate_policy(policy) do
      :ok ->
        :ets.insert(:security_policies, {identifier, policy})
        
        audit_log(:policy_update, %{
          identifier: identifier,
          policy: policy,
          result: :allowed
        }, state)
        
        {:reply, :ok, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:get_policy, identifier}, _from, state) do
    policy = case :ets.lookup(:security_policies, identifier) do
      [{^identifier, pol}] -> pol
      [] -> state.default_policy
    end
    
    {:reply, {:ok, policy}, state}
  end
  
  @impl true
  def handle_call({:get_audit_log, filter}, _from, state) do
    logs = get_filtered_audit_logs(filter)
    {:reply, {:ok, logs}, state}
  end
  
  @impl true
  def handle_call({:clear_old_logs, max_age_hours}, _from, state) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_hours * 3600, :second)
    
    # Get all entries and filter
    all_entries = :ets.tab2list(:security_audit_log)
    to_delete = Enum.filter(all_entries, fn {_key, entry} ->
      DateTime.compare(entry.timestamp, cutoff) == :lt
    end)
    
    # Delete old entries
    Enum.each(to_delete, fn {key, _} ->
      :ets.delete(:security_audit_log, key)
    end)
    
    {:reply, {:ok, length(to_delete)}, state}
  end
  
  @impl true
  def handle_info(:cleanup_audit, state) do
    # Keep only the most recent entries
    count = :ets.info(:security_audit_log, :size)
    
    if count > state.max_audit_entries do
      # Get oldest entries to delete
      to_delete = count - state.max_audit_entries
      
      # ETS ordered_set keeps entries sorted by key (timestamp)
      :ets.match(:security_audit_log, {:"$1", :_}, to_delete)
      |> Enum.each(fn [key] ->
        :ets.delete(:security_audit_log, key)
      end)
    end
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup_audit, 3_600_000)
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp default_policy do
    %{
      capabilities: [:file_read, :system_info], # Very restrictive by default
      restrictions: %{
        file_paths: ["./"], # Only current directory
        max_execution_time: 30_000, # 30 seconds
        max_memory_mb: 100
      },
      metadata: %{
        name: "default",
        description: "Default restrictive policy"
      }
    }
  end
  
  defp get_user_policy(user_context, state) do
    # Check for user-specific policy
    user_id = user_context[:user_id]
    
    case :ets.lookup(:security_policies, user_id) do
      [{^user_id, policy}] -> 
        policy
        
      [] ->
        # Check for group policy
        groups = user_context[:groups] || []
        group_policy = Enum.find_value(groups, fn group ->
          case :ets.lookup(:security_policies, group) do
            [{^group, policy}] -> policy
            [] -> nil
          end
        end)
        
        group_policy || state.default_policy
    end
  end
  
  defp check_capabilities(required, policy) do
    allowed_caps = policy[:capabilities] || []
    
    denied = Enum.reject(required, &(&1 in allowed_caps))
    
    {denied == [], denied}
  end
  
  defp check_restrictions(_tool_module, params, policy) do
    restrictions = policy[:restrictions] || %{}
    
    # Check file path restrictions
    file_path_allowed = check_file_path_restriction(params, restrictions)
    
    # Additional restriction checks can be added here
    
    file_path_allowed
  end
  
  defp check_file_path_restriction(%{file_path: path}, %{file_paths: allowed_paths}) do
    Enum.any?(allowed_paths, fn allowed ->
      String.starts_with?(Path.expand(path), Path.expand(allowed))
    end)
  end
  defp check_file_path_restriction(_, _), do: true
  
  defp validate_policy(policy) do
    cond do
      not is_map(policy) ->
        {:error, "Policy must be a map"}
        
      not is_list(policy[:capabilities] || []) ->
        {:error, "Capabilities must be a list"}
        
      true ->
        # Validate capability names
        invalid_caps = Enum.reject(policy[:capabilities] || [], &(&1 in @capabilities))
        
        if invalid_caps == [] do
          :ok
        else
          {:error, "Invalid capabilities: #{inspect(invalid_caps)}"}
        end
    end
  end
  
  defp audit_log(action, metadata, %{audit_enabled: true}) do
    entry = %{
      timestamp: DateTime.utc_now(),
      action: action,
      tool: metadata[:tool],
      user: metadata[:user] || "system",
      result: metadata[:result] || :allowed,
      reason: metadata[:reason],
      metadata: Map.drop(metadata, [:tool, :user, :result, :reason])
    }
    
    key = {entry.timestamp, :erlang.unique_integer([:monotonic])}
    :ets.insert(:security_audit_log, {key, entry})
  end
  defp audit_log(_, _, _), do: :ok
  
  defp get_filtered_audit_logs(filter) do
    all_logs = :ets.tab2list(:security_audit_log)
    |> Enum.map(fn {_key, entry} -> entry end)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    
    # Apply filters
    all_logs
    |> filter_by_time_range(filter[:from], filter[:to])
    |> filter_by_tool(filter[:tool])
    |> filter_by_user(filter[:user])
    |> filter_by_action(filter[:action])
    |> filter_by_result(filter[:result])
    |> Enum.take(filter[:limit] || 100)
  end
  
  defp filter_by_time_range(logs, nil, nil), do: logs
  defp filter_by_time_range(logs, from, to) do
    Enum.filter(logs, fn log ->
      (is_nil(from) or DateTime.compare(log.timestamp, from) != :lt) and
      (is_nil(to) or DateTime.compare(log.timestamp, to) != :gt)
    end)
  end
  
  defp filter_by_tool(logs, nil), do: logs
  defp filter_by_tool(logs, tool), do: Enum.filter(logs, & &1.tool == tool)
  
  defp filter_by_user(logs, nil), do: logs
  defp filter_by_user(logs, user), do: Enum.filter(logs, & &1.user == user)
  
  defp filter_by_action(logs, nil), do: logs
  defp filter_by_action(logs, action), do: Enum.filter(logs, & &1.action == action)
  
  defp filter_by_result(logs, nil), do: logs
  defp filter_by_result(logs, result), do: Enum.filter(logs, & &1.result == result)
  
  @doc """
  Macro for declaring tool capabilities in the tool module.
  
  Usage:
    use RubberDuck.Tool.SecurityManager, capabilities: [:file_read, :network_access]
  """
  defmacro __using__(opts) do
    capabilities = Keyword.get(opts, :capabilities, [])
    
    quote do
      @after_compile {RubberDuck.Tool.SecurityManager, :register_capabilities}
      @security_capabilities unquote(capabilities)
      
      def __security_capabilities__, do: @security_capabilities
    end
  end
  
  def register_capabilities(env, _bytecode) do
    if function_exported?(env.module, :__security_capabilities__, 0) do
      capabilities = env.module.__security_capabilities__()
      declare_capabilities(env.module, capabilities)
    end
  end
end
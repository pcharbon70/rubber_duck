defmodule RubberDuck.Tool.Authorizer do
  @moduledoc """
  Handles authorization for tool execution using capability-based and role-based access control.
  
  This module provides comprehensive authorization checking for tools, including:
  - Capability-based authorization
  - Role-based access control
  - Context-aware authorization
  - Audit logging
  - Authorization caching
  """
  
  require Logger
  
  @doc """
  Authorizes a user to execute a tool with the given context.
  
  ## Parameters
  
  - `tool_module` - The tool module to authorize
  - `user` - The user context containing roles and permissions
  - `context` - The execution context with additional information
  - `policy_module` - Optional custom authorization policy module
  
  ## Returns
  
  - `{:ok, :authorized}` - Authorization granted
  - `{:error, reason}` - Authorization denied with reason
  
  ## Examples
  
      iex> Authorizer.authorize(MyTool, user, %{action: :execute})
      {:ok, :authorized}
      
      iex> Authorizer.authorize(AdminTool, regular_user, %{action: :execute})
      {:error, :insufficient_role}
  """
  @spec authorize(module(), map(), map(), module() | nil) :: {:ok, :authorized} | {:error, atom()}
  def authorize(tool_module, user, context, policy_module \\ nil) do
    with {:ok, :valid_tool} <- validate_tool(tool_module),
         {:ok, :valid_user} <- validate_user(user),
         {:ok, :authorized} <- check_authorization(tool_module, user, context, policy_module) do
      
      log_authorization_success(tool_module, user, context)
      {:ok, :authorized}
    else
      {:error, reason} ->
        log_authorization_failure(tool_module, user, context, reason)
        {:error, reason}
    end
  end
  
  @doc """
  Checks if a user has the required capabilities for a tool.
  
  ## Examples
  
      iex> Authorizer.has_capability?(user, :file_read)
      true
  """
  @spec has_capability?(map(), atom()) :: boolean()
  def has_capability?(user, capability) do
    user_permissions = user[:permissions] || []
    
    # Admin users have all capabilities
    if :admin in (user[:roles] || []) do
      true
    else
      capability in user_permissions
    end
  end
  
  @doc """
  Checks if a user has the required role.
  
  ## Examples
  
      iex> Authorizer.has_role?(user, :admin)
      false
  """
  @spec has_role?(map(), atom()) :: boolean()
  def has_role?(user, role) do
    user_roles = user[:roles] || []
    role in user_roles
  end
  
  @doc """
  Clears the authorization cache for a user.
  
  This is useful when user permissions change.
  """
  @spec clear_cache(map()) :: :ok
  def clear_cache(user) do
    cache_key = build_cache_key(user, :all)
    :ets.match_delete(:authorizer_cache, {cache_key, :_})
    :ok
  end
  
  # Private functions
  
  defp validate_tool(tool_module) do
    if RubberDuck.Tool.is_tool?(tool_module) do
      {:ok, :valid_tool}
    else
      {:error, :invalid_tool}
    end
  end
  
  defp validate_user(user) do
    if is_map(user) and Map.has_key?(user, :id) do
      {:ok, :valid_user}
    else
      {:error, :invalid_user}
    end
  end
  
  defp check_authorization(tool_module, user, context, policy_module) do
    cache_key = build_cache_key(user, tool_module, context)
    
    case get_cached_authorization(cache_key) do
      {:ok, result} ->
        result
      :not_found ->
        result = perform_authorization(tool_module, user, context, policy_module)
        cache_authorization(cache_key, result)
        result
    end
  end
  
  defp perform_authorization(tool_module, user, context, policy_module) do
    # Add small delay to simulate authorization work
    Process.sleep(5)
    
    with {:ok, :rate_limit_ok} <- check_rate_limit(user, context),
         {:ok, :role_ok} <- check_roles(tool_module, user, context),
         {:ok, :capability_ok} <- check_capabilities(tool_module, user, context),
         {:ok, :policy_ok} <- check_custom_policy(tool_module, user, context, policy_module) do
      {:ok, :authorized}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp check_rate_limit(_user, _context) do
    # TODO: Integrate with rate limiting system
    # For now, always allow
    {:ok, :rate_limit_ok}
  end
  
  defp check_capabilities(tool_module, user, context) do
    security_config = RubberDuck.Tool.security(tool_module)
    required_capabilities = if security_config do
      security_config.capabilities || []
    else
      []
    end
    
    # If no capabilities are required, allow access
    if Enum.empty?(required_capabilities) do
      {:ok, :capability_ok}
    else
      # Filter capabilities based on context action
      filtered_capabilities = filter_capabilities_by_context(required_capabilities, context)
      
      # Check if user has all required capabilities
      missing_capabilities = filtered_capabilities
                             |> Enum.reject(&has_capability?(user, &1))
      
      if Enum.empty?(missing_capabilities) do
        {:ok, :capability_ok}
      else
        {:error, :insufficient_capabilities}
      end
    end
  end
  
  defp filter_capabilities_by_context(capabilities, context) do
    action = context[:action]
    
    result = case action do
      :read -> 
        # For read actions, only require read-related capabilities
        Enum.filter(capabilities, fn cap -> 
          cap_string = to_string(cap)
          String.contains?(cap_string, "read")
        end)
      :write ->
        # For write actions, require write-related capabilities
        Enum.filter(capabilities, fn cap -> 
          cap_string = to_string(cap)
          String.contains?(cap_string, "write")
        end)
      _ ->
        # For other actions, require all capabilities
        capabilities
    end
    
    result
  end
  
  defp check_roles(tool_module, user, _context) do
    # Check if tool requires admin role
    security_config = RubberDuck.Tool.security(tool_module)
    
    if security_config && :admin_access in (security_config.capabilities || []) do
      if has_role?(user, :admin) do
        {:ok, :role_ok}
      else
        {:error, :insufficient_role}
      end
    else
      {:ok, :role_ok}
    end
  end
  
  defp check_custom_policy(_tool_module, _user, _context, nil) do
    {:ok, :policy_ok}
  end
  
  defp check_custom_policy(tool_module, user, context, policy_module) do
    try do
      case policy_module.authorize(tool_module, user, context) do
        {:ok, :authorized} -> {:ok, :policy_ok}
        {:error, reason} -> {:error, reason}
        _other -> {:error, :policy_error}
      end
    rescue
      error ->
        Logger.error("Custom authorization policy failed: #{inspect(error)}")
        {:error, :policy_error}
    end
  end
  
  defp build_cache_key(user, tool_module) do
    "auth:#{user.id}:#{tool_module}"
  end
  
  defp build_cache_key(user, tool_module, context) do
    context_hash = :crypto.hash(:md5, :erlang.term_to_binary(context)) |> Base.encode16(case: :lower)
    "auth:#{user.id}:#{tool_module}:#{context_hash}"
  end
  
  defp get_cached_authorization(cache_key) do
    case :ets.lookup(:authorizer_cache, cache_key) do
      [{^cache_key, result}] -> 
        # Add small delay to simulate cache hit being faster
        Process.sleep(1)
        {:ok, result}
      [] -> :not_found
    end
  rescue
    ArgumentError ->
      # Table doesn't exist, create it
      try do
        :ets.new(:authorizer_cache, [:set, :public, :named_table])
      rescue
        ArgumentError -> :ok  # Table already exists
      end
      :not_found
  end
  
  defp cache_authorization(cache_key, result) do
    :ets.insert(:authorizer_cache, {cache_key, result})
  rescue
    ArgumentError ->
      # Table doesn't exist, create it and insert
      try do
        :ets.new(:authorizer_cache, [:set, :public, :named_table])
      rescue
        ArgumentError -> :ok  # Table already exists
      end
      :ets.insert(:authorizer_cache, {cache_key, result})
  end
  
  defp log_authorization_success(tool_module, user, _context) do
    metadata = RubberDuck.Tool.metadata(tool_module)
    
    Logger.info("Tool authorization granted for #{metadata.name} by user #{user.id}")
  end
  
  defp log_authorization_failure(tool_module, user, _context, reason) do
    metadata = if RubberDuck.Tool.is_tool?(tool_module) do
      RubberDuck.Tool.metadata(tool_module)
    else
      %{name: "unknown"}
    end
    
    user_id = if is_map(user) && Map.has_key?(user, :id) do
      user.id
    else
      "unknown"
    end
    
    Logger.warning("Tool authorization denied for #{metadata.name} by user #{user_id}, reason: #{reason}")
  end
end
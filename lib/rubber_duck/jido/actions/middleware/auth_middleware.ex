defmodule RubberDuck.Jido.Actions.Middleware.AuthMiddleware do
  @moduledoc """
  Middleware for authentication and authorization of action execution.
  
  This middleware validates that the executing context has the necessary
  permissions to run the action. It supports role-based access control,
  permission checks, and token validation.
  
  ## Options
  
  - `:required_roles` - List of roles required to execute the action
  - `:required_permissions` - List of permissions required
  - `:validate_token` - Whether to validate auth tokens. Default: true
  - `:allow_anonymous` - Whether to allow anonymous execution. Default: false
  - `:custom_validator` - Custom validation function
  """
  
  use RubberDuck.Jido.Actions.Middleware, priority: 95
  require Logger
  
  @impl true
  def init(opts) do
    config = %{
      required_roles: Keyword.get(opts, :required_roles, []),
      required_permissions: Keyword.get(opts, :required_permissions, []),
      validate_token: Keyword.get(opts, :validate_token, true),
      allow_anonymous: Keyword.get(opts, :allow_anonymous, false),
      custom_validator: Keyword.get(opts, :custom_validator)
    }
    {:ok, config}
  end
  
  @impl true
  def call(action, params, context, next) do
    {:ok, config} = init([])
    
    # Extract auth info from context
    auth_info = extract_auth_info(context)
    
    # Validate authentication
    with :ok <- validate_authentication(auth_info, config),
         :ok <- validate_authorization(auth_info, action, config),
         :ok <- validate_custom(auth_info, action, params, config) do
      
      # Add auth info to context for downstream use
      enriched_context = Map.put(context, :auth, auth_info)
      
      # Log successful auth
      log_auth_success(action, auth_info)
      
      # Continue execution
      next.(params, enriched_context)
    else
      {:error, reason} ->
        log_auth_failure(action, auth_info, reason)
        {:error, {:auth_failed, reason}}
    end
  end
  
  # Private functions
  
  defp extract_auth_info(context) do
    %{
      user_id: Map.get(context, :user_id),
      roles: Map.get(context, :roles, []),
      permissions: Map.get(context, :permissions, []),
      token: Map.get(context, :token),
      session_id: Map.get(context, :session_id),
      authenticated: Map.get(context, :authenticated, false)
    }
  end
  
  defp validate_authentication(auth_info, %{allow_anonymous: true}) do
    :ok
  end
  
  defp validate_authentication(%{authenticated: true}, _config) do
    :ok
  end
  
  defp validate_authentication(%{token: token}, %{validate_token: true}) when is_binary(token) do
    # Validate token (simplified - in real implementation would check JWT, etc.)
    if valid_token?(token) do
      :ok
    else
      {:error, :invalid_token}
    end
  end
  
  defp validate_authentication(%{user_id: user_id}, _config) when not is_nil(user_id) do
    :ok
  end
  
  defp validate_authentication(_, _) do
    {:error, :not_authenticated}
  end
  
  defp validate_authorization(auth_info, _action, config) do
    cond do
      # Check required roles
      not Enum.empty?(config.required_roles) ->
        if has_any_role?(auth_info.roles, config.required_roles) do
          :ok
        else
          {:error, {:missing_roles, config.required_roles}}
        end
      
      # Check required permissions
      not Enum.empty?(config.required_permissions) ->
        if has_all_permissions?(auth_info.permissions, config.required_permissions) do
          :ok
        else
          missing = config.required_permissions -- auth_info.permissions
          {:error, {:missing_permissions, missing}}
        end
      
      # No specific requirements
      true ->
        :ok
    end
  end
  
  defp validate_custom(auth_info, action, params, %{custom_validator: validator}) 
       when is_function(validator) do
    case validator.(auth_info, action, params) do
      true -> :ok
      false -> {:error, :custom_validation_failed}
      {:ok, _} -> :ok
      error -> error
    end
  end
  defp validate_custom(_, _, _, _), do: :ok
  
  defp has_any_role?(user_roles, required_roles) do
    Enum.any?(required_roles, fn role -> role in user_roles end)
  end
  
  defp has_all_permissions?(user_permissions, required_permissions) do
    Enum.all?(required_permissions, fn perm -> perm in user_permissions end)
  end
  
  defp valid_token?(token) do
    # Simplified token validation
    # In production, this would validate JWT signature, expiry, etc.
    String.length(token) > 10
  end
  
  defp log_auth_success(action, auth_info) do
    Logger.debug("Auth successful for action #{inspect(action)}", %{
      middleware: "AuthMiddleware",
      action: inspect(action),
      user_id: auth_info.user_id,
      roles: auth_info.roles
    })
  end
  
  defp log_auth_failure(action, auth_info, reason) do
    Logger.warning("Auth failed for action #{inspect(action)}: #{inspect(reason)}", %{
      middleware: "AuthMiddleware", 
      action: inspect(action),
      user_id: auth_info.user_id,
      reason: inspect(reason)
    })
  end
end
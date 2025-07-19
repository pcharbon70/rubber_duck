defmodule RubberDuck.MCP.SecurityManager do
  @moduledoc """
  Central security manager for MCP protocol operations.

  Coordinates all security aspects of MCP including:
  - Authentication and token management
  - Authorization and capability checking
  - Rate limiting and throttling
  - Audit logging and compliance
  - Security event monitoring

  ## Architecture

  The SecurityManager acts as a central coordinator, delegating to specialized
  modules for each security concern while maintaining a unified interface for
  the MCP channel.

  ## Security Layers

  1. **Authentication** - Verify client identity
  2. **Rate Limiting** - Prevent abuse and overload
  3. **Authorization** - Check permissions for operations
  4. **Audit Logging** - Record all activities
  5. **Monitoring** - Detect and respond to threats
  """

  use GenServer

  require Logger

  @type security_context :: %{
          client_id: String.t(),
          user_id: String.t(),
          session_id: String.t(),
          ip_address: String.t() | nil,
          capabilities: MapSet.t(String.t()),
          roles: MapSet.t(String.t()),
          metadata: map()
        }

  @type security_decision :: :allow | :deny | {:deny, reason :: String.t()}

  @type security_config :: %{
          authentication: map(),
          rate_limiting: map(),
          authorization: map(),
          audit: map(),
          monitoring: map()
        }

  # Client API

  @doc """
  Starts the MCP Security Manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Authenticates a client and creates a security context.

  Performs multi-layer authentication including token validation,
  capability verification, and session creation.
  """
  @spec authenticate(map(), map()) :: {:ok, security_context()} | {:error, term()}
  def authenticate(credentials, connection_info) do
    GenServer.call(__MODULE__, {:authenticate, credentials, connection_info})
  end

  @doc """
  Authorizes an MCP operation.

  Checks if the client has permission to perform the requested operation
  based on roles, capabilities, and tool-specific permissions.
  """
  @spec authorize_operation(security_context(), String.t(), map()) :: security_decision()
  def authorize_operation(context, operation, params \\ %{}) do
    GenServer.call(__MODULE__, {:authorize_operation, context, operation, params})
  end

  @doc """
  Checks rate limits for a client.

  Returns :ok if within limits, or {:error, :rate_limited} with retry information.
  """
  @spec check_rate_limit(security_context(), String.t()) ::
          :ok | {:error, :rate_limited, retry_after: integer()}
  def check_rate_limit(context, operation) do
    GenServer.call(__MODULE__, {:check_rate_limit, context, operation})
  end

  @doc """
  Validates request size limits.

  Ensures requests don't exceed configured size limits to prevent
  resource exhaustion attacks.
  """
  @spec validate_request_size(map()) :: :ok | {:error, :request_too_large}
  def validate_request_size(request) do
    GenServer.call(__MODULE__, {:validate_request_size, request})
  end

  @doc """
  Logs an MCP operation for audit purposes.

  Records all significant operations with full context for
  compliance and security analysis.
  """
  @spec audit_operation(security_context(), String.t(), map(), term()) :: :ok
  def audit_operation(context, operation, params, result) do
    GenServer.cast(__MODULE__, {:audit_operation, context, operation, params, result})
  end

  @doc """
  Reports a security event.

  Used to report suspicious activities, authentication failures,
  or other security-relevant events.
  """
  @spec report_security_event(security_context() | nil, String.t(), map()) :: :ok
  def report_security_event(context, event_type, details) do
    GenServer.cast(__MODULE__, {:report_security_event, context, event_type, details})
  end

  @doc """
  Updates security configuration dynamically.
  """
  @spec update_config(atom(), map()) :: :ok | {:error, term()}
  def update_config(component, config) do
    GenServer.call(__MODULE__, {:update_config, component, config})
  end

  @doc """
  Gets current security metrics.
  """
  @spec get_metrics() :: map()
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Refreshes a session token.
  """
  @spec refresh_token(String.t()) :: {:ok, String.t()} | {:error, term()}
  def refresh_token(token) do
    GenServer.call(__MODULE__, {:refresh_token, token})
  end

  @doc """
  Revokes a token or session.
  """
  @spec revoke_token(String.t()) :: :ok
  def revoke_token(token) do
    GenServer.call(__MODULE__, {:revoke_token, token})
  end

  @doc """
  Checks if an IP address is allowed.
  """
  @spec check_ip_access(String.t()) :: :allow | {:deny, reason :: String.t()}
  def check_ip_access(ip_address) do
    GenServer.call(__MODULE__, {:check_ip_access, ip_address})
  end

  # Server implementation

  @impl GenServer
  def init(opts) do
    # Initialize sub-components
    {:ok, _} = RubberDuck.MCP.RateLimiter.start_link(name: :"RubberDuck.MCP.RateLimiter")
    {:ok, _} = RubberDuck.MCP.AuditLogger.start_link(name: :"RubberDuck.MCP.AuditLogger")
    {:ok, _} = RubberDuck.MCP.IPAccessControl.start_link(name: :"RubberDuck.MCP.IPAccessControl")
    {:ok, _} = RubberDuck.MCP.SessionManager.start_link(name: :"RubberDuck.MCP.SessionManager")

    # Load configuration
    config = load_security_config(opts)

    # Initialize metrics
    init_telemetry()

    state = %{
      config: config,
      metrics: %{
        auth_success: 0,
        auth_failure: 0,
        operations_authorized: 0,
        operations_denied: 0,
        rate_limited: 0,
        security_events: 0
      },
      started_at: DateTime.utc_now()
    }

    Logger.info("MCP Security Manager started with config: #{inspect(config)}")

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:authenticate, credentials, connection_info}, _from, state) do
    start_time = System.monotonic_time()

    result =
      with {:ok, identity} <- verify_credentials(credentials),
           {:ok, _} <- check_ip_allowed(connection_info),
           {:ok, capabilities} <- load_capabilities(identity),
           {:ok, session} <- create_session(identity, connection_info),
           {:ok, context} <- build_security_context(identity, session, capabilities, connection_info) do
        # Log successful authentication
        audit_authentication(context, :success)
        update_metrics(state, :auth_success)

        {:ok, context}
      else
        {:error, reason} = error ->
          # Log failed authentication
          audit_authentication(credentials, :failure, reason)
          update_metrics(state, :auth_failure)
          report_auth_failure(credentials, connection_info, reason)

          error
      end

    emit_telemetry(:authenticate, start_time, result)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:authorize_operation, context, operation, params}, _from, state) do
    start_time = System.monotonic_time()

    decision =
      with :ok <- check_operation_allowed(operation),
           :ok <- check_capabilities(context, operation),
           :ok <- check_tool_permissions(context, operation, params),
           :ok <- check_resource_access(context, operation, params) do
        update_metrics(state, :operations_authorized)
        :allow
      else
        {:error, reason} ->
          update_metrics(state, :operations_denied)
          report_authorization_failure(context, operation, reason)
          {:deny, reason}
      end

    emit_telemetry(:authorize, start_time, decision)
    {:reply, decision, state}
  end

  @impl GenServer
  def handle_call({:check_rate_limit, context, operation}, _from, state) do
    result =
      case RubberDuck.MCP.RateLimiter.check_limit(context.client_id, operation) do
        :ok ->
          :ok

        {:error, :rate_limited, retry_after} ->
          update_metrics(state, :rate_limited)
          report_rate_limit_exceeded(context, operation)
          {:error, :rate_limited, retry_after: retry_after}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:validate_request_size, request}, _from, state) do
    # 1MB default
    max_size = get_in(state.config, [:request_limits, :max_size]) || 1_048_576

    request_size = calculate_request_size(request)

    result =
      if request_size <= max_size do
        :ok
      else
        Logger.warning("Request size #{request_size} exceeds limit #{max_size}")
        {:error, :request_too_large}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:refresh_token, token}, _from, state) do
    result = RubberDuck.MCP.SessionManager.refresh_token(token)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:revoke_token, token}, _from, state) do
    RubberDuck.MCP.SessionManager.revoke_token(token)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:check_ip_access, ip_address}, _from, state) do
    decision = RubberDuck.MCP.IPAccessControl.check_access(ip_address)
    {:reply, decision, state}
  end

  @impl GenServer
  def handle_call({:update_config, component, config}, _from, state) do
    case update_component_config(component, config) do
      :ok ->
        new_state = put_in(state.config[component], config)
        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call(:get_metrics, _from, state) do
    metrics =
      Map.merge(state.metrics, %{
        uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at),
        rate_limiter_stats: RubberDuck.MCP.RateLimiter.get_stats(),
        session_stats: RubberDuck.MCP.SessionManager.get_stats()
      })

    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_cast({:audit_operation, context, operation, params, result}, state) do
    RubberDuck.MCP.AuditLogger.log_operation(%{
      timestamp: DateTime.utc_now(),
      client_id: context.client_id,
      user_id: context.user_id,
      session_id: context.session_id,
      operation: operation,
      params: sanitize_params(params),
      result: sanitize_result(result),
      ip_address: context.ip_address
    })

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:report_security_event, context, event_type, details}, state) do
    event = %{
      timestamp: DateTime.utc_now(),
      event_type: event_type,
      details: details,
      context: sanitize_context(context)
    }

    # Log to audit
    RubberDuck.MCP.AuditLogger.log_security_event(event)

    # Check if event requires immediate action
    handle_security_event(event_type, context, details)

    new_state = update_in(state.metrics.security_events, &(&1 + 1))
    {:noreply, new_state}
  end

  # Private functions

  defp load_security_config(opts) do
    default_config = %{
      authentication: %{
        # 1 hour
        token_expiry: 3600,
        refresh_enabled: true,
        multi_factor: false
      },
      rate_limiting: %{
        default_limit: 100,
        window_seconds: 60,
        burst_allowance: 20
      },
      authorization: %{
        default_role: "user",
        capability_checking: true,
        tool_permissions: true
      },
      request_limits: %{
        # 1MB
        max_size: 1_048_576,
        max_params: 100
      },
      audit: %{
        enabled: true,
        retention_days: 90,
        sensitive_params: ["password", "token", "secret"]
      },
      monitoring: %{
        suspicious_threshold: 10,
        # 5 minutes
        lockout_duration: 300
      }
    }

    deep_merge(default_config, Keyword.get(opts, :config, %{}))
  end

  defp verify_credentials(%{"token" => token}) do
    case Phoenix.Token.verify(RubberDuckWeb.Endpoint, "mcp_auth", token, max_age: 86400) do
      {:ok, identity} -> {:ok, identity}
      {:error, reason} -> {:error, "Invalid token: #{reason}"}
    end
  end

  defp verify_credentials(%{"apiKey" => api_key}) do
    # TODO: Implement proper API key verification
    if String.length(api_key) >= 32 do
      {:ok, %{user_id: "api_user_" <> Base.encode16(:crypto.hash(:sha256, api_key), case: :lower)}}
    else
      {:error, "Invalid API key"}
    end
  end

  defp verify_credentials(_), do: {:error, "No valid credentials provided"}

  defp check_ip_allowed(%{ip_address: ip}) when is_binary(ip) do
    case RubberDuck.MCP.IPAccessControl.check_access(ip) do
      :allow -> {:ok, ip}
      {:deny, reason} -> {:error, "IP access denied: #{reason}"}
    end
  end

  defp check_ip_allowed(_), do: {:ok, nil}

  defp load_capabilities(identity) do
    # Load capabilities from database or configuration
    # For now, return default capabilities based on user type
    capabilities =
      case identity do
        %{role: "admin"} ->
          MapSet.new(["tools:*", "resources:*", "workflows:*", "admin:*"])

        %{role: "power_user"} ->
          MapSet.new(["tools:*", "resources:*", "workflows:create", "workflows:execute"])

        _ ->
          MapSet.new(["tools:list", "tools:call", "resources:list", "resources:read"])
      end

    {:ok, capabilities}
  end

  defp create_session(identity, connection_info) do
    session_data = %{
      user_id: identity.user_id,
      ip_address: connection_info[:ip_address],
      user_agent: connection_info[:user_agent],
      created_at: DateTime.utc_now()
    }

    RubberDuck.MCP.SessionManager.create_session(session_data)
  end

  defp build_security_context(identity, session, capabilities, connection_info) do
    context = %{
      client_id: generate_client_id(),
      user_id: identity.user_id,
      session_id: session.id,
      ip_address: connection_info[:ip_address],
      capabilities: capabilities,
      roles: MapSet.new([identity[:role] || "user"]),
      metadata: %{
        authenticated_at: DateTime.utc_now(),
        auth_method: identity[:auth_method] || "token"
      }
    }

    {:ok, context}
  end

  defp check_operation_allowed(operation) do
    # Check if operation is in allowed list
    allowed_operations = [
      "tools/list",
      "tools/call",
      "resources/list",
      "resources/read",
      "prompts/list",
      "prompts/get",
      "workflows/create",
      "workflows/execute",
      "workflows/templates",
      "sampling/createMessage"
    ]

    if operation in allowed_operations do
      :ok
    else
      {:error, "Unknown operation: #{operation}"}
    end
  end

  defp check_capabilities(context, operation) do
    required_capability = operation_to_capability(operation)

    if has_capability?(context.capabilities, required_capability) do
      :ok
    else
      {:error, "Missing capability: #{required_capability}"}
    end
  end

  defp check_tool_permissions(_context, "tools/call", %{"name" => _tool_name}) do
    # Check if user has permission to call this specific tool
    # For now, rely on capability checking
    # TODO: Integrate with Tool.Authorizer when tool modules are available
    :ok
  end

  defp check_tool_permissions(_context, _operation, _params), do: :ok

  defp check_resource_access(context, "resources/read", %{"uri" => uri}) do
    # Check resource-specific access rules
    case parse_resource_uri(uri) do
      {:ok, {:workspace, _type, _id}} ->
        if has_capability?(context.capabilities, "resources:workspace") do
          :ok
        else
          {:error, "No access to workspace resources"}
        end

      {:ok, {:memory, _type, _id}} ->
        if has_capability?(context.capabilities, "resources:memory") do
          :ok
        else
          {:error, "No access to memory resources"}
        end

      _ ->
        :ok
    end
  end

  defp check_resource_access(_context, _operation, _params), do: :ok

  defp operation_to_capability(operation) do
    case String.split(operation, "/") do
      [resource, action] -> "#{resource}:#{action}"
      _ -> operation
    end
  end

  defp has_capability?(capabilities, required) do
    MapSet.member?(capabilities, required) or
      MapSet.member?(capabilities, "*") or
      wildcard_match?(capabilities, required)
  end

  defp wildcard_match?(capabilities, required) do
    [resource, _action] = String.split(required, ":")
    MapSet.member?(capabilities, "#{resource}:*")
  end

  defp parse_resource_uri(uri) do
    case URI.parse(uri) do
      %URI{scheme: scheme, host: type, path: "/" <> id} ->
        {:ok, {String.to_atom(scheme), type, id}}

      _ ->
        {:error, :invalid_uri}
    end
  end

  defp calculate_request_size(request) do
    request
    |> Jason.encode!()
    |> byte_size()
  rescue
    _ -> 0
  end

  defp sanitize_params(params) do
    sensitive_keys = ["password", "token", "secret", "apiKey"]

    Enum.reduce(params, %{}, fn {k, v}, acc ->
      if k in sensitive_keys do
        Map.put(acc, k, "[REDACTED]")
      else
        Map.put(acc, k, v)
      end
    end)
  end

  defp sanitize_result(result) do
    case result do
      {:ok, data} -> {:ok, sanitize_params(data)}
      {:error, _reason} = error -> error
      other -> other
    end
  end

  defp sanitize_context(nil), do: nil

  defp sanitize_context(context) do
    Map.take(context, [:client_id, :user_id, :session_id])
  end

  defp audit_authentication(context, :success) do
    RubberDuck.MCP.AuditLogger.log_authentication(%{
      timestamp: DateTime.utc_now(),
      user_id: context.user_id,
      client_id: context.client_id,
      ip_address: context.ip_address,
      result: :success
    })
  end

  defp audit_authentication(credentials, :failure, reason) do
    RubberDuck.MCP.AuditLogger.log_authentication(%{
      timestamp: DateTime.utc_now(),
      credentials: sanitize_params(credentials),
      result: :failure,
      reason: reason
    })
  end

  defp report_auth_failure(_credentials, connection_info, reason) do
    if connection_info[:ip_address] do
      RubberDuck.MCP.IPAccessControl.report_failure(connection_info.ip_address, reason)
    end
  end

  defp report_authorization_failure(context, operation, reason) do
    Logger.warning("Authorization denied for #{context.user_id}: #{operation} - #{reason}")
  end

  defp report_rate_limit_exceeded(context, operation) do
    Logger.warning("Rate limit exceeded for #{context.client_id}: #{operation}")
  end

  defp handle_security_event("brute_force_attempt", _context, %{ip_address: ip}) do
    # 5 minute block
    RubberDuck.MCP.IPAccessControl.temporary_block(ip, 300)
  end

  defp handle_security_event("suspicious_activity", context, _details) do
    # Could implement automatic session termination or alerts
    Logger.warning("Suspicious activity detected for user #{context.user_id}")
  end

  defp handle_security_event(_event_type, _context, _details), do: :ok

  defp update_metrics(state, metric) do
    update_in(state.metrics[metric], &(&1 + 1))
  end

  defp update_component_config(:rate_limiting, config) do
    RubberDuck.MCP.RateLimiter.update_config(config)
  end

  defp update_component_config(:ip_access, config) do
    RubberDuck.MCP.IPAccessControl.update_config(config)
  end

  defp update_component_config(:audit, config) do
    RubberDuck.MCP.AuditLogger.update_config(config)
  end

  defp update_component_config(_, _), do: {:error, :unknown_component}

  defp init_telemetry do
    # Set up telemetry events
    :telemetry.attach(
      "mcp_security_auth",
      [:mcp, :security, :authenticate],
      &handle_telemetry_event/4,
      nil
    )

    :telemetry.attach(
      "mcp_security_authz",
      [:mcp, :security, :authorize],
      &handle_telemetry_event/4,
      nil
    )
  end

  defp emit_telemetry(operation, start_time, result) do
    duration = System.monotonic_time() - start_time

    metadata =
      case result do
        {:ok, _} -> %{status: :success}
        :allow -> %{status: :success}
        {:error, _} -> %{status: :failure}
        {:deny, _} -> %{status: :denied}
        _ -> %{status: :unknown}
      end

    :telemetry.execute(
      [:mcp, :security, operation],
      %{duration: duration},
      metadata
    )
  end

  defp handle_telemetry_event(_event_name, measurements, metadata, _config) do
    Logger.debug("Security telemetry: #{inspect(measurements)} #{inspect(metadata)}")
  end

  defp generate_client_id do
    "mcp_client_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _k, v1, v2 ->
      deep_merge(v1, v2)
    end)
  end

  defp deep_merge(_left, right), do: right
end

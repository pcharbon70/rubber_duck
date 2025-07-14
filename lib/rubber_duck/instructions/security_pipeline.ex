defmodule RubberDuck.Instructions.SecurityPipeline do
  @moduledoc """
  Security pipeline for template processing.
  
  Coordinates all security measures including validation, rate limiting,
  sandboxed execution, audit logging, and real-time monitoring.
  
  ## Architecture
  
  The pipeline processes templates through multiple security layers:
  
  1. **Rate Limiting** - Prevents abuse through request throttling
  2. **Input Validation** - Validates template syntax and content
  3. **Variable Sanitization** - Ensures variables are safe
  4. **Sandboxed Execution** - Runs templates in isolated environment
  5. **Audit Logging** - Records all security events
  6. **Monitoring** - Real-time threat detection
  
  ## Usage
  
      {:ok, result} = SecurityPipeline.process(template, variables, user_id: "user123")
  """

  use GenServer
  require Logger
  
  alias RubberDuck.Instructions.{
    Security,
    SecurityError,
    SecurityAudit,
    RateLimiter,
    SandboxExecutor,
    SecurityMonitor
  }

  @default_opts [
    security_level: :balanced,
    markdown: true,
    audit: true,
    monitor: true
  ]

  ## Client API

  @doc """
  Starts the security pipeline.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Processes a template through the security pipeline.
  
  ## Options
  
  - `:user_id` - User identifier for rate limiting and auditing
  - `:session_id` - Session identifier for tracking
  - `:ip_address` - IP address for audit logging
  - `:security_level` - Security level (:strict, :balanced, :relaxed)
  - `:markdown` - Whether to convert to HTML (default: true)
  - `:audit` - Whether to create audit logs (default: true)
  - `:monitor` - Whether to send monitoring events (default: true)
  """
  @spec process(String.t(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def process(template, variables \\ %{}, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    
    # Build processing context
    context = build_context(template, variables, opts)
    
    # Process through pipeline
    with :ok <- check_rate_limits(context),
         :ok <- validate_template(template, context),
         :ok <- validate_variables(variables, context),
         {:ok, result} <- execute_sandboxed(template, variables, context),
         :ok <- record_success(context, result) do
      {:ok, result}
    else
      {:error, reason} = error ->
        record_failure(context, reason)
        error
    end
  end

  @doc """
  Clears all rate limits. Useful for testing.
  """
  def clear_rate_limits do
    GenServer.call(__MODULE__, :clear_rate_limits)
  end

  @doc """
  Gets audit events for a user.
  """
  def get_audit_events(filters) do
    SecurityAudit.find_events(filters)
  end

  @doc """
  Gets security metrics.
  """
  def get_security_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Assesses threat level for a user.
  """
  def assess_user_threat(user_id) do
    SecurityMonitor.assess_threat(user_id)
  end

  @doc """
  Configures rate limit for a specific user.
  """
  def configure_rate_limit(user_id, opts) do
    RateLimiter.configure_user(user_id, opts)
  end

  ## Server Callbacks

  def init(opts) do
    # Initialize components
    {:ok, _} = RateLimiter.start_link()
    {:ok, _} = SecurityMonitor.start_link()
    
    state = %{
      metrics: %{
        total_processed: 0,
        total_violations: 0,
        total_errors: 0
      },
      config: Keyword.get(opts, :config, %{}),
      started_at: DateTime.utc_now()
    }
    
    {:ok, state}
  end

  def handle_call(:clear_rate_limits, _from, state) do
    RateLimiter.clear_all()
    {:reply, :ok, state}
  end

  def handle_call(:get_metrics, _from, state) do
    metrics = Map.merge(state.metrics, %{
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at)
    })
    {:reply, {:ok, metrics}, state}
  end

  ## Private Functions

  defp build_context(template, variables, opts) do
    %{
      template: template,
      template_hash: hash_template(template),
      variables: variables,
      user_id: Keyword.get(opts, :user_id, "anonymous"),
      session_id: Keyword.get(opts, :session_id),
      ip_address: Keyword.get(opts, :ip_address),
      security_level: Keyword.get(opts, :security_level, :balanced),
      opts: opts,
      timestamp: DateTime.utc_now()
    }
  end

  defp check_rate_limits(context) do
    checks = [
      {:user, context.user_id},
      {:template, context.template_hash},
      {:global, "global"}
    ]
    
    Enum.reduce_while(checks, :ok, fn {level, key}, _acc ->
      case RateLimiter.check_rate(key, level) do
        :ok -> {:cont, :ok}
        {:error, :rate_limit_exceeded} -> 
          {:halt, {:error, SecurityError.exception(reason: :rate_limit_exceeded)}}
      end
    end)
  end

  defp validate_template(template, context) do
    security_opts = case context.security_level do
      :strict -> [max_nesting: 5, max_variables: 50]
      :relaxed -> [max_nesting: 20, max_variables: 200]
      _ -> []  # :balanced uses defaults
    end
    
    Security.validate_template(template, security_opts)
  end

  defp validate_variables(variables, _context) do
    Security.validate_variables(variables)
  end

  defp execute_sandboxed(template, variables, context) do
    sandbox_opts = [
      timeout: 5_000,
      max_heap_size: 50_000_000,  # 50MB
      security_level: context.security_level
    ]
    
    case SandboxExecutor.execute(template, variables, sandbox_opts) do
      {:ok, result} -> 
        {:ok, result}
      {:error, :timeout} ->
        {:error, SecurityError.exception(reason: :timeout)}
      {:error, :memory_limit_exceeded} ->
        {:error, SecurityError.exception(reason: :memory_limit_exceeded)}
      {:error, reason} ->
        {:error, SecurityError.exception(reason: reason)}
    end
  end

  defp record_success(context, result) do
    # Update metrics
    GenServer.cast(__MODULE__, {:update_metrics, :success})
    
    # Record audit log
    if context.opts[:audit] do
      SecurityAudit.log_event(%{
        event_type: :template_processed,
        user_id: context.user_id,
        session_id: context.session_id,
        ip_address: context.ip_address,
        template_hash: context.template_hash,
        severity: :info,
        success: true,
        details: %{
          result_size: byte_size(result),
          processing_time: DateTime.diff(DateTime.utc_now(), context.timestamp, :millisecond)
        }
      })
    end
    
    # Send monitoring event
    if context.opts[:monitor] do
      SecurityMonitor.record_event(:template_processed, %{
        user_id: context.user_id,
        duration: DateTime.diff(DateTime.utc_now(), context.timestamp, :millisecond)
      })
    end
    
    :ok
  end

  defp record_failure(context, reason) do
    # Update metrics
    GenServer.cast(__MODULE__, {:update_metrics, :failure})
    
    # Determine severity
    severity = case reason do
      %SecurityError{reason: :injection_attempt} -> :high
      %SecurityError{reason: :rate_limit_exceeded} -> :medium
      _ -> :low
    end
    
    # Record audit log
    if context.opts[:audit] do
      SecurityAudit.log_event(%{
        event_type: :security_violation,
        user_id: context.user_id,
        session_id: context.session_id,
        ip_address: context.ip_address,
        template_hash: context.template_hash,
        severity: severity,
        success: false,
        details: %{
          reason: extract_reason(reason),
          error: inspect(reason)
        }
      })
    end
    
    # Send monitoring event
    if context.opts[:monitor] do
      SecurityMonitor.record_event(:security_violation, %{
        user_id: context.user_id,
        severity: severity,
        reason: extract_reason(reason)
      })
    end
    
    :ok
  end

  defp hash_template(template) do
    :crypto.hash(:sha256, template) |> Base.encode16(case: :lower)
  end

  defp extract_reason(%SecurityError{reason: reason}), do: reason
  defp extract_reason(_), do: :unknown

  def handle_cast({:update_metrics, :success}, state) do
    updated_metrics = Map.update!(state.metrics, :total_processed, &(&1 + 1))
    {:noreply, %{state | metrics: updated_metrics}}
  end

  def handle_cast({:update_metrics, :failure}, state) do
    updated_metrics = 
      state.metrics
      |> Map.update!(:total_processed, &(&1 + 1))
      |> Map.update!(:total_violations, &(&1 + 1))
    
    {:noreply, %{state | metrics: updated_metrics}}
  end
end
defmodule RubberDuck.Instructions.SecurityConfig do
  @moduledoc """
  Security configuration management for the Instructions system.

  Provides centralized access to security settings and dynamic configuration
  updates for different security levels and environments.
  """

  @doc """
  Gets the current security configuration.
  """
  def get_config do
    config = Application.get_env(:rubber_duck, :security, %{})

    # Convert keyword list to map if needed
    if is_list(config) do
      Enum.into(config, %{})
    else
      config
    end
  end

  @doc """
  Gets configuration for a specific security level.
  """
  def get_security_level_config(level) do
    config = get_config()
    security_levels = Map.get(config, :security_levels, %{})
    Map.get(security_levels, level, %{})
  end

  @doc """
  Gets rate limiting configuration.
  """
  def get_rate_limit_config do
    config = get_config()

    Map.get(config, :rate_limits, %{
      user: {10, :minute},
      template: {20, :minute},
      global: {100, :minute}
    })
  end

  @doc """
  Gets sandbox configuration.
  """
  def get_sandbox_config do
    config = get_config()

    Map.get(config, :sandbox, %{
      timeout: 5_000,
      max_heap_size: 50_000_000,
      default_security_level: :balanced
    })
  end

  @doc """
  Gets security validation configuration.
  """
  def get_validation_config do
    config = get_config()

    Map.get(config, :validation, %{
      injection_detection: true,
      xss_protection: true,
      path_traversal_protection: true,
      code_execution_protection: true,
      dangerous_patterns: [],
      xss_patterns: [],
      path_traversal_patterns: []
    })
  end

  @doc """
  Gets security monitoring configuration.
  """
  def get_monitoring_config do
    config = get_config()

    Map.get(config, :monitoring, %{
      window_size: 3600,
      cleanup_interval: 300_000,
      threat_weights: %{},
      threat_levels: %{},
      alert_thresholds: %{}
    })
  end

  @doc """
  Gets audit logging configuration.
  """
  def get_audit_config do
    config = get_config()

    Map.get(config, :audit, %{
      logged_events: [
        :template_processed,
        :security_violation,
        :injection_attempt,
        :rate_limit_exceeded,
        :sandbox_violation,
        :resource_limit_exceeded,
        :user_blocked,
        :anomaly_detected
      ],
      retention_days: 30,
      cleanup_frequency: 86400
    })
  end

  @doc """
  Gets the default security level.
  """
  def get_default_security_level do
    config = get_config()
    Map.get(config, :default_security_level, :balanced)
  end

  @doc """
  Checks if security is enabled.
  """
  def security_enabled? do
    config = get_config()
    Map.get(config, :enabled, true)
  end

  @doc """
  Gets the maximum template size allowed.
  """
  def get_max_template_size do
    config = get_config()
    Map.get(config, :max_template_size, 10_000)
  end

  @doc """
  Gets the maximum processing time allowed.
  """
  def get_max_processing_time do
    config = get_config()
    Map.get(config, :max_processing_time, 5_000)
  end

  @doc """
  Gets dangerous patterns for security validation.
  """
  def get_dangerous_patterns do
    validation_config = get_validation_config()
    Map.get(validation_config, :dangerous_patterns, [])
  end

  @doc """
  Gets XSS patterns for security validation.
  """
  def get_xss_patterns do
    validation_config = get_validation_config()
    Map.get(validation_config, :xss_patterns, [])
  end

  @doc """
  Gets path traversal patterns for security validation.
  """
  def get_path_traversal_patterns do
    validation_config = get_validation_config()
    Map.get(validation_config, :path_traversal_patterns, [])
  end

  @doc """
  Gets allowed functions for a security level.
  """
  def get_allowed_functions(security_level) do
    level_config = get_security_level_config(security_level)
    Map.get(level_config, :allowed_functions, [])
  end

  @doc """
  Gets rate limit factor for a security level.
  """
  def get_rate_limit_factor(security_level) do
    level_config = get_security_level_config(security_level)
    Map.get(level_config, :rate_limit_factor, 1.0)
  end

  @doc """
  Gets adaptive rate limiting factors.
  """
  def get_adaptive_factors do
    config = get_config()

    Map.get(config, :adaptive_factors, %{
      suspicious: 0.2,
      elevated: 0.5,
      normal: 1.0,
      trusted: 2.0
    })
  end

  @doc """
  Gets threat weights for security monitoring.
  """
  def get_threat_weights do
    monitoring_config = get_monitoring_config()

    Map.get(monitoring_config, :threat_weights, %{
      injection_attempt: 10,
      rate_limit_exceeded: 3,
      sandbox_violation: 8,
      resource_limit_exceeded: 5,
      template_processed: -1,
      anomaly_detected: 5
    })
  end

  @doc """
  Gets threat levels for security monitoring.
  """
  def get_threat_levels do
    monitoring_config = get_monitoring_config()

    Map.get(monitoring_config, :threat_levels, %{
      low: 0..10,
      medium: 11..30,
      high: 31..50,
      critical: 51..100,
      blocked: 101..999_999
    })
  end

  @doc """
  Gets alert thresholds for security monitoring.
  """
  def get_alert_thresholds do
    monitoring_config = get_monitoring_config()

    Map.get(monitoring_config, :alert_thresholds, %{
      injection_threshold: 3,
      anomaly_sensitivity: :medium,
      alert_cooldown: 300
    })
  end

  @doc """
  Updates security configuration at runtime.
  """
  def update_config(new_config) when is_map(new_config) do
    current_config = get_config()
    updated_config = Map.merge(current_config, new_config)
    Application.put_env(:rubber_duck, :security, updated_config)
    :ok
  end

  @doc """
  Updates configuration for a specific security level.
  """
  def update_security_level_config(level, new_config) when is_map(new_config) do
    current_config = get_config()
    current_levels = Map.get(current_config, :security_levels, %{})
    current_level_config = Map.get(current_levels, level, %{})

    updated_level_config = Map.merge(current_level_config, new_config)
    updated_levels = Map.put(current_levels, level, updated_level_config)
    updated_config = Map.put(current_config, :security_levels, updated_levels)

    Application.put_env(:rubber_duck, :security, updated_config)
    :ok
  end

  @doc """
  Validates security configuration.
  """
  def validate_config(config) when is_map(config) do
    required_keys = [:enabled, :default_security_level, :rate_limits, :sandbox, :validation]

    case check_required_keys(config, required_keys) do
      :ok -> validate_security_levels(config)
      error -> error
    end
  end

  defp check_required_keys(config, required_keys) do
    missing_keys = Enum.filter(required_keys, fn key -> not Map.has_key?(config, key) end)

    if Enum.empty?(missing_keys) do
      :ok
    else
      {:error, {:missing_keys, missing_keys}}
    end
  end

  defp validate_security_levels(config) do
    security_levels = Map.get(config, :security_levels, %{})
    valid_levels = [:strict, :balanced, :relaxed]

    invalid_levels = Map.keys(security_levels) -- valid_levels

    if Enum.empty?(invalid_levels) do
      :ok
    else
      {:error, {:invalid_security_levels, invalid_levels}}
    end
  end

  @doc """
  Resets configuration to defaults.
  """
  def reset_to_defaults do
    Application.delete_env(:rubber_duck, :security)
    :ok
  end
end

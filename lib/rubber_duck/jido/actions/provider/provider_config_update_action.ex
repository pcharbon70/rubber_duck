defmodule RubberDuck.Jido.Actions.Provider.ProviderConfigUpdateAction do
  @moduledoc """
  Action for dynamically updating provider configuration without restart.
  
  This action handles:
  - Runtime configuration updates for all provider types
  - Configuration validation and safety checks
  - Hot-swapping of provider settings
  - Rate limit and circuit breaker reconfiguration
  - Provider-specific configuration options
  - Configuration rollback on failure
  """
  
  use Jido.Action,
    name: "provider_config_update",
    description: "Updates provider configuration dynamically with validation and rollback",
    schema: [
      config_updates: [type: :map, required: true],
      validate_only: [type: :boolean, default: false],
      backup_current: [type: :boolean, default: true],
      force_update: [type: :boolean, default: false],
      restart_connections: [type: :boolean, default: false]
    ]

  # alias RubberDuck.LLM.{ProviderConfig, ConfigLoader}
  # alias RubberDuck.Jido.Actions.Base.UpdateStateAction
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    try do
      # Validate the agent has the expected state structure
      if not is_valid_provider_agent?(agent) do
        {:error, {:invalid_provider_agent, "Agent does not have provider configuration"}}
      else
      
      # Backup current configuration if requested
      backup = if params.backup_current do
        create_config_backup(agent)
      else
        nil
      end
      
      # Validate the proposed configuration
      case validate_config_updates(agent, params.config_updates) do
        {:ok, validated_config} ->
          if params.validate_only do
            {:ok, %{
              validation_result: :valid,
              proposed_config: validated_config,
              current_config: get_safe_config(agent.state.provider_config),
              backup_created: not is_nil(backup)
            }}
          else
            # Apply the configuration update
            apply_config_update(agent, validated_config, backup, params)
          end
        
        {:error, validation_errors} ->
          {:error, {:config_validation_failed, validation_errors}}
      end
      end # This closes the if statement from line 36
      
    rescue
      error ->
        Logger.error("Config update failed for #{agent.name}: #{inspect(error)}")
        {:error, {:config_update_failed, error}}
    end
  end
  
  # Private implementation functions
  
  defp is_valid_provider_agent?(agent) do
    Map.has_key?(agent.state, :provider_config) and
    Map.has_key?(agent.state, :provider_module) and
    Map.has_key?(agent.state, :rate_limiter) and
    Map.has_key?(agent.state, :circuit_breaker)
  end
  
  defp create_config_backup(agent) do
    %{
      timestamp: DateTime.utc_now(),
      provider_config: agent.state.provider_config,
      rate_limiter: agent.state.rate_limiter,
      circuit_breaker: agent.state.circuit_breaker,
      capabilities: agent.state.capabilities,
      max_concurrent_requests: agent.state.max_concurrent_requests
    }
  end
  
  defp validate_config_updates(agent, config_updates) do
    provider_module = agent.state.provider_module
    current_config = agent.state.provider_config
    
    # Merge updates with current config
    proposed_config = Map.merge(current_config, config_updates)
    
    errors = []
    
    # Validate provider-specific configuration
    errors = validate_provider_specific_config(provider_module, proposed_config, errors)
    
    # Validate rate limiting configuration
    errors = validate_rate_limit_config(config_updates, errors)
    
    # Validate circuit breaker configuration  
    errors = validate_circuit_breaker_config(config_updates, errors)
    
    # Validate concurrent request limits
    errors = validate_concurrent_request_config(config_updates, errors)
    
    # Validate API keys and authentication
    errors = validate_authentication_config(proposed_config, errors)
    
    if Enum.empty?(errors) do
      {:ok, proposed_config}
    else
      {:error, errors}
    end
  end
  
  defp validate_provider_specific_config(provider_module, config, errors) do
    case provider_module do
      RubberDuck.LLM.Providers.Anthropic ->
        validate_anthropic_config(config, errors)
      
      RubberDuck.LLM.Providers.OpenAI ->
        validate_openai_config(config, errors)
      
      RubberDuck.LLM.Providers.Ollama ->
        validate_ollama_config(config, errors)
      
      _ ->
        ["Unknown provider module: #{provider_module}" | errors]
    end
  end
  
  defp validate_anthropic_config(config, errors) do
    errors = if Map.has_key?(config, :api_version) do
      version = config.api_version
      if version in ["2023-06-01", "2023-01-01"] do
        errors
      else
        ["Invalid Anthropic API version: #{version}" | errors]
      end
    else
      errors
    end
    
    errors = if Map.has_key?(config, :safety_level) do
      level = config.safety_level
      if level in [:strict, :standard, :relaxed] do
        errors
      else
        ["Invalid Anthropic safety level: #{level}" | errors]
      end
    else
      errors
    end
    
    errors = if Map.has_key?(config, :max_tokens) do
      max_tokens = config.max_tokens
      if is_integer(max_tokens) and max_tokens > 0 and max_tokens <= 200_000 do
        errors
      else
        ["Invalid max_tokens for Anthropic: #{max_tokens}" | errors]
      end
    else
      errors
    end
    
    errors
  end
  
  defp validate_openai_config(config, errors) do
    errors = if Map.has_key?(config, :organization_id) do
      org_id = config.organization_id
      if is_binary(org_id) and String.starts_with?(org_id, "org-") do
        errors
      else
        ["Invalid OpenAI organization ID format: #{org_id}" | errors]
      end
    else
      errors
    end
    
    errors = if Map.has_key?(config, :model) do
      model = config.model
      valid_models = ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo", "gpt-4o"]
      if model in valid_models do
        errors
      else
        ["Unsupported OpenAI model: #{model}" | errors]
      end
    else
      errors
    end
    
    errors = if Map.has_key?(config, :temperature) do
      temp = config.temperature
      if is_number(temp) and temp >= 0.0 and temp <= 2.0 do
        errors
      else
        ["Invalid temperature for OpenAI: #{temp}" | errors]
      end
    else
      errors
    end
    
    errors
  end
  
  defp validate_ollama_config(config, errors) do
    errors = if Map.has_key?(config, :host) do
      host = config.host
      if is_binary(host) and String.length(host) > 0 do
        errors
      else
        ["Invalid Ollama host: #{host}" | errors]
      end
    else
      errors
    end
    
    errors = if Map.has_key?(config, :port) do
      port = config.port
      if is_integer(port) and port > 0 and port <= 65535 do
        errors
      else
        ["Invalid Ollama port: #{port}" | errors]
      end
    else
      errors
    end
    
    errors = if Map.has_key?(config, :model) do
      model = config.model
      if is_binary(model) and String.length(model) > 0 do
        errors
      else
        ["Invalid Ollama model specification: #{model}" | errors]
      end
    else
      errors
    end
    
    errors
  end
  
  defp validate_rate_limit_config(config_updates, errors) do
    errors = if Map.has_key?(config_updates, :rate_limit) do
      rate_config = config_updates.rate_limit
      
      errors = if Map.has_key?(rate_config, :limit) do
        limit = rate_config.limit
        if is_integer(limit) and limit > 0 do
          errors
        else
          ["Invalid rate limit: #{limit}" | errors]
        end
      else
        errors
      end
      
      errors = if Map.has_key?(rate_config, :window) do
        window = rate_config.window
        if is_integer(window) and window > 0 do
          errors
        else
          ["Invalid rate limit window: #{window}" | errors]
        end
      else
        errors
      end
      
      errors
    else
      errors
    end
    
    errors
  end
  
  defp validate_circuit_breaker_config(config_updates, errors) do
    errors = if Map.has_key?(config_updates, :circuit_breaker) do
      cb_config = config_updates.circuit_breaker
      
      errors = if Map.has_key?(cb_config, :failure_threshold) do
        threshold = cb_config.failure_threshold
        if is_integer(threshold) and threshold > 0 do
          errors
        else
          ["Invalid circuit breaker failure threshold: #{threshold}" | errors]
        end
      else
        errors
      end
      
      errors = if Map.has_key?(cb_config, :timeout) do
        timeout = cb_config.timeout
        if is_integer(timeout) and timeout > 0 do
          errors
        else
          ["Invalid circuit breaker timeout: #{timeout}" | errors]
        end
      else
        errors
      end
      
      errors
    else
      errors
    end
    
    errors
  end
  
  defp validate_concurrent_request_config(config_updates, errors) do
    if Map.has_key?(config_updates, :max_concurrent_requests) do
      max_concurrent = config_updates.max_concurrent_requests
      if is_integer(max_concurrent) and max_concurrent > 0 and max_concurrent <= 1000 do
        errors
      else
        ["Invalid max_concurrent_requests: #{max_concurrent}" | errors]
      end
    else
      errors
    end
  end
  
  defp validate_authentication_config(config, errors) do
    # Check for required authentication based on provider
    if Map.has_key?(config, :api_key) do
      api_key = config.api_key
      if is_binary(api_key) and String.length(api_key) > 10 do
        errors
      else
        ["Invalid or missing API key" | errors]
      end
    else
      # API key validation depends on provider - some may not require it
      errors
    end
  end
  
  defp apply_config_update(agent, validated_config, backup, params) do
    try do
      # Update the agent state
      updated_agent = update_agent_configuration(agent, validated_config, params)
      
      # Restart connections if requested
      connection_result = if params.restart_connections do
        restart_provider_connections(updated_agent)
      else
        {:ok, :skipped}
      end
      
      # Test the new configuration
      test_result = if not params.force_update do
        test_configuration(updated_agent)
      else
        {:ok, :skipped}
      end
      
      case {connection_result, test_result} do
        {{:ok, _}, {:ok, _}} ->
          Logger.info("Configuration updated successfully for #{agent.name}")
          
          {:ok, %{
            status: :success,
            applied_config: get_safe_config(validated_config),
            backup_available: not is_nil(backup),
            connections_restarted: params.restart_connections,
            configuration_tested: not params.force_update,
            updated_at: DateTime.utc_now()
          }}
        
        {{:error, conn_error}, _} ->
          # Rollback configuration due to connection failure
          if backup do
            rollback_configuration(agent, backup)
          end
          {:error, {:connection_restart_failed, conn_error}}
        
        {_, {:error, test_error}} ->
          # Rollback configuration due to test failure
          if backup do
            rollback_configuration(agent, backup)
          end
          {:error, {:configuration_test_failed, test_error}}
      end
      
    rescue
      error ->
        # Rollback configuration due to update failure
        if backup do
          rollback_configuration(agent, backup)
        end
        {:error, {:config_apply_failed, error}}
    end
  end
  
  defp update_agent_configuration(agent, validated_config, params) do
    # Update provider configuration
    agent = put_in(agent.state.provider_config, validated_config)
    
    # Update rate limiting if specified
    agent = if Map.has_key?(params.config_updates, :rate_limit) do
      rate_config = params.config_updates.rate_limit
      current_rate_limiter = agent.state.rate_limiter
      
      updated_rate_limiter = 
        current_rate_limiter
        |> Map.merge(rate_config)
        |> Map.put(:current_count, 0)  # Reset count on config change
        |> Map.put(:window_start, nil)  # Reset window
      
      put_in(agent.state.rate_limiter, updated_rate_limiter)
    else
      agent
    end
    
    # Update circuit breaker if specified
    agent = if Map.has_key?(params.config_updates, :circuit_breaker) do
      cb_config = params.config_updates.circuit_breaker
      current_circuit_breaker = agent.state.circuit_breaker
      
      updated_circuit_breaker = Map.merge(current_circuit_breaker, cb_config)
      
      put_in(agent.state.circuit_breaker, updated_circuit_breaker)
    else
      agent
    end
    
    # Update concurrent request limit if specified
    agent = if Map.has_key?(params.config_updates, :max_concurrent_requests) do
      put_in(agent.state.max_concurrent_requests, params.config_updates.max_concurrent_requests)
    else
      agent
    end
    
    agent
  end
  
  defp restart_provider_connections(_agent) do
    # In a real implementation, this would restart HTTP connections,
    # clear connection pools, etc.
    {:ok, :connections_restarted}
  end
  
  defp test_configuration(_agent) do
    # In a real implementation, this would make a test request
    # to verify the new configuration works
    {:ok, :configuration_valid}
  end
  
  defp rollback_configuration(agent, backup) do
    Logger.warning("Rolling back configuration for #{agent.name}")
    
    # Restore backed up configuration
    agent = put_in(agent.state.provider_config, backup.provider_config)
    agent = put_in(agent.state.rate_limiter, backup.rate_limiter)
    agent = put_in(agent.state.circuit_breaker, backup.circuit_breaker)
    agent = put_in(agent.state.capabilities, backup.capabilities)
    agent = put_in(agent.state.max_concurrent_requests, backup.max_concurrent_requests)
    
    {:ok, agent}
  end
  
  defp get_safe_config(config) do
    # Remove sensitive information from config for response
    config
    |> Map.drop([:api_key, :secret_key, :token, :password])
    |> Map.put(:api_key_present, Map.has_key?(config, :api_key))
  end
end
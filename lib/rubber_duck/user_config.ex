defmodule RubberDuck.UserConfig do
  @moduledoc """
  User Configuration API for managing per-user LLM settings.

  This module provides a clean interface for managing user preferences
  for LLM providers and models, including default settings and
  usage tracking.
  """

  alias RubberDuck.LLM.Config
  alias RubberDuck.Memory

  @type provider :: :openai | :anthropic | :ollama | :tgi
  @type model :: String.t()
  @type user_id :: String.t()
  @type config_result :: {:ok, term()} | {:error, term()}

  @doc """
  Set a user's default LLM provider and model.

  This will create or update the user's configuration and
  mark it as the default across all providers.

  ## Examples

      iex> RubberDuck.UserConfig.set_default("user123", :openai, "gpt-4")
      {:ok, %RubberDuck.Memory.UserLLMConfig{...}}
      
      iex> RubberDuck.UserConfig.set_default("user123", :invalid, "model")
      {:error, :invalid_provider}
  """
  @spec set_default(user_id(), provider(), model()) :: config_result()
  def set_default(user_id, provider, model) when is_binary(user_id) and is_atom(provider) and is_binary(model) do
    # Validate provider and model
    with :ok <- validate_provider(provider),
         :ok <- validate_model(provider, model) do
      Memory.set_user_default(user_id, provider, model)
    end
  end

  @doc """
  Add a model to a user's configuration for a specific provider.

  This adds the model to the user's available models for the provider
  without necessarily making it the default.

  ## Examples

      iex> RubberDuck.UserConfig.add_model("user123", :openai, "gpt-3.5-turbo")
      {:ok, %RubberDuck.Memory.UserLLMConfig{...}}
  """
  @spec add_model(user_id(), provider(), model()) :: config_result()
  def add_model(user_id, provider, model) when is_binary(user_id) and is_atom(provider) and is_binary(model) do
    # Validate provider and model
    with :ok <- validate_provider(provider),
         :ok <- validate_model(provider, model) do
      # Check if config already exists
      case Memory.get_provider_configs(user_id, provider) do
        {:ok, configs} when is_list(configs) and length(configs) == 0 ->
          # Create new config
          Memory.create_config(%{
            user_id: user_id,
            provider: provider,
            model: model,
            is_default: false,
            metadata: %{}
          })

        {:ok, [config | _]} ->
          # Update existing config with new model
          Memory.update_config(config, %{model: model})

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Get a user's default LLM configuration.

  Returns the user's global default provider and model.

  ## Examples

      iex> RubberDuck.UserConfig.get_default("user123")
      {:ok, %{provider: :openai, model: "gpt-4"}}
      
      iex> RubberDuck.UserConfig.get_default("new_user")
      {:error, :not_found}
  """
  @spec get_default(user_id()) :: {:ok, %{provider: provider(), model: model()}} | {:error, term()}
  def get_default(user_id) when is_binary(user_id) do
    case Memory.get_user_default(user_id) do
      {:ok, config} when not is_nil(config) ->
        {:ok, %{provider: config.provider, model: config.model}}

      {:ok, nil} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get all configurations for a user.

  Returns all LLM configurations for the user as a list.

  ## Examples

      iex> RubberDuck.UserConfig.get_all_configs("user123")
      {:ok, [%RubberDuck.Memory.UserLLMConfig{...}]}
  """
  @spec get_all_configs(user_id()) :: {:ok, list()} | {:error, term()}
  def get_all_configs(user_id) when is_binary(user_id) do
    case Memory.get_user_configs(user_id) do
      {:ok, configs} when is_list(configs) ->
        {:ok, configs}

      {:ok, []} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get configuration for a specific provider for a user.

  ## Examples

      iex> RubberDuck.UserConfig.get_provider_config("user123", :openai)
      {:ok, %{model: "gpt-4", is_default: true, usage_count: 5}}
      
      iex> RubberDuck.UserConfig.get_provider_config("user123", :unknown)
      {:error, :not_found}
  """
  @spec get_provider_config(user_id(), provider()) :: {:ok, map()} | {:error, term()}
  def get_provider_config(user_id, provider) when is_binary(user_id) and is_atom(provider) do
    case Memory.get_provider_configs(user_id, provider) do
      {:ok, [config | _]} ->
        {:ok,
         %{
           model: config.model,
           is_default: config.is_default,
           usage_count: config.usage_count,
           metadata: config.metadata,
           created_at: config.created_at,
           updated_at: config.updated_at
         }}

      {:ok, configs} when is_list(configs) and length(configs) == 0 ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Remove a user's configuration for a specific provider.

  ## Examples

      iex> RubberDuck.UserConfig.remove_provider_config("user123", :openai)
      :ok
      
      iex> RubberDuck.UserConfig.remove_provider_config("user123", :unknown)
      {:error, :not_found}
  """
  @spec remove_provider_config(user_id(), provider()) :: :ok | {:error, term()}
  def remove_provider_config(user_id, provider) when is_binary(user_id) and is_atom(provider) do
    case Memory.get_provider_configs(user_id, provider) do
      {:ok, [config | _]} ->
        case Ash.destroy(config) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, configs} when is_list(configs) and length(configs) == 0 ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Remove all configurations for a user's provider.

  This removes all LLM configurations for the specified provider.

  ## Examples

      iex> RubberDuck.UserConfig.remove_provider("user123", :openai)
      {:ok, 2}  # Removed 2 configs
      
      iex> RubberDuck.UserConfig.remove_provider("user123", :unknown)
      {:ok, 0}  # No configs found
  """
  @spec remove_provider(user_id(), provider()) :: {:ok, integer()} | {:error, term()}
  def remove_provider(user_id, provider) when is_binary(user_id) and is_atom(provider) do
    case Memory.get_provider_configs(user_id, provider) do
      {:ok, configs} when is_list(configs) ->
        # Remove all configs for this provider
        results = Enum.map(configs, &Ash.destroy/1)

        # Check if any deletions failed
        case Enum.find(results, fn result -> match?({:error, _}, result) end) do
          nil -> {:ok, length(configs)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Clear all configurations for a user.

  This removes all LLM configurations for the user.

  ## Examples

      iex> RubberDuck.UserConfig.clear_all_configs("user123")
      :ok
  """
  @spec clear_all_configs(user_id()) :: :ok | {:error, term()}
  def clear_all_configs(user_id) when is_binary(user_id) do
    case Memory.get_user_configs(user_id) do
      {:ok, configs} when is_list(configs) and length(configs) == 0 ->
        :ok

      {:ok, configs} ->
        results = Enum.map(configs, &Ash.destroy/1)

        # Check if any deletions failed
        case Enum.find(results, fn result -> match?({:error, _}, result) end) do
          nil -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the resolved provider and model for a user.

  This function resolves the user's preferences and falls back to
  global configuration if no user preference is set.

  ## Examples

      iex> RubberDuck.UserConfig.get_resolved_config("user123")
      {:ok, %{provider: :openai, model: "gpt-4"}}
      
      iex> RubberDuck.UserConfig.get_resolved_config("new_user")
      {:ok, %{provider: :openai, model: "gpt-3.5-turbo"}}  # Falls back to global config
  """
  @spec get_resolved_config(user_id()) :: {:ok, %{provider: provider(), model: model()}} | {:error, term()}
  def get_resolved_config(user_id) when is_binary(user_id) do
    case Config.get_current_provider_and_model(user_id) do
      {provider, model} when not is_nil(provider) and not is_nil(model) ->
        {:ok, %{provider: provider, model: model}}

      {nil, nil} ->
        {:error, :no_configuration_available}

      _ ->
        {:error, :configuration_error}
    end
  end

  @doc """
  Get statistics for a user's LLM usage.

  ## Examples

      iex> RubberDuck.UserConfig.get_usage_stats("user123")
      {:ok, %{
        total_requests: 50,
        providers: %{
          openai: %{requests: 30, models: ["gpt-4", "gpt-3.5-turbo"]},
          anthropic: %{requests: 20, models: ["claude-3-sonnet"]}
        }
      }}
  """
  @spec get_usage_stats(user_id()) :: {:ok, map()} | {:error, term()}
  def get_usage_stats(user_id) when is_binary(user_id) do
    case Memory.get_user_configs(user_id) do
      {:ok, configs} when is_list(configs) ->
        total_requests = Enum.sum(Enum.map(configs, & &1.usage_count))

        provider_stats =
          configs
          |> Enum.map(fn config ->
            {config.provider,
             %{
               requests: config.usage_count,
               models: [config.model],
               last_used: get_last_used_from_metadata(config.metadata)
             }}
          end)
          |> Map.new()

        {:ok,
         %{
           total_requests: total_requests,
           providers: provider_stats
         }}

      {:ok, []} ->
        {:ok, %{total_requests: 0, providers: %{}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp validate_provider(provider) do
    valid_providers = [:openai, :anthropic, :ollama, :tgi]

    if provider in valid_providers do
      :ok
    else
      {:error, :invalid_provider}
    end
  end

  defp validate_model(_provider, _model) do
    # For now, we'll accept any model as Config.validate_model always returns :ok
    # In the future, this could be enhanced with more strict validation
    :ok
  end

  defp get_last_used_from_metadata(metadata) do
    case metadata["last_used"] do
      nil ->
        nil

      timestamp when is_binary(timestamp) ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, datetime, _} -> datetime
          _ -> nil
        end

      _ ->
        nil
    end
  end
end

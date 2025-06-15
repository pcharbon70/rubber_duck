defmodule RubberDuck.Interface.CLI.ConfigManager do
  @moduledoc """
  Manages CLI configuration for RubberDuck interface.
  
  This module handles configuration loading, validation, persistence, and
  management for the CLI interface. It supports multiple configuration
  sources including environment variables, config files, and runtime settings.
  
  ## Features
  
  - Configuration file loading and persistence
  - Environment variable overrides
  - Configuration validation and type coercion
  - Profile management for different environments
  - Runtime configuration updates
  - Default configuration management
  
  ## Configuration Sources (in priority order)
  
  1. Runtime settings (highest priority)
  2. Environment variables
  3. User config file (`~/.rubber_duck/config.yaml`)
  4. Project config file (`./rubber_duck.config.yaml`)
  5. Default configuration (lowest priority)
  """

  require Logger

  @type config_key :: atom() | String.t()
  @type config_value :: any()
  @type config :: map()
  @type profile :: String.t()

  # Default configuration
  @default_config %{
    # Display settings
    colors: true,
    syntax_highlight: true,
    timestamps: false,
    format: "text",
    
    # Interface settings
    interactive_prompt: "🦆 > ",
    user_prompt: "You: ",
    pager: "less",
    editor: System.get_env("EDITOR") || "vim",
    
    # AI model settings
    model: "claude",
    temperature: 0.7,
    max_tokens: 2048,
    
    # Session settings
    auto_save_sessions: true,
    session_history_limit: 1000,
    default_session_name: "default",
    
    # Network settings
    timeout: 30000,
    retry_attempts: 3,
    
    # Logging settings
    log_level: "info",
    log_file: nil,
    
    # Cluster settings
    cluster_nodes: [],
    cluster_timeout: 10000,
    
    # File paths
    config_dir: Path.expand("~/.rubber_duck"),
    sessions_dir: Path.expand("~/.rubber_duck/sessions"),
    cache_dir: Path.expand("~/.rubber_duck/cache")
  }

  # Environment variable mappings
  @env_mappings %{
    "RUBBER_DUCK_COLORS" => {:colors, :boolean},
    "RUBBER_DUCK_MODEL" => {:model, :string},
    "RUBBER_DUCK_TEMPERATURE" => {:temperature, :float},
    "RUBBER_DUCK_MAX_TOKENS" => {:max_tokens, :integer},
    "RUBBER_DUCK_TIMEOUT" => {:timeout, :integer},
    "RUBBER_DUCK_LOG_LEVEL" => {:log_level, :string},
    "RUBBER_DUCK_CONFIG_DIR" => {:config_dir, :string},
    "EDITOR" => {:editor, :string},
    "PAGER" => {:pager, :string}
  }

  # Configuration validation rules
  @validation_rules %{
    colors: [:boolean],
    syntax_highlight: [:boolean],
    timestamps: [:boolean],
    format: ["text", "json", "yaml"],
    temperature: {:float, 0.0, 2.0},
    max_tokens: {:integer, 1, 100_000},
    timeout: {:integer, 1000, 300_000},
    retry_attempts: {:integer, 0, 10},
    log_level: ["debug", "info", "warning", "error"],
    session_history_limit: {:integer, 10, 10_000}
  }

  @doc """
  Load configuration from all sources and merge them.
  """
  def load_config(overrides \\ %{}) do
    config = @default_config
    |> merge_project_config()
    |> merge_user_config()
    |> merge_env_config()
    |> merge_runtime_config(overrides)
    |> validate_config()
    
    case config do
      {:ok, valid_config} -> 
        ensure_directories(valid_config)
        {:ok, valid_config}
      error -> 
        error
    end
  end

  @doc """
  Get the current configuration.
  """
  def get_config(current_config \\ nil) do
    case current_config do
      nil -> 
        case load_config() do
          {:ok, config} -> config
          {:error, _} -> @default_config
        end
      config when is_map(config) -> 
        config
    end
  end

  @doc """
  Set a configuration value.
  """
  def set_config(key, value, current_config) do
    key_atom = normalize_key(key)
    
    case validate_config_value(key_atom, value) do
      {:ok, validated_value} ->
        new_config = Map.put(current_config, key_atom, validated_value)
        {:ok, new_config}
      error ->
        error
    end
  end

  @doc """
  Update multiple configuration values.
  """
  def update_config(updates, current_config) when is_map(updates) do
    Enum.reduce_while(updates, {:ok, current_config}, fn {key, value}, {:ok, config} ->
      case set_config(key, value, config) do
        {:ok, new_config} -> {:cont, {:ok, new_config}}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Reset configuration to defaults.
  """
  def reset_config do
    {:ok, @default_config}
  end

  @doc """
  Save configuration to user config file.
  """
  def save_config(config) do
    config_file_path = get_user_config_path(config)
    
    # Create config directory if it doesn't exist
    config_dir = Path.dirname(config_file_path)
    File.mkdir_p!(config_dir)
    
    # Filter out system-specific paths and runtime settings
    config_to_save = config
    |> Map.drop([:config_dir, :sessions_dir, :cache_dir])
    |> remove_default_values()
    
    case YamlElixir.write_to_file(config_to_save, config_file_path) do
      :ok -> {:ok, config_file_path}
      error -> {:error, "Failed to save config: #{inspect(error)}"}
    end
  end

  @doc """
  Load configuration profile.
  """
  def load_profile(profile_name, config) do
    profile_path = get_profile_path(profile_name, config)
    
    if File.exists?(profile_path) do
      case YamlElixir.read_from_file(profile_path) do
        {:ok, profile_config} ->
          merged_config = Map.merge(config, normalize_keys(profile_config))
          validate_config(merged_config)
        error ->
          {:error, "Failed to load profile: #{inspect(error)}"}
      end
    else
      {:error, "Profile '#{profile_name}' not found"}
    end
  end

  @doc """
  Save configuration as a profile.
  """
  def save_profile(profile_name, config) do
    profile_path = get_profile_path(profile_name, config)
    
    # Create profiles directory
    profiles_dir = Path.dirname(profile_path)
    File.mkdir_p!(profiles_dir)
    
    # Save configuration
    config_to_save = remove_default_values(config)
    
    case YamlElixir.write_to_file(config_to_save, profile_path) do
      :ok -> {:ok, profile_path}
      error -> {:error, "Failed to save profile: #{inspect(error)}"}
    end
  end

  @doc """
  List available configuration profiles.
  """
  def list_profiles(config) do
    profiles_dir = get_profiles_dir(config)
    
    if File.exists?(profiles_dir) do
      profiles_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".yaml"))
      |> Enum.map(&Path.rootname/1)
    else
      []
    end
  end

  @doc """
  Get configuration schema for validation and help.
  """
  def get_config_schema do
    %{
      display: %{
        colors: %{
          type: :boolean,
          default: @default_config.colors,
          description: "Enable colored output"
        },
        syntax_highlight: %{
          type: :boolean,
          default: @default_config.syntax_highlight,
          description: "Enable syntax highlighting for code blocks"
        },
        format: %{
          type: :enum,
          values: ["text", "json", "yaml"],
          default: @default_config.format,
          description: "Default output format"
        }
      },
      interface: %{
        interactive_prompt: %{
          type: :string,
          default: @default_config.interactive_prompt,
          description: "Prompt shown in interactive mode"
        },
        editor: %{
          type: :string,
          default: @default_config.editor,
          description: "Editor command for file editing"
        }
      },
      ai: %{
        model: %{
          type: :string,
          default: @default_config.model,
          description: "Default AI model to use"
        },
        temperature: %{
          type: :float,
          range: {0.0, 2.0},
          default: @default_config.temperature,
          description: "Model temperature (creativity level)"
        },
        max_tokens: %{
          type: :integer,
          range: {1, 100_000},
          default: @default_config.max_tokens,
          description: "Maximum tokens in model response"
        }
      }
    }
  end

  @doc """
  Validate entire configuration map.
  """
  def validate_config(config) do
    validation_errors = config
    |> Enum.map(fn {key, value} -> validate_config_value(key, value) end)
    |> Enum.filter(&match?({:error, _}, &1))
    
    case validation_errors do
      [] -> {:ok, config}
      errors -> {:error, {:validation_errors, errors}}
    end
  end

  @doc """
  Validate a single configuration value.
  """
  def validate_config_value(key, value) do
    case Map.get(@validation_rules, key) do
      nil -> 
        {:ok, value}  # No validation rule, accept any value
        
      [:boolean] ->
        validate_boolean(value)
        
      values when is_list(values) ->
        validate_enum(value, values)
        
      {:integer, min, max} ->
        validate_integer(value, min, max)
        
      {:float, min, max} ->
        validate_float(value, min, max)
        
      rule ->
        {:error, "Unknown validation rule: #{inspect(rule)}"}
    end
  end

  # Private helper functions

  defp merge_project_config(config) do
    project_config_path = "./rubber_duck.config.yaml"
    
    if File.exists?(project_config_path) do
      case YamlElixir.read_from_file(project_config_path) do
        {:ok, project_config} ->
          Map.merge(config, normalize_keys(project_config))
        {:error, reason} ->
          Logger.warning("Failed to load project config: #{reason}")
          config
      end
    else
      config
    end
  end

  defp merge_user_config(config) do
    user_config_path = get_user_config_path(config)
    
    if File.exists?(user_config_path) do
      case YamlElixir.read_from_file(user_config_path) do
        {:ok, user_config} ->
          Map.merge(config, normalize_keys(user_config))
        {:error, reason} ->
          Logger.warning("Failed to load user config: #{reason}")
          config
      end
    else
      config
    end
  end

  defp merge_env_config(config) do
    env_config = @env_mappings
    |> Enum.reduce(%{}, fn {env_var, {key, type}}, acc ->
      case System.get_env(env_var) do
        nil -> acc
        value -> 
          case coerce_type(value, type) do
            {:ok, coerced_value} -> Map.put(acc, key, coerced_value)
            {:error, _} -> 
              Logger.warning("Invalid environment variable #{env_var}: #{value}")
              acc
          end
      end
    end)
    
    Map.merge(config, env_config)
  end

  defp merge_runtime_config(config, overrides) do
    Map.merge(config, normalize_keys(overrides))
  end

  defp normalize_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      normalized_key = normalize_key(key)
      Map.put(acc, normalized_key, value)
    end)
  end

  defp normalize_key(key) when is_binary(key) do
    String.to_atom(key)
  end
  defp normalize_key(key) when is_atom(key), do: key

  defp coerce_type(value, :string), do: {:ok, value}
  defp coerce_type(value, :boolean) do
    case String.downcase(value) do
      val when val in ["true", "yes", "1", "on"] -> {:ok, true}
      val when val in ["false", "no", "0", "off"] -> {:ok, false}
      _ -> {:error, :invalid_boolean}
    end
  end
  defp coerce_type(value, :integer) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end
  defp coerce_type(value, :float) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, :invalid_float}
    end
  end

  defp validate_boolean(value) when is_boolean(value), do: {:ok, value}
  defp validate_boolean(_), do: {:error, "Must be true or false"}

  defp validate_enum(value, allowed_values) do
    if value in allowed_values do
      {:ok, value}
    else
      {:error, "Must be one of: #{Enum.join(allowed_values, ", ")}"}
    end
  end

  defp validate_integer(value, min, max) when is_integer(value) do
    if value >= min and value <= max do
      {:ok, value}
    else
      {:error, "Must be between #{min} and #{max}"}
    end
  end
  defp validate_integer(_, _, _), do: {:error, "Must be an integer"}

  defp validate_float(value, min, max) when is_float(value) do
    if value >= min and value <= max do
      {:ok, value}
    else
      {:error, "Must be between #{min} and #{max}"}
    end
  end
  defp validate_float(value, min, max) when is_integer(value) do
    validate_float(value / 1.0, min, max)
  end
  defp validate_float(_, _, _), do: {:error, "Must be a number"}

  defp ensure_directories(config) do
    directories = [
      config.config_dir,
      config.sessions_dir,
      config.cache_dir,
      get_profiles_dir(config)
    ]
    
    Enum.each(directories, &File.mkdir_p!/1)
  end

  defp get_user_config_path(config) do
    Path.join(config.config_dir, "config.yaml")
  end

  defp get_profiles_dir(config) do
    Path.join(config.config_dir, "profiles")
  end

  defp get_profile_path(profile_name, config) do
    Path.join(get_profiles_dir(config), "#{profile_name}.yaml")
  end

  defp remove_default_values(config) do
    Enum.reduce(config, %{}, fn {key, value}, acc ->
      default_value = Map.get(@default_config, key)
      if value != default_value do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end
end
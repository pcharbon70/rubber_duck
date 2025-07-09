defmodule RubberDuck.CLI.Config do
  @moduledoc """
  Configuration management for the CLI.

  Handles loading configuration from files, environment variables,
  and command-line arguments.
  """

  defstruct [
    :format,
    :verbose,
    :quiet,
    :debug,
    :config_file,
    :user_preferences
  ]

  @type t :: %__MODULE__{
          format: :json | :plain | :table,
          verbose: boolean(),
          quiet: boolean(),
          debug: boolean(),
          config_file: String.t() | nil,
          user_preferences: map()
        }

  @doc """
  Creates a configuration from parsed command-line arguments.
  """
  def from_parsed_args(parsed) do
    config = %__MODULE__{
      format: get_in(parsed, [:options, :format]) || :plain,
      verbose: get_in(parsed, [:flags, :verbose]) || false,
      quiet: get_in(parsed, [:flags, :quiet]) || false,
      debug: get_in(parsed, [:flags, :debug]) || false,
      config_file: get_in(parsed, [:options, :config])
    }

    # Load user preferences from config file if specified
    case config.config_file do
      nil ->
        load_default_config(config)

      file ->
        load_config_file(config, file)
    end
  end

  @doc """
  Loads configuration from a file.
  """
  def load_config_file(config, file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, prefs} ->
            %{config | user_preferences: prefs}

          {:error, _reason} ->
            # Try parsing as TOML if JSON fails
            case Toml.decode(content) do
              {:ok, prefs} ->
                %{config | user_preferences: prefs}

              {:error, _reason} ->
                IO.warn("Failed to parse config file: #{file_path}")
                config
            end
        end

      {:error, _reason} ->
        IO.warn("Config file not found: #{file_path}")
        config
    end
  end

  @doc """
  Loads default configuration from standard locations.
  """
  def load_default_config(config) do
    home = System.user_home!()

    default_paths = [
      Path.join([home, ".rubber_duck", "config.json"]),
      Path.join([home, ".rubber_duck", "config.toml"]),
      Path.join([home, ".config", "rubber_duck", "config.json"]),
      Path.join([home, ".config", "rubber_duck", "config.toml"]),
      ".rubber_duck.json",
      ".rubber_duck.toml"
    ]

    Enum.find_value(default_paths, config, fn path ->
      if File.exists?(path) do
        load_config_file(config, path)
      else
        nil
      end
    end)
  end

  @doc """
  Gets a preference value from the configuration.
  """
  def get_preference(config, key, default \\ nil) do
    get_in(config.user_preferences, [key]) || default
  end

  @doc """
  Merges command-specific options with the base configuration.
  """
  def merge_options(config, options) do
    Map.merge(config, Map.new(options))
  end
end

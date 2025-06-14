defmodule RubberDuck.ILP.Parser.PluginManager do
  @moduledoc """
  Plugin architecture for language-specific extensions.
  Allows dynamic loading and management of parser plugins.
  """
  use GenServer
  require Logger

  alias RubberDuck.ILP.Parser.{Behaviour, Plugin}

  defstruct [
    :plugins,
    :plugin_registry,
    :language_mappings,
    :capabilities_cache,
    :plugin_configs
  ]

  @plugin_dir "lib/rubber_duck/ilp/parser/plugins"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a new parser plugin.
  """
  def register_plugin(plugin_module, opts \\ []) do
    GenServer.call(__MODULE__, {:register_plugin, plugin_module, opts})
  end

  @doc """
  Unregisters a parser plugin.
  """
  def unregister_plugin(plugin_module) do
    GenServer.call(__MODULE__, {:unregister_plugin, plugin_module})
  end

  @doc """
  Gets all registered plugins.
  """
  def list_plugins do
    GenServer.call(__MODULE__, :list_plugins)
  end

  @doc """
  Gets plugins for a specific language.
  """
  def get_plugins_for_language(language) do
    GenServer.call(__MODULE__, {:get_plugins_for_language, language})
  end

  @doc """
  Loads plugins from the plugin directory.
  """
  def load_plugins_from_directory(directory \\ @plugin_dir) do
    GenServer.call(__MODULE__, {:load_plugins_from_directory, directory})
  end

  @doc """
  Gets plugin configuration.
  """
  def get_plugin_config(plugin_module) do
    GenServer.call(__MODULE__, {:get_plugin_config, plugin_module})
  end

  @doc """
  Updates plugin configuration.
  """
  def update_plugin_config(plugin_module, config) do
    GenServer.call(__MODULE__, {:update_plugin_config, plugin_module, config})
  end

  @doc """
  Enables or disables a plugin.
  """
  def set_plugin_enabled(plugin_module, enabled) do
    GenServer.call(__MODULE__, {:set_plugin_enabled, plugin_module, enabled})
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting ILP Parser PluginManager")
    
    state = %__MODULE__{
      plugins: %{},
      plugin_registry: %{},
      language_mappings: %{},
      capabilities_cache: %{},
      plugin_configs: %{}
    }
    
    # Load built-in plugins
    initial_state = load_builtin_plugins(state)
    
    {:ok, initial_state}
  end

  @impl true
  def handle_call({:register_plugin, plugin_module, opts}, _from, state) do
    case register_plugin_internal(plugin_module, opts, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister_plugin, plugin_module}, _from, state) do
    new_state = unregister_plugin_internal(plugin_module, state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list_plugins, _from, state) do
    plugins = Map.keys(state.plugins)
    {:reply, plugins, state}
  end

  @impl true
  def handle_call({:get_plugins_for_language, language}, _from, state) do
    plugins = Map.get(state.language_mappings, language, [])
    {:reply, plugins, state}
  end

  @impl true
  def handle_call({:load_plugins_from_directory, directory}, _from, state) do
    case load_plugins_from_dir(directory, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_plugin_config, plugin_module}, _from, state) do
    config = Map.get(state.plugin_configs, plugin_module, %{})
    {:reply, config, state}
  end

  @impl true
  def handle_call({:update_plugin_config, plugin_module, config}, _from, state) do
    new_configs = Map.put(state.plugin_configs, plugin_module, config)
    new_state = %{state | plugin_configs: new_configs}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_plugin_enabled, plugin_module, enabled}, _from, state) do
    case Map.get(state.plugins, plugin_module) do
      nil ->
        {:reply, {:error, :plugin_not_found}, state}
      
      plugin_info ->
        updated_plugin = %{plugin_info | enabled: enabled}
        new_plugins = Map.put(state.plugins, plugin_module, updated_plugin)
        new_state = %{state | plugins: new_plugins}
        {:reply, :ok, new_state}
    end
  end

  defp register_plugin_internal(plugin_module, opts, state) do
    try do
      # Validate plugin implements required behaviour
      case validate_plugin(plugin_module) do
        :ok ->
          plugin_info = %{
            module: plugin_module,
            language: plugin_module.language(),
            capabilities: plugin_module.capabilities(),
            enabled: Keyword.get(opts, :enabled, true),
            registered_at: System.monotonic_time(:millisecond),
            metadata: extract_plugin_metadata(plugin_module)
          }
          
          # Register plugin
          new_plugins = Map.put(state.plugins, plugin_module, plugin_info)
          
          # Update language mappings
          language = plugin_module.language()
          current_plugins = Map.get(state.language_mappings, language, [])
          new_language_mappings = Map.put(
            state.language_mappings, 
            language, 
            [plugin_module | current_plugins]
          )
          
          # Cache capabilities
          new_capabilities_cache = Map.put(
            state.capabilities_cache,
            plugin_module,
            plugin_module.capabilities()
          )
          
          new_state = %{state |
            plugins: new_plugins,
            language_mappings: new_language_mappings,
            capabilities_cache: new_capabilities_cache
          }
          
          Logger.info("Registered parser plugin: #{plugin_module} for language: #{language}")
          {:ok, new_state}
        
        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        {:error, {:plugin_error, e}}
    end
  end

  defp unregister_plugin_internal(plugin_module, state) do
    case Map.get(state.plugins, plugin_module) do
      nil ->
        state
      
      %{language: language} ->
        # Remove from plugins
        new_plugins = Map.delete(state.plugins, plugin_module)
        
        # Remove from language mappings
        current_plugins = Map.get(state.language_mappings, language, [])
        updated_plugins = List.delete(current_plugins, plugin_module)
        new_language_mappings = Map.put(state.language_mappings, language, updated_plugins)
        
        # Remove from capabilities cache
        new_capabilities_cache = Map.delete(state.capabilities_cache, plugin_module)
        
        # Remove from plugin configs
        new_plugin_configs = Map.delete(state.plugin_configs, plugin_module)
        
        Logger.info("Unregistered parser plugin: #{plugin_module}")
        
        %{state |
          plugins: new_plugins,
          language_mappings: new_language_mappings,
          capabilities_cache: new_capabilities_cache,
          plugin_configs: new_plugin_configs
        }
    end
  end

  defp validate_plugin(plugin_module) do
    required_functions = [
      {:language, 0},
      {:file_extensions, 0},
      {:capabilities, 0},
      {:parse, 2},
      {:validate, 1},
      {:extract_symbols, 1},
      {:get_syntax_tokens, 1},
      {:get_folding_ranges, 1}
    ]
    
    case check_behaviour_implementation(plugin_module, required_functions) do
      :ok -> :ok
      missing_functions -> {:error, {:missing_functions, missing_functions}}
    end
  end

  defp check_behaviour_implementation(module, required_functions) do
    missing = Enum.filter(required_functions, fn {func, arity} ->
      not function_exported?(module, func, arity)
    end)
    
    case missing do
      [] -> :ok
      _ -> missing
    end
  end

  defp extract_plugin_metadata(plugin_module) do
    %{
      name: module_name(plugin_module),
      description: get_module_doc(plugin_module),
      version: get_plugin_version(plugin_module),
      author: get_plugin_author(plugin_module),
      dependencies: get_plugin_dependencies(plugin_module)
    }
  end

  defp module_name(module) do
    module
    |> Module.split()
    |> List.last()
  end

  defp get_module_doc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} -> doc
      _ -> "No description available"
    end
  end

  defp get_plugin_version(_module) do
    # In a real implementation, this would read from plugin metadata
    "1.0.0"
  end

  defp get_plugin_author(_module) do
    # In a real implementation, this would read from plugin metadata
    "Unknown"
  end

  defp get_plugin_dependencies(_module) do
    # In a real implementation, this would analyze plugin dependencies
    []
  end

  defp load_builtin_plugins(state) do
    builtin_plugins = [
      RubberDuck.ILP.Parser.ElixirParser,
      RubberDuck.ILP.Parser.TreeSitterWrapper.Javascript,
      RubberDuck.ILP.Parser.TreeSitterWrapper.Typescript,
      RubberDuck.ILP.Parser.TreeSitterWrapper.Python,
      RubberDuck.ILP.Parser.TreeSitterWrapper.Go,
      RubberDuck.ILP.Parser.TreeSitterWrapper.Rust,
      RubberDuck.ILP.Parser.TreeSitterWrapper.Java,
      RubberDuck.ILP.Parser.TreeSitterWrapper.Cpp,
      RubberDuck.ILP.Parser.TreeSitterWrapper.C,
      RubberDuck.ILP.Parser.TreeSitterWrapper.Ruby
    ]
    
    Enum.reduce(builtin_plugins, state, fn plugin, acc_state ->
      case register_plugin_internal(plugin, [enabled: true], acc_state) do
        {:ok, new_state} -> new_state
        {:error, reason} ->
          Logger.warning("Failed to register builtin plugin #{plugin}: #{inspect(reason)}")
          acc_state
      end
    end)
  end

  defp load_plugins_from_dir(directory, state) do
    case File.ls(directory) do
      {:ok, files} ->
        plugin_files = Enum.filter(files, &String.ends_with?(&1, ".ex"))
        
        Enum.reduce_while(plugin_files, {:ok, state}, fn file, {:ok, acc_state} ->
          file_path = Path.join(directory, file)
          
          case load_plugin_from_file(file_path, acc_state) do
            {:ok, new_state} -> {:cont, {:ok, new_state}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      
      {:error, reason} ->
        {:error, {:directory_error, reason}}
    end
  end

  defp load_plugin_from_file(file_path, state) do
    try do
      # In a real implementation, this would compile and load the plugin module
      # For now, we'll simulate successful loading
      Logger.info("Would load plugin from: #{file_path}")
      {:ok, state}
    rescue
      e ->
        {:error, {:load_error, e}}
    end
  end
end

defmodule RubberDuck.ILP.Parser.Plugin do
  @moduledoc """
  Base module for parser plugins with common functionality.
  """

  @doc """
  Macro for creating parser plugins.
  """
  defmacro __using__(opts) do
    language = Keyword.get(opts, :language)
    extensions = Keyword.get(opts, :extensions, [])
    
    quote do
      @behaviour RubberDuck.ILP.Parser.Behaviour
      
      @language unquote(language)
      @extensions unquote(extensions)
      
      @impl true
      def language, do: @language
      
      @impl true
      def file_extensions, do: @extensions
      
      # Default implementations that can be overridden
      @impl true
      def capabilities do
        %{
          supports_incremental: false,
          supports_syntax_highlighting: true,
          supports_folding: true,
          supports_symbols: true,
          supports_semantic_tokens: false
        }
      end
      
      @impl true
      def validate(source) do
        case parse(source) do
          {:ok, _} -> {:ok, []}
          {:error, reason} -> {:error, [%{line: 1, column: 0, message: inspect(reason)}]}
        end
      end
      
      @impl true
      def extract_symbols(_ast) do
        []
      end
      
      @impl true
      def get_syntax_tokens(_source) do
        []
      end
      
      @impl true
      def get_folding_ranges(_ast) do
        []
      end
      
      defoverridable [
        capabilities: 0,
        validate: 1,
        extract_symbols: 1,
        get_syntax_tokens: 1,
        get_folding_ranges: 1
      ]
    end
  end

  @doc """
  Helper function to create a plugin configuration.
  """
  def create_config(opts) do
    %{
      enabled: Keyword.get(opts, :enabled, true),
      priority: Keyword.get(opts, :priority, 5),
      settings: Keyword.get(opts, :settings, %{}),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Helper function to merge plugin configurations.
  """
  def merge_configs(base_config, override_config) do
    Map.merge(base_config, override_config, fn
      :settings, base_settings, override_settings ->
        Map.merge(base_settings, override_settings)
      _key, _base_value, override_value ->
        override_value
    end)
  end

  @doc """
  Helper function to validate plugin configuration.
  """
  def validate_config(config) do
    required_keys = [:enabled, :priority]
    
    case Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      true -> :ok
      false -> {:error, :invalid_config}
    end
  end
end
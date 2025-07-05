defmodule RubberDuck.Plugin do
  @moduledoc """
  Behavior for RubberDuck plugins.
  
  Plugins provide a way to extend the system with new capabilities
  without modifying core engine code. Each plugin must implement
  this behavior to ensure consistent integration.
  
  ## Example
  
      defmodule MyPlugin do
        @behaviour RubberDuck.Plugin
        
        @impl true
        def name, do: :my_plugin
        
        @impl true
        def version, do: "1.0.0"
        
        @impl true
        def description, do: "My awesome plugin"
        
        @impl true
        def supported_types, do: [:text, :code]
        
        @impl true
        def dependencies, do: []
        
        @impl true
        def init(config) do
          # Initialize plugin state
          {:ok, %{config: config}}
        end
        
        @impl true
        def execute(input, state) do
          # Process input and return result
          {:ok, transform(input), state}
        end
        
        @impl true
        def terminate(_reason, _state) do
          # Cleanup if needed
          :ok
        end
      end
  """
  
  @type name :: atom()
  @type version :: String.t()
  @type plugin_type :: :preprocessor | :processor | :postprocessor | :enhancer
  @type supported_type :: :text | :code | :ast | :binary | :json | :any
  @type dependency :: {name(), version_requirement :: String.t()} | name()
  @type config :: keyword()
  @type state :: any()
  @type input :: any()
  @type output :: any()
  @type reason :: any()
  
  @doc """
  Returns the unique name of the plugin.
  """
  @callback name() :: name()
  
  @doc """
  Returns the version of the plugin.
  """
  @callback version() :: version()
  
  @doc """
  Returns a description of what the plugin does.
  """
  @callback description() :: String.t()
  
  @doc """
  Returns the types of data this plugin can handle.
  """
  @callback supported_types() :: [supported_type()]
  
  @doc """
  Returns the list of other plugins this plugin depends on.
  """
  @callback dependencies() :: [dependency()]
  
  @doc """
  Initializes the plugin with the given configuration.
  
  This is called when the plugin is started and should return
  the initial state for the plugin.
  """
  @callback init(config()) :: {:ok, state()} | {:error, reason()}
  
  @doc """
  Executes the plugin's main logic.
  
  Takes input data and the current plugin state, processes the input,
  and returns the result along with the updated state.
  """
  @callback execute(input(), state()) :: 
    {:ok, output(), state()} | 
    {:error, reason(), state()}
  
  @doc """
  Called when the plugin is being shut down.
  
  Allows the plugin to clean up resources.
  """
  @callback terminate(reason(), state()) :: any()
  
  @doc """
  Optional callback to validate input before processing.
  
  Returns :ok if input is valid, {:error, reason} otherwise.
  """
  @callback validate_input(input()) :: :ok | {:error, reason()}
  
  @doc """
  Optional callback to handle configuration changes.
  
  Called when plugin configuration is updated at runtime.
  """
  @callback handle_config_change(new_config :: config(), state()) :: 
    {:ok, state()} | {:error, reason()}
  
  @optional_callbacks [validate_input: 1, handle_config_change: 2]
  
  @doc """
  Helper function to check if a module implements the Plugin behavior.
  """
  def is_plugin?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
    function_exported?(module, :__info__, 1) and
    module.__info__(:attributes)
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(__MODULE__)
  end
  
  def is_plugin?(_), do: false
  
  @doc """
  Validates that a plugin module implements all required callbacks.
  """
  def validate_plugin(module) when is_atom(module) do
    required_callbacks = [
      name: 0,
      version: 0,
      description: 0,
      supported_types: 0,
      dependencies: 0,
      init: 1,
      execute: 2,
      terminate: 2
    ]
    
    missing = Enum.reject(required_callbacks, fn {func, arity} ->
      function_exported?(module, func, arity)
    end)
    
    case missing do
      [] -> :ok
      callbacks -> {:error, {:missing_callbacks, callbacks}}
    end
  end
  
  def validate_plugin(_), do: {:error, :not_a_module}
end
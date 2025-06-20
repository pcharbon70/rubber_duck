defmodule RubberDuck.Commands.CommandBehaviour do
  @moduledoc """
  Behaviour for defining commands in the distributed commands subsystem.
  
  This behaviour provides a standardized interface for command implementations
  that enables:
  - Unified command execution across all interfaces (CLI, TUI, web, IDE)
  - Distributed command routing and execution
  - Parameter validation and type checking
  - Rich metadata for help generation and interface adaptation
  - Interface-agnostic command definitions
  
  ## Example Implementation
  
      defmodule MyApp.Commands.HelloCommand do
        @behaviour RubberDuck.Commands.CommandBehaviour
        
        alias RubberDuck.Commands.CommandMetadata
        alias RubberDuck.Commands.CommandMetadata.Parameter
        
        @impl true
        def metadata do
          %CommandMetadata{
            name: "hello",
            description: "Greets the user with a friendly message",
            category: :general,
            parameters: [
              %Parameter{
                name: :name,
                type: :string,
                required: false,
                default: "World",
                description: "Name to greet"
              },
              %Parameter{
                name: :uppercase,
                type: :boolean,
                required: false,
                default: false,
                description: "Make greeting uppercase"
              }
            ],
            examples: [
              %{
                description: "Basic greeting",
                command: "hello"
              },
              %{
                description: "Greet someone specific",
                command: "hello --name Alice"
              },
              %{
                description: "Uppercase greeting",
                command: "hello --name Bob --uppercase"
              }
            ]
          }
        end
        
        @impl true
        def validate(params) do
          with :ok <- validate_name(params[:name]),
               :ok <- validate_uppercase(params[:uppercase]) do
            :ok
          end
        end
        
        @impl true
        def execute(params, context) do
          name = params[:name] || "World"
          greeting = "Hello, " <> name <> "!"
          
          result = if params[:uppercase] do
            String.upcase(greeting)
          else
            greeting
          end
          
          {:ok, result}
        end
        
        defp validate_name(nil), do: :ok
        defp validate_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
        defp validate_name(_), do: {:error, [{:name, "must be a non-empty string"}]}
        
        defp validate_uppercase(nil), do: :ok
        defp validate_uppercase(val) when is_boolean(val), do: :ok
        defp validate_uppercase(_), do: {:error, [{:uppercase, "must be a boolean"}]}
      end
  
  ## Command Context
  
  The context parameter passed to `execute/2` contains information about the
  execution environment and may include:
  
  - `:interface` - The interface type (`:cli`, `:tui`, `:web`, `:ide`)
  - `:session_id` - Unique session identifier
  - `:user_id` - User identifier if available
  - `:node` - The node executing the command
  - `:request_id` - Unique request identifier for tracking
  - `:timeout` - Execution timeout
  - Custom context data provided by the calling interface
  
  ## Return Values
  
  Commands can return various types of results:
  
  - `{:ok, result}` - Successful execution with result
  - `{:error, reason}` - Execution failed with error
  - `{:ok, {:stream, stream}}` - Streaming response (for stream: true commands)
  - `{:ok, {:async, task}}` - Async execution reference (for async: true commands)
  """

  alias RubberDuck.Commands.CommandMetadata

  @type params :: map()
  @type context :: map()
  @type result :: any()
  @type validation_error :: {atom(), String.t()}
  @type validation_errors :: [validation_error()]

  @doc """
  Returns the metadata for this command.
  
  The metadata should describe the command's name, description, parameters,
  examples, and other properties that enable the distributed commands subsystem
  to route, validate, and execute the command appropriately.
  
  The metadata is used for:
  - Command registration and discovery
  - Parameter validation
  - Help text generation
  - Interface adaptation
  - Routing decisions
  """
  @callback metadata() :: CommandMetadata.t()

  @doc """
  Validates command parameters before execution.
  
  This callback allows commands to perform custom validation beyond the
  basic type checking provided by the parameter definitions in metadata.
  
  ## Parameters
  
  - `params` - Map of parameter names to values
  
  ## Return Values
  
  - `:ok` - Parameters are valid
  - `{:error, validation_errors}` - Parameters are invalid with specific errors
  
  ## Example
  
      def validate(params) do
        cond do
          is_nil(params[:required_param]) ->
            {:error, [{:required_param, "is required"}]}
            
          params[:number] < 0 ->
            {:error, [{:number, "must be positive"}]}
            
          true ->
            :ok
        end
      end
  """
  @callback validate(params()) :: :ok | {:error, validation_errors()}

  @doc """
  Executes the command with the given parameters and context.
  
  This is the main command logic that performs the actual work. The command
  should be designed to be stateless and side-effect free where possible,
  or at least idempotent.
  
  ## Parameters
  
  - `params` - Map of validated parameter names to values
  - `context` - Execution context with environment information
  
  ## Return Values
  
  - `{:ok, result}` - Successful execution
  - `{:error, reason}` - Execution failed
  - `{:ok, {:stream, stream}}` - For streaming commands
  - `{:ok, {:async, task}}` - For async commands
  
  ## Examples
  
      def execute(params, context) do
        case perform_work(params, context) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      end
      
      # Streaming command
      def execute(params, context) do
        stream = create_data_stream(params)
        {:ok, {:stream, stream}}
      end
      
      # Async command
      def execute(params, context) do
        task = Task.async(fn -> heavy_computation(params) end)
        {:ok, {:async, task}}
      end
  """
  @callback execute(params(), context()) :: 
    {:ok, result()} | 
    {:error, any()} | 
    {:ok, {:stream, Enumerable.t()}} | 
    {:ok, {:async, Task.t()}}

  @doc """
  Helper function to validate that a module implements the CommandBehaviour.
  
  This can be used during command registration to ensure the module properly
  implements all required callbacks.
  """
  @spec validate_implementation!(module()) :: :ok
  def validate_implementation!(module) do
    unless function_exported?(module, :metadata, 0) do
      raise ArgumentError, "Module #{module} must implement metadata/0 callback"
    end

    unless function_exported?(module, :validate, 1) do
      raise ArgumentError, "Module #{module} must implement validate/1 callback"
    end

    unless function_exported?(module, :execute, 2) do
      raise ArgumentError, "Module #{module} must implement execute/2 callback"
    end

    # Validate that metadata returns a proper CommandMetadata struct
    try do
      metadata = module.metadata()
      CommandMetadata.validate!(metadata)
    rescue
      error ->
        raise ArgumentError, "Module #{module} metadata/0 callback returned invalid metadata: #{inspect(error)}"
    end

    :ok
  end

  @doc """
  Helper function to get command name from a module implementing CommandBehaviour.
  """
  @spec command_name(module()) :: String.t()
  def command_name(module) do
    module.metadata().name
  end

  @doc """
  Helper function to check if a command supports async execution.
  """
  @spec async?(module()) :: boolean()
  def async?(module) do
    module.metadata().async
  end

  @doc """
  Helper function to check if a command supports streaming responses.
  """
  @spec stream?(module()) :: boolean()
  def stream?(module) do
    module.metadata().stream
  end

  @doc """
  Helper function to get command category.
  """
  @spec category(module()) :: atom()
  def category(module) do
    module.metadata().category
  end

  @doc """
  Helper function to check if a command is deprecated.
  """
  @spec deprecated?(module()) :: boolean()
  def deprecated?(module) do
    module.metadata().deprecated
  end
end
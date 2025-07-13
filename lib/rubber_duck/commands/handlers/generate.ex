defmodule RubberDuck.Commands.Handlers.Generate do
  @moduledoc """
  Handler for code generation commands.
  
  Generates code from natural language descriptions using the generation engine.
  """

  @behaviour RubberDuck.Commands.Handler

  alias RubberDuck.Commands.{Command, Handler}
  alias RubberDuck.Engine.Manager

  require Logger

  @impl true
  def execute(%Command{name: :generate, args: args, options: options} = command) do
    with :ok <- validate(command) do
      language = Map.get(options, :language, "elixir") |> String.to_atom()
      
      # Prepare input for the generation engine
      engine_input = %{
        prompt: args.description,
        language: language,
        context: %{
          project_files: Map.get(command.context.metadata, :project_files, []),
          current_file: Map.get(command.context.metadata, :current_file),
          imports: Map.get(command.context.metadata, :imports, [])
        }
      }

      Logger.debug("Calling generation engine with input: #{inspect(engine_input)}")

      # Call the real generation engine
      case Manager.execute(:generation, engine_input) do
        {:ok, result} ->
          {:ok, %{
            generated_code: result.code,
            language: to_string(result.language),
            description: args.description,
            imports: result.imports,
            confidence: result.confidence,
            explanation: result.explanation,
            timestamp: DateTime.utc_now()
          }}
        
        {:error, :engine_not_found} ->
          Logger.warning("Generation engine not found, falling back to mock")
          # Fallback to mock if engine not available
          generated_code = generate_mock_code(args.description, to_string(language))
          
          {:ok, %{
            generated_code: generated_code,
            language: to_string(language),
            description: args.description,
            timestamp: DateTime.utc_now(),
            fallback: true
          }}
          
        {:error, reason} = error ->
          Logger.error("Generation engine error: #{inspect(reason)}")
          error
      end
    end
  end

  def execute(_command) do
    {:error, "Invalid command for generate handler"}
  end

  @impl true
  def validate(%Command{name: :generate, args: args}) do
    Handler.validate_required_args(%{args: args}, [:description])
  end
  
  def validate(_), do: {:error, "Invalid command for generate handler"}

  # Private functions

  defp generate_mock_code(description, language) do
    case language do
      "elixir" ->
        """
        # Generated from: #{description}
        defmodule GeneratedModule do
          @moduledoc \"\"\"
          #{description}
          \"\"\"

          def example_function do
            :ok
          end
        end
        """
        
      "python" ->
        """
        # Generated from: #{description}
        class GeneratedClass:
            \"\"\"#{description}\"\"\"
            
            def example_method(self):
                return True
        """
        
      _ ->
        """
        // Generated from: #{description}
        // Language: #{language}
        // This is a placeholder implementation
        """
    end
  end
end
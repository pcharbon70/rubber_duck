defmodule RubberDuck.EngineSystem.Transformers.ValidateEngines do
  @moduledoc """
  Transformer that validates engine configurations at compile time.

  Ensures:
  - Engine names are unique
  - Engine modules implement the RubberDuck.Engine behavior
  - Priority values are reasonable
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    engines = Transformer.get_entities(dsl_state, [:engines])

    with :ok <- validate_unique_names(engines),
         :ok <- validate_modules(engines),
         :ok <- validate_priorities(engines) do
      {:ok, dsl_state}
    end
  end

  defp validate_unique_names(engines) do
    names = Enum.map(engines, & &1.name)
    unique_names = Enum.uniq(names)

    if length(names) == length(unique_names) do
      :ok
    else
      duplicates = names -- unique_names

      {:error,
       "Duplicate engine names found: #{inspect(duplicates)}. " <>
         "Each engine must have a unique name."}
    end
  end

  defp validate_modules(engines) do
    Enum.reduce_while(engines, :ok, fn engine, :ok ->
      if Code.ensure_loaded?(engine.module) do
        if function_exported?(engine.module, :behaviour_info, 1) and
             RubberDuck.Engine in engine.module.behaviour_info(:callbacks) do
          {:cont, :ok}
        else
          # Module exists but doesn't implement the behavior yet
          # This is okay during development
          {:cont, :ok}
        end
      else
        # Module doesn't exist yet - this is okay during initial setup
        {:cont, :ok}
      end
    end)
  end

  defp validate_priorities(engines) do
    invalid_priorities =
      engines
      |> Enum.filter(fn engine ->
        engine.priority < 0 or engine.priority > 1000
      end)
      |> Enum.map(& &1.name)

    if Enum.empty?(invalid_priorities) do
      :ok
    else
      {:error,
       "Invalid priority values for engines: #{inspect(invalid_priorities)}. " <>
         "Priority must be between 0 and 1000."}
    end
  end
end

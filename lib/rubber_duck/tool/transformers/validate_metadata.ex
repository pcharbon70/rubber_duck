defmodule RubberDuck.Tool.Transformers.ValidateMetadata do
  @moduledoc """
  Validates that required metadata is present and valid.
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    # Name is already validated as required by the schema
    # Validate version format if provided
    case Spark.Dsl.Extension.get_opt(dsl_state, [:tool], :version) do
      nil ->
        {:ok, dsl_state}

      version ->
        case Version.parse(version) do
          {:ok, _} ->
            {:ok, dsl_state}

          :error ->
            {:error,
             Spark.Error.DslError.exception(
               module: Spark.Dsl.Extension.get_persisted(dsl_state, :module),
               message: "Invalid version format: #{inspect(version)}. Must be semantic version (e.g., '1.0.0')",
               path: [:tool, :version]
             )}
        end
    end
  end
end

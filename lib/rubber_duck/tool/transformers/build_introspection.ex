defmodule RubberDuck.Tool.Transformers.BuildIntrospection do
  @moduledoc """
  Builds introspection functions for accessing tool metadata at runtime.
  """
  
  use Spark.Dsl.Transformer
  
  def transform(dsl_state) do
    _module = Spark.Dsl.Extension.get_persisted(dsl_state, :module)
    
    # Get all the tool configuration
    name = Spark.Dsl.Extension.get_opt(dsl_state, [:tool], :name)
    description = Spark.Dsl.Extension.get_opt(dsl_state, [:tool], :description)
    category = Spark.Dsl.Extension.get_opt(dsl_state, [:tool], :category)
    version = Spark.Dsl.Extension.get_opt(dsl_state, [:tool], :version, "1.0.0")
    tags = Spark.Dsl.Extension.get_opt(dsl_state, [:tool], :tags, [])
    
    # Get entities
    parameters = Spark.Dsl.Extension.get_entities(dsl_state, [:tool])
                 |> Enum.filter(&match?(%RubberDuck.Tool.Parameter{}, &1))
    execution = Spark.Dsl.Extension.get_entities(dsl_state, [:tool])
                |> Enum.find(&match?(%RubberDuck.Tool.Execution{}, &1))
    security = Spark.Dsl.Extension.get_entities(dsl_state, [:tool])
               |> Enum.find(&match?(%RubberDuck.Tool.Security{}, &1))
    
    # Build the introspection function
    introspection_fn = quote do
      def __tool__(:name), do: unquote(name)
      def __tool__(:description), do: unquote(description)
      def __tool__(:category), do: unquote(category)
      def __tool__(:version), do: unquote(version)
      def __tool__(:tags), do: unquote(tags)
      def __tool__(:parameters), do: unquote(Macro.escape(parameters))
      def __tool__(:execution), do: unquote(Macro.escape(execution))
      def __tool__(:security), do: unquote(Macro.escape(security))
      
      def __tool__(:all) do
        %{
          name: __tool__(:name),
          description: __tool__(:description),
          category: __tool__(:category),
          version: __tool__(:version),
          tags: __tool__(:tags),
          parameters: __tool__(:parameters),
          execution: __tool__(:execution),
          security: __tool__(:security)
        }
      end
    end
    
    {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], introspection_fn)}
  end
end
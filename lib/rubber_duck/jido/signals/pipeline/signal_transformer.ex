defmodule RubberDuck.Jido.Signals.Pipeline.SignalTransformer do
  @moduledoc """
  Behaviour for signal transformers in the processing pipeline.
  
  Signal transformers modify, enrich, validate, or filter signals
  as they flow through the processing pipeline. All transformers
  must maintain CloudEvents compliance through Jido.Signal.
  """
  
  @type transform_result :: {:ok, map()} | {:error, term()} | {:skip, term()}
  @type transformer_opts :: keyword()
  
  @doc """
  Transforms a signal.
  
  Returns:
  - `{:ok, transformed_signal}` - Successfully transformed signal
  - `{:error, reason}` - Transformation failed, halt pipeline
  - `{:skip, reason}` - Skip this transformer, continue pipeline
  """
  @callback transform(signal :: map(), opts :: transformer_opts()) :: transform_result()
  
  @doc """
  Validates if a signal should be processed by this transformer.
  """
  @callback should_transform?(signal :: map(), opts :: transformer_opts()) :: boolean()
  
  @doc """
  Returns transformer metadata for monitoring.
  """
  @callback metadata() :: map()
  
  @optional_callbacks [should_transform?: 2, metadata: 0]
  
  @doc """
  Helper macro for implementing transformers.
  """
  defmacro __using__(opts \\ []) do
    quote do
      @behaviour RubberDuck.Jido.Signals.Pipeline.SignalTransformer
      
      @transformer_name unquote(Keyword.get(opts, :name, __MODULE__))
      @transformer_priority unquote(Keyword.get(opts, :priority, 50))
      
      require Logger
      
      @impl true
      def should_transform?(_signal, _opts), do: true
      
      @impl true
      def metadata do
        %{
          name: @transformer_name,
          priority: @transformer_priority,
          module: __MODULE__
        }
      end
      
      defoverridable [should_transform?: 2, metadata: 0]
      
      @doc """
      Applies the transformer to a signal.
      """
      def apply(signal, opts \\ []) do
        if should_transform?(signal, opts) do
          start_time = System.monotonic_time(:microsecond)
          
          result = transform(signal, opts)
          
          duration = System.monotonic_time(:microsecond) - start_time
          
          # Emit telemetry
          :telemetry.execute(
            [:rubber_duck, :signal, :transformer],
            %{duration: duration},
            %{
              transformer: @transformer_name,
              status: transform_status(result)
            }
          )
          
          result
        else
          {:skip, :not_applicable}
        end
      end
      
      defp transform_status({:ok, _}), do: :success
      defp transform_status({:error, _}), do: :error
      defp transform_status({:skip, _}), do: :skip
    end
  end
end
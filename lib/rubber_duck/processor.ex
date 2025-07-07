defprotocol RubberDuck.Processor do
  @moduledoc """
  Protocol for processing different data types in the RubberDuck system.

  The Processor protocol provides a unified interface for transforming
  various data types into formats suitable for engines and plugins to consume.

  ## Core Functions

  - `process/2` - Transform data with given options
  - `metadata/1` - Extract metadata from the data
  - `validate/1` - Validate data format
  - `normalize/1` - Normalize data to standard format

  ## Example Implementation

      defimpl RubberDuck.Processor, for: MyCustomType do
        def process(data, opts) do
          # Transform data based on options
          {:ok, transformed_data}
        end
        
        def metadata(data) do
          %{
            type: :custom,
            size: calculate_size(data),
            timestamp: DateTime.utc_now()
          }
        end
        
        def validate(data) do
          if valid?(data), do: :ok, else: {:error, :invalid_format}
        end
        
        def normalize(data) do
          # Convert to standard representation
          standardize(data)
        end
      end
  """

  @type opts :: keyword()
  @type metadata :: map()
  @type error :: {:error, term()}

  @doc """
  Process the data with the given options.

  Options may include:
  - `:format` - Target format for transformation
  - `:context` - Additional context for processing
  - `:validate` - Whether to validate before processing

  Returns `{:ok, processed_data}` or `{:error, reason}`.
  """
  @spec process(t, opts()) :: {:ok, any()} | error()
  def process(data, opts \\ [])

  @doc """
  Extract metadata from the data.

  Returns a map containing relevant metadata such as:
  - Type information
  - Size/length
  - Structure details
  - Any type-specific metadata
  """
  @spec metadata(t) :: metadata()
  def metadata(data)

  @doc """
  Validate the data format.

  Returns `:ok` if valid, `{:error, reason}` otherwise.
  """
  @spec validate(t) :: :ok | error()
  def validate(data)

  @doc """
  Normalize the data to a standard format.

  This function should convert the data to a canonical representation
  that can be consistently processed by the system.
  """
  @spec normalize(t) :: t
  def normalize(data)
end

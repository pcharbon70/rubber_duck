defprotocol RubberDuck.Enhancer do
  @moduledoc """
  Protocol for enhancing data with additional context and information.

  The Enhancer protocol provides a unified interface for augmenting
  data with metadata, context, and derived information that can improve
  processing by engines and plugins.

  ## Core Functions

  - `enhance/2` - Enhance data with context
  - `with_context/2` - Add contextual information
  - `with_metadata/2` - Enrich with metadata
  - `derive/2` - Derive new information from data

  ## Example Implementation

      defimpl RubberDuck.Enhancer, for: MyCustomType do
        def enhance(data, strategy) do
          # Apply enhancement strategy
          {:ok, enhanced_data}
        end
        
        def with_context(data, context) do
          # Add context to data
          Map.put(data, :context, context)
        end
        
        def with_metadata(data, metadata) do
          # Attach metadata
          Map.put(data, :metadata, metadata)
        end
        
        def derive(data, derivations) do
          # Derive new information
          apply_derivations(data, derivations)
        end
      end
  """

  @type strategy :: atom() | {atom(), keyword()}
  @type context :: map()
  @type metadata :: map()
  @type derivation :: atom() | {atom(), keyword()}
  @type error :: {:error, term()}

  @doc """
  Enhance the data using the specified strategy.

  Common strategies include:
  - `:semantic` - Add semantic information
  - `:structural` - Add structural annotations
  - `:temporal` - Add time-based context
  - `:relational` - Add relationship information
  - `{:custom, opts}` - Custom enhancement with options

  Returns `{:ok, enhanced_data}` or `{:error, reason}`.
  """
  @spec enhance(t, strategy()) :: {:ok, any()} | error()
  def enhance(data, strategy)

  @doc """
  Add contextual information to the data.

  Context might include:
  - Source information
  - Processing history
  - Related data references
  - Environmental context
  """
  @spec with_context(t, context()) :: t
  def with_context(data, context)

  @doc """
  Enrich data with metadata.

  Metadata might include:
  - Creation/modification timestamps
  - Author/owner information
  - Quality metrics
  - Processing instructions
  """
  @spec with_metadata(t, metadata()) :: t
  def with_metadata(data, metadata)

  @doc """
  Derive new information from the data.

  Derivations might include:
  - `:summary` - Generate summary
  - `:statistics` - Calculate statistics
  - `:relationships` - Identify relationships
  - `:patterns` - Extract patterns
  - `{:custom, opts}` - Custom derivation
  """
  @spec derive(t, derivation() | [derivation()]) :: {:ok, map()} | error()
  def derive(data, derivations)
end

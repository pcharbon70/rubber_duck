defmodule RubberDuckCore.Protocols do
  @moduledoc """
  Core protocols for the RubberDuck system.
  
  These protocols define common interfaces that can be implemented
  across different modules and applications in the umbrella project.
  """

  defprotocol Serializable do
    @moduledoc """
    Protocol for serializing data structures to maps for storage or transmission.
    """
    
    @doc "Converts the data structure to a serializable map"
    def to_map(data)
    
    @doc "Converts the data structure from a map"
    def from_map(map, type)
  end

  defprotocol Cacheable do
    @moduledoc """
    Protocol for determining cache behavior of data structures.
    """
    
    @doc "Returns the cache key for the data"
    def cache_key(data)
    
    @doc "Returns the cache TTL in seconds"
    def cache_ttl(data)
    
    @doc "Determines if the data should be cached"
    def cacheable?(data)
  end

  defprotocol Analyzable do
    @moduledoc """
    Protocol for data that can be analyzed by engines.
    """
    
    @doc "Returns the analysis type for the data"
    def analysis_type(data)
    
    @doc "Extracts analyzable content from the data"
    def extract_content(data)
    
    @doc "Returns metadata for analysis"
    def analysis_metadata(data)
  end
end
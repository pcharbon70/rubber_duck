defmodule RubberDuck.MCP.Registry.MetadataTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.MCP.Registry.Metadata
  
  @moduletag :mcp_registry
  
  defmodule SampleTool do
    @moduledoc """
    A sample tool for testing metadata extraction.
    
    This tool demonstrates various metadata attributes.
    """
    
    @category :sample
    @tags [:test, :example, :metadata]
    @capabilities [:text_processing, :validation]
    @version "1.2.3"
    @examples [
      %{
        description: "Basic example",
        params: %{input: "test"}
      }
    ]
    @performance %{
      avg_latency_ms: 50,
      max_concurrent: 5
    }
    @dependencies [SomeDependency]
    
    use Hermes.Server.Component, type: :tool
    
    schema do
      field :input, {:required, :string}
      field :async, :boolean
      field :stream, :boolean
    end
    
    def execute(_, frame), do: {:ok, %{}, frame}
    def input_schema, do: %{"properties" => %{"input" => %{}, "async" => %{}, "stream" => %{}}}
  end
  
  describe "metadata extraction" do
    test "extracts basic module information" do
      metadata = Metadata.extract_from_module(SampleTool)
      
      assert metadata.module == SampleTool
      assert metadata.name == "Sample tool"
      assert String.starts_with?(metadata.description, "A sample tool")
      assert metadata.source == :internal
      assert %DateTime{} = metadata.registered_at
    end
    
    test "extracts module attributes" do
      metadata = Metadata.extract_from_module(SampleTool)
      
      assert metadata.category == :sample
      assert :test in metadata.tags
      assert :example in metadata.tags
      assert :metadata in metadata.tags
      assert :text_processing in metadata.capabilities
      assert :validation in metadata.capabilities
      assert metadata.version == "1.2.3"
    end
    
    test "extracts examples and performance data" do
      metadata = Metadata.extract_from_module(SampleTool)
      
      assert [%{description: "Basic example", params: %{input: "test"}}] = metadata.examples
      assert metadata.performance.avg_latency_ms == 50
      assert metadata.performance.max_concurrent == 5
    end
    
    test "extracts dependencies" do
      metadata = Metadata.extract_from_module(SampleTool)
      
      assert SomeDependency in metadata.dependencies
    end
    
    test "extracts schema information" do
      metadata = Metadata.extract_from_module(SampleTool)
      
      assert metadata.schema["properties"]["input"]
      assert metadata.schema["properties"]["async"]
      assert metadata.schema["properties"]["stream"]
    end
    
    test "infers capabilities from schema" do
      metadata = Metadata.extract_from_module(SampleTool)
      
      # Should include inferred capabilities
      assert :async in metadata.capabilities
      assert :streaming in metadata.capabilities
    end
    
    test "uses defaults when attributes missing" do
      defmodule MinimalTool do
        use Hermes.Server.Component, type: :tool
        
        schema do
          field :data, :string
        end
        
        def execute(_, frame), do: {:ok, %{}, frame}
      end
      
      metadata = Metadata.extract_from_module(MinimalTool)
      
      assert metadata.category == :general
      assert metadata.tags == []
      assert metadata.version == "1.0.0"
      assert metadata.examples == []
    end
    
    test "merges options with extracted data" do
      opts = [
        category: :custom,
        tags: [:additional],
        version: "2.0.0",
        source: :external
      ]
      
      metadata = Metadata.extract_from_module(SampleTool, opts)
      
      assert metadata.category == :sample  # Module attribute takes precedence
      assert :additional in metadata.tags   # Merged with module tags
      assert metadata.version == "1.2.3"    # Module attribute takes precedence
      assert metadata.source == :external   # From opts
    end
  end
  
  describe "metadata manipulation" do
    test "updates metadata fields" do
      metadata = Metadata.extract_from_module(SampleTool)
      updated = Metadata.update(metadata, version: "2.0.0", tags: [:updated])
      
      assert updated.version == "2.0.0"
      assert updated.tags == [:updated]
      assert updated.module == SampleTool  # Unchanged
    end
    
    test "converts to JSON-compatible map" do
      metadata = Metadata.extract_from_module(SampleTool)
      map = Metadata.to_map(metadata)
      
      assert is_map(map)
      assert map.module == "RubberDuck.MCP.Registry.MetadataTest.SampleTool"
      assert map.name == metadata.name
      assert map.category == metadata.category
      assert is_binary(map.registered_at)
      assert map.dependencies == ["RubberDuck.MCP.Registry.MetadataTest.SomeDependency"]
    end
  end
  
  describe "edge cases" do
    test "handles module without docs" do
      defmodule NoDocsTools do
        @category :nodocs
        
        use Hermes.Server.Component, type: :tool
        
        schema do
          field :x, :integer
        end
        
        def execute(_, frame), do: {:ok, %{}, frame}
      end
      
      metadata = Metadata.extract_from_module(NoDocsTools)
      assert metadata.description == "No description available"
    end
    
    test "handles module without schema function" do
      defmodule NoSchemaFunc do
        use Hermes.Server.Component, type: :tool
        
        schema do
          field :y, :string
        end
        
        def execute(_, frame), do: {:ok, %{}, frame}
      end
      
      metadata = Metadata.extract_from_module(NoSchemaFunc)
      assert metadata.schema == nil
    end
  end
end
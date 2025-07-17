defmodule RubberDuck.Tool.CapabilityAPITest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.CapabilityAPI
  
  # Mock tools for testing
  defmodule DataTool do
    use RubberDuck.Tool
    
    tool do
      metadata do
        name :data_tool
        description "Tool for data processing"
        category :data
        version "2.0.0"
      end
      
      parameter :input_file do
        type :string
        required true
        description "Path to input file"
      end
      
      security do
        level :balanced
        capabilities [:file_read]
      end
      
      execution do
        async true
        timeout 60_000
        handler fn params, _context -> {:ok, "data processed"} end
      end
    end
  end
  
  defmodule AnalysisTool do
    use RubberDuck.Tool
    
    tool do
      metadata do
        name :analysis_tool
        description "Tool for data analysis"
        category :analysis
      end
      
      parameter :data do
        type {:array, :float}
        required true
        description "Data to analyze"
      end
      
      execution do
        handler fn params, _context -> {:ok, %{mean: 42.0}} end
      end
    end
  end
  
  setup do
    # Register test tools
    RubberDuck.Tool.Registry.register(DataTool)
    RubberDuck.Tool.Registry.register(AnalysisTool)
    
    on_exit(fn ->
      RubberDuck.Tool.Registry.unregister(:data_tool)
      RubberDuck.Tool.Registry.unregister(:analysis_tool)
    end)
    
    :ok
  end
  
  describe "list_capabilities/1" do
    test "lists all tool capabilities" do
      capabilities = CapabilityAPI.list_capabilities()
      
      assert length(capabilities) >= 2
      assert Enum.any?(capabilities, & &1.name == :data_tool)
      assert Enum.any?(capabilities, & &1.name == :analysis_tool)
    end
    
    test "includes metrics when requested" do
      capabilities = CapabilityAPI.list_capabilities(include_metrics: true)
      
      tool = Enum.find(capabilities, & &1.name == :data_tool)
      assert Map.has_key?(tool, :metrics)
      assert is_map(tool.metrics)
    end
    
    test "filters by category" do
      capabilities = CapabilityAPI.list_capabilities(category: :data)
      
      assert length(capabilities) >= 1
      assert Enum.all?(capabilities, & &1.category == :data)
    end
    
    test "includes correct capability information" do
      capabilities = CapabilityAPI.list_capabilities()
      
      data_tool = Enum.find(capabilities, & &1.name == :data_tool)
      assert data_tool.version == "2.0.0"
      assert data_tool.capabilities.async_supported == true
      assert data_tool.capabilities.cancellable == true
      assert data_tool.security.sandbox_level == :balanced
    end
  end
  
  describe "get_capability/2" do
    test "gets detailed capability for specific tool" do
      assert {:ok, capability} = CapabilityAPI.get_capability(:data_tool)
      
      assert capability.name == :data_tool
      assert capability.description == "Tool for data processing"
      assert length(capability.parameters) == 1
      assert hd(capability.parameters).name == :input_file
    end
    
    test "includes examples when available" do
      assert {:ok, capability} = CapabilityAPI.get_capability(:data_tool, include_examples: true)
      
      assert Map.has_key?(capability, :examples)
    end
    
    test "returns error for non-existent tool" do
      assert {:error, :not_found} = CapabilityAPI.get_capability(:nonexistent_tool)
    end
  end
  
  describe "get_composition_capabilities/0" do
    test "returns composition capabilities status" do
      capabilities = CapabilityAPI.get_composition_capabilities()
      
      assert capabilities.supported == false
      assert is_list(capabilities.planned_features)
      assert "Tool chaining" in capabilities.planned_features
      assert capabilities.availability == "Future release"
    end
  end
  
  describe "get_openapi_spec/0" do
    test "generates valid OpenAPI specification" do
      spec = CapabilityAPI.get_openapi_spec()
      
      assert spec["openapi"] == "3.0.0"
      assert spec["info"]["title"] == "RubberDuck Tool API"
      assert is_map(spec["paths"])
      assert Map.has_key?(spec["paths"], "/tools/data_tool")
      assert Map.has_key?(spec["paths"], "/tools/analysis_tool")
    end
    
    test "includes security schemes" do
      spec = CapabilityAPI.get_openapi_spec()
      
      assert spec["components"]["securitySchemes"]["bearerAuth"]["type"] == "http"
      assert spec["security"] == [%{"bearerAuth" => []}]
    end
  end
  
  describe "search_by_capability/2" do
    test "searches tools by query" do
      assert {:ok, results} = CapabilityAPI.search_by_capability("data")
      
      assert length(results) >= 1
      assert Enum.any?(results, & &1.tool_name == :data_tool)
      
      # Check relevance scores
      assert Enum.all?(results, & &1.relevance_score > 0)
    end
    
    test "highlights matching context" do
      assert {:ok, results} = CapabilityAPI.search_by_capability("analysis")
      
      analysis_result = Enum.find(results, & &1.tool_name == :analysis_tool)
      assert analysis_result.matching_context =~ "**analysis**"
    end
    
    test "respects limit option" do
      assert {:ok, results} = CapabilityAPI.search_by_capability("tool", limit: 1)
      
      assert length(results) == 1
    end
  end
  
  describe "get_recommendations/2" do
    test "returns tool recommendations based on context" do
      context = %{
        recent_tools: [:data_tool],
        preferred_category: :analysis
      }
      
      assert {:ok, recommendations} = CapabilityAPI.get_recommendations(context)
      
      assert is_list(recommendations)
      assert length(recommendations) <= 5
      
      # Should recommend analysis tool since we recently used data tool
      assert Enum.any?(recommendations, & &1.tool_name == :analysis_tool)
    end
    
    test "includes recommendation reasons" do
      context = %{recent_tools: []}
      
      assert {:ok, recommendations} = CapabilityAPI.get_recommendations(context)
      
      assert Enum.all?(recommendations, fn rec ->
        is_list(rec.reasons) and length(rec.reasons) > 0
      end)
    end
  end
  
  describe "get_tool_metrics/1" do
    test "returns mock metrics for existing tool" do
      assert {:ok, metrics} = CapabilityAPI.get_tool_metrics(:data_tool)
      
      assert is_map(metrics)
      assert Map.has_key?(metrics, :total_executions)
      assert Map.has_key?(metrics, :success_rate)
      assert Map.has_key?(metrics, :average_duration_ms)
    end
    
    test "returns error for non-existent tool" do
      assert {:error, :not_found} = CapabilityAPI.get_tool_metrics(:nonexistent)
    end
  end
  
  describe "get_dependencies/1" do
    test "returns tool dependencies" do
      assert {:ok, deps} = CapabilityAPI.get_dependencies(:data_tool)
      
      assert deps.tool_name == :data_tool
      assert is_list(deps.runtime_dependencies)
      assert deps.capability_dependencies == [:file_read]
      assert is_map(deps.system_requirements)
    end
  end
end
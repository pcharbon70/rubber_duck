defmodule RubberDuck.Tool.RegistryTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Tool.Registry
  
  defmodule TestTool do
    use RubberDuck.Tool
    
    tool do
      name :test_tool
      description "A test tool"
      category :testing
      version "1.0.0"
      tags [:test, :example]
      
      parameter :input do
        type :string
        required true
      end
      
      execution do
        handler &TestTool.execute/2
      end
    end
    
    def execute(params, _context) do
      {:ok, "Processed: #{params.input}"}
    end
  end
  
  defmodule TestToolV2 do
    use RubberDuck.Tool
    
    tool do
      name :test_tool
      description "A test tool version 2"
      category :testing
      version "2.0.0"
      tags [:test, :example, :v2]
      
      parameter :input do
        type :string
        required true
      end
      
      parameter :mode do
        type :string
        default "normal"
      end
      
      execution do
        handler &TestToolV2.execute/2
      end
    end
    
    def execute(params, _context) do
      {:ok, "V2 Processed: #{params.input} in #{params.mode} mode"}
    end
  end
  
  defmodule AnotherTool do
    use RubberDuck.Tool
    
    tool do
      name :another_tool
      description "Another test tool"
      category :utilities
      version "1.0.0"
      tags [:utility, :helper]
      
      execution do
        handler &AnotherTool.execute/2
      end
    end
    
    def execute(_params, _context) do
      {:ok, "Another tool executed"}
    end
  end
  
  setup do
    # Ensure registry is started fresh for each test
    case Process.whereis(Registry) do
      nil -> :ok
      pid when is_pid(pid) -> 
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
    end
    
    {:ok, pid} = Registry.start_link()
    
    # Clean up after test
    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)
    
    :ok
  end
  
  describe "tool registration" do
    test "registers a tool successfully" do
      assert :ok = Registry.register(TestTool)
      
      # Verify it was registered
      assert {:ok, tool} = Registry.get(:test_tool)
      assert tool.module == TestTool
      assert tool.name == :test_tool
      assert tool.version == "1.0.0"
    end
    
    test "registers multiple versions of same tool" do
      assert :ok = Registry.register(TestTool)
      assert :ok = Registry.register(TestToolV2)
      
      # Get specific version
      assert {:ok, tool_v1} = Registry.get(:test_tool, "1.0.0")
      assert tool_v1.module == TestTool
      assert tool_v1.version == "1.0.0"
      
      assert {:ok, tool_v2} = Registry.get(:test_tool, "2.0.0")
      assert tool_v2.module == TestToolV2
      assert tool_v2.version == "2.0.0"
      
      # Get latest version by default
      assert {:ok, latest} = Registry.get(:test_tool)
      assert latest.module == TestToolV2
      assert latest.version == "2.0.0"
    end
    
    test "returns error for non-existent tool" do
      assert {:error, :not_found} = Registry.get(:non_existent)
    end
    
    test "validates tool module before registration" do
      assert {:error, :invalid_tool} = Registry.register(NonExistentModule)
    end
  end
  
  describe "tool listing and querying" do
    setup do
      Registry.register(TestTool)
      Registry.register(TestToolV2)
      Registry.register(AnotherTool)
      :ok
    end
    
    test "lists all registered tools" do
      tools = Registry.list_all()
      assert length(tools) == 3
      
      # Should include all versions
      assert Enum.any?(tools, &(&1.module == TestTool))
      assert Enum.any?(tools, &(&1.module == TestToolV2))
      assert Enum.any?(tools, &(&1.module == AnotherTool))
    end
    
    test "lists latest version of each tool" do
      tools = Registry.list()
      assert length(tools) == 2
      
      # Should only include latest versions
      assert Enum.any?(tools, &(&1.module == TestToolV2 && &1.name == :test_tool))
      assert Enum.any?(tools, &(&1.module == AnotherTool))
      refute Enum.any?(tools, &(&1.module == TestTool))
    end
    
    test "filters tools by category" do
      testing_tools = Registry.list_by_category(:testing)
      assert length(testing_tools) == 2
      assert Enum.all?(testing_tools, &(&1.category == :testing))
      
      utility_tools = Registry.list_by_category(:utilities)
      assert length(utility_tools) == 1
      assert hd(utility_tools).module == AnotherTool
    end
    
    test "filters tools by tags" do
      test_tagged = Registry.list_by_tag(:test)
      assert length(test_tagged) == 2
      assert Enum.all?(test_tagged, &(:test in &1.tags))
      
      v2_tagged = Registry.list_by_tag(:v2)
      assert length(v2_tagged) == 1
      assert hd(v2_tagged).module == TestToolV2
    end
    
    test "lists all versions of a specific tool" do
      versions = Registry.list_versions(:test_tool)
      assert length(versions) == 2
      assert Enum.any?(versions, &(&1 == "1.0.0"))
      assert Enum.any?(versions, &(&1 == "2.0.0"))
    end
  end
  
  describe "tool unregistration" do
    setup do
      Registry.register(TestTool)
      Registry.register(TestToolV2)
      :ok
    end
    
    test "unregisters a specific version" do
      assert :ok = Registry.unregister(:test_tool, "1.0.0")
      assert {:error, :not_found} = Registry.get(:test_tool, "1.0.0")
      assert {:ok, _} = Registry.get(:test_tool, "2.0.0")
    end
    
    test "unregisters all versions of a tool" do
      assert :ok = Registry.unregister(:test_tool)
      assert {:error, :not_found} = Registry.get(:test_tool)
      assert [] = Registry.list_versions(:test_tool)
    end
  end
  
  describe "dynamic registration" do
    test "registers tools dynamically at runtime" do
      # Define a tool module at runtime
      defmodule RuntimeTool do
        use RubberDuck.Tool
        
        tool do
          name :runtime_tool
          description "Dynamically registered tool"
          category :dynamic
          version "1.0.0"
          
          execution do
            handler &RuntimeTool.execute/2
          end
        end
        
        def execute(_params, _context) do
          {:ok, "Runtime execution"}
        end
      end
      
      assert :ok = Registry.register(RuntimeTool)
      assert {:ok, tool} = Registry.get(:runtime_tool)
      assert tool.module == RuntimeTool
    end
  end
end
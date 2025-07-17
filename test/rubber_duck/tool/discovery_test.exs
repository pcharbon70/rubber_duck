defmodule RubberDuck.Tool.DiscoveryTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Tool.Discovery
  alias RubberDuck.Tool.Registry
  
  # Test modules for discovery
  defmodule TestTools.Calculator do
    use RubberDuck.Tool
    
    tool do
      name :calculator
      description "Basic math calculator"
      category :math
      version "1.0.0"
      tags [:math, :utility]
      
      parameter :operation do
        type :string
        required true
        description "The operation: add, subtract, multiply, divide"
      end
      
      parameter :numbers do
        type :list
        required true
        description "List of numbers to operate on"
      end
      
      execution do
        handler &TestTools.Calculator.execute/2
        timeout 5_000
      end
    end
    
    def execute(params, _context) do
      {:ok, "Math result"}
    end
  end
  
  defmodule TestTools.TextProcessor do
    use RubberDuck.Tool
    
    tool do
      name :text_processor
      description "Processes text strings"
      category :text
      version "1.0.0"
      tags [:text, :processing]
      
      parameter :text do
        type :string
        required true
        description "The text to process"
      end
      
      parameter :operation do
        type :string
        required true
        description "The operation: uppercase, lowercase, reverse"
      end
      
      execution do
        handler &TestTools.TextProcessor.execute/2
        timeout 3_000
      end
    end
    
    def execute(params, _context) do
      {:ok, "Text processed"}
    end
  end
  
  # A module that is not a tool (should be ignored)
  defmodule TestTools.NotATool do
    def some_function do
      :ok
    end
  end
  
  setup do
    # Start registry fresh for each test
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
  
  describe "module discovery" do
    test "discovers tools in a specific module" do
      tools = Discovery.discover_in_module(TestTools.Calculator)
      
      assert length(tools) == 1
      assert hd(tools) == TestTools.Calculator
    end
    
    test "discovers tools in a namespace" do
      tools = Discovery.discover_in_namespace(TestTools)
      
      assert length(tools) == 2
      assert TestTools.Calculator in tools
      assert TestTools.TextProcessor in tools
      refute TestTools.NotATool in tools
    end
    
    test "discovers tools in all loaded modules" do
      tools = Discovery.discover_all()
      
      # Should include our test tools
      assert TestTools.Calculator in tools
      assert TestTools.TextProcessor in tools
      refute TestTools.NotATool in tools
    end
    
    test "handles modules that don't exist" do
      tools = Discovery.discover_in_module(NonExistentModule)
      assert tools == []
    end
  end
  
  describe "tool loading" do
    test "loads discovered tools into registry" do
      tools = [TestTools.Calculator, TestTools.TextProcessor]
      
      assert :ok = Discovery.load_tools(tools)
      
      # Verify tools were registered
      assert {:ok, calc_tool} = Registry.get(:calculator)
      assert calc_tool.module == TestTools.Calculator
      
      assert {:ok, text_tool} = Registry.get(:text_processor)
      assert text_tool.module == TestTools.TextProcessor
    end
    
    test "skips invalid tools during loading" do
      tools = [TestTools.Calculator, TestTools.NotATool, TestTools.TextProcessor]
      
      assert :ok = Discovery.load_tools(tools)
      
      # Should load valid tools and skip invalid ones
      assert {:ok, _} = Registry.get(:calculator)
      assert {:ok, _} = Registry.get(:text_processor)
    end
    
    test "loads tools from a namespace" do
      assert :ok = Discovery.load_from_namespace(TestTools)
      
      # Should discover and load both tools
      assert {:ok, _} = Registry.get(:calculator)
      assert {:ok, _} = Registry.get(:text_processor)
    end
    
    test "loads all available tools" do
      assert :ok = Discovery.load_all()
      
      # Should find and load our test tools
      assert {:ok, _} = Registry.get(:calculator)
      assert {:ok, _} = Registry.get(:text_processor)
    end
  end
  
  describe "tool validation" do
    test "validates tool modules correctly" do
      assert Discovery.valid_tool?(TestTools.Calculator) == true
      assert Discovery.valid_tool?(TestTools.TextProcessor) == true
      assert Discovery.valid_tool?(TestTools.NotATool) == false
      assert Discovery.valid_tool?(NonExistentModule) == false
    end
  end
  
  describe "conditional loading" do
    test "loads tools with filters" do
      filter_fn = fn module ->
        metadata = RubberDuck.Tool.metadata(module)
        metadata.category == :math
      end
      
      assert :ok = Discovery.load_from_namespace(TestTools, filter: filter_fn)
      
      # Should only load math tools
      assert {:ok, _} = Registry.get(:calculator)
      assert {:error, :not_found} = Registry.get(:text_processor)
    end
    
    test "loads tools by category" do
      assert :ok = Discovery.load_from_namespace(TestTools, category: :text)
      
      # Should only load text tools
      assert {:error, :not_found} = Registry.get(:calculator)
      assert {:ok, _} = Registry.get(:text_processor)
    end
    
    test "loads tools by tag" do
      assert :ok = Discovery.load_from_namespace(TestTools, tag: :math)
      
      # Should only load tools with math tag
      assert {:ok, _} = Registry.get(:calculator)
      assert {:error, :not_found} = Registry.get(:text_processor)
    end
  end
end
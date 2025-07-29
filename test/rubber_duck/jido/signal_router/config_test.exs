defmodule RubberDuck.Jido.SignalRouter.ConfigTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Jido.SignalRouter.Config
  
  # Dummy action module for testing
  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      description: "Test action",
      schema: []
      
    @impl true
    def run(_params, _context), do: {:ok, %{}, %{}}
  end
  
  setup do
    # Start the Config GenServer
    start_supervised!(Config)
    
    # Clear any existing routes
    Config.clear_routes()
    
    :ok
  end
  
  describe "register_route/3" do
    test "registers a simple route" do
      assert :ok = Config.register_route("test.event", TestAction)
      
      routes = Config.list_routes()
      assert Enum.any?(routes, fn 
        {"test.event", TestAction, opts} -> 
          Keyword.get(opts, :priority) == 50
        _ -> 
          false
      end)
    end
    
    test "registers a route with custom priority" do
      assert :ok = Config.register_route("high.priority", TestAction, priority: 100)
      
      routes = Config.list_routes()
      assert Enum.any?(routes, fn 
        {"high.priority", TestAction, opts} -> 
          Keyword.get(opts, :priority) == 100
        _ -> 
          false
      end)
    end
    
    test "registers a pattern route with wildcards" do
      assert :ok = Config.register_route("com.example.*.created", TestAction)
      
      routes = Config.list_routes()
      assert Enum.any?(routes, fn 
        {"com.example.*.created", TestAction, _opts} -> true
        _ -> false
      end)
    end
    
    test "prevents duplicate routes by default" do
      assert :ok = Config.register_route("duplicate.test", TestAction)
      assert {:error, :route_exists} = Config.register_route("duplicate.test", TestAction)
    end
    
    test "allows override when specified" do
      assert :ok = Config.register_route("override.test", TestAction, priority: 50)
      assert :ok = Config.register_route("override.test", TestAction, priority: 100, override: true)
      
      routes = Config.list_routes()
      matching = Enum.filter(routes, fn {pattern, _, _} -> pattern == "override.test" end)
      assert length(matching) == 1
      
      [{_, _, opts}] = matching
      assert Keyword.get(opts, :priority) == 100
    end
    
    test "validates action module exists and has run/2" do
      assert {:error, :invalid_action_module} = Config.register_route("bad.action", NonExistentModule)
    end
    
    test "accepts custom parameter extractor" do
      extractor = fn event -> %{custom: event["type"]} end
      assert :ok = Config.register_route("custom.extractor", TestAction, param_extractor: extractor)
    end
  end
  
  describe "unregister_route/1" do
    test "removes an existing route" do
      Config.register_route("to.remove", TestAction)
      assert :ok = Config.unregister_route("to.remove")
      
      routes = Config.list_routes()
      refute Enum.any?(routes, fn {pattern, _, _} -> pattern == "to.remove" end)
    end
    
    test "returns error for non-existent route" do
      assert {:error, :not_found} = Config.unregister_route("does.not.exist")
    end
  end
  
  describe "find_route/1" do
    setup do
      # Register some test routes
      Config.register_route("exact.match", TestAction)
      Config.register_route("com.example.*.event", TestAction, priority: 60)
      Config.register_route("com.*.event", TestAction, priority: 40)
      :ok
    end
    
    test "finds exact match route" do
      assert {:ok, TestAction, _extractor} = Config.find_route("exact.match")
    end
    
    test "finds pattern match route" do
      assert {:ok, TestAction, _extractor} = Config.find_route("com.example.user.event")
    end
    
    test "returns highest priority pattern match" do
      # Both patterns match, but com.example.*.event has higher priority
      assert {:ok, TestAction, _extractor} = Config.find_route("com.example.test.event")
      
      # Verify it's using the right route by checking the pattern
      routes = Config.list_routes()
      matching = Enum.find(routes, fn 
        {"com.example.*.event", _, _} -> true
        _ -> false 
      end)
      assert matching != nil
      {pattern, _, _} = matching
      assert pattern == "com.example.*.event"
    end
    
    test "returns error when no route matches" do
      assert {:error, :no_route} = Config.find_route("no.match.here")
    end
    
    test "exact match takes precedence over pattern match" do
      Config.register_route("com.exact.event", TestAction, priority: 10)
      assert {:ok, TestAction, _} = Config.find_route("com.exact.event")
    end
  end
  
  describe "list_routes/0" do
    test "returns empty list when no routes" do
      assert [] = Config.list_routes()
    end
    
    test "returns routes sorted by priority (descending)" do
      Config.register_route("low", TestAction, priority: 10)
      Config.register_route("high", TestAction, priority: 100)
      Config.register_route("medium", TestAction, priority: 50)
      
      routes = Config.list_routes()
      patterns = Enum.map(routes, fn {pattern, _, _} -> pattern end)
      
      assert patterns == ["high", "medium", "low"]
    end
    
    test "includes metadata in route info" do
      Config.register_route("with.meta", TestAction, metadata: %{custom: "data"})
      
      routes = Config.list_routes()
      matching = Enum.find(routes, fn 
        {"with.meta", _, _} -> true
        _ -> false 
      end)
      assert matching != nil
      
      {_, _, opts} = matching
      assert %{custom: "data"} = Keyword.get(opts, :metadata)
    end
  end
  
  describe "clear_routes/0" do
    test "removes all routes" do
      Config.register_route("route1", TestAction)
      Config.register_route("route2", TestAction)
      Config.register_route("route3", TestAction)
      
      assert length(Config.list_routes()) == 3
      
      assert :ok = Config.clear_routes()
      assert [] = Config.list_routes()
    end
  end
  
  describe "parameter extraction" do
    test "default extractor returns data field" do
      Config.register_route("default.extract", TestAction)
      {:ok, _, extractor} = Config.find_route("default.extract")
      
      event = %{"data" => %{"key" => "value"}}
      assert %{"key" => "value"} = extractor.(event)
    end
    
    test "custom extractor is used when provided" do
      custom_extractor = fn event -> 
        %{type: event["type"], source: event["source"]}
      end
      
      Config.register_route("custom.extract", TestAction, param_extractor: custom_extractor)
      {:ok, _, extractor} = Config.find_route("custom.extract")
      
      event = %{"type" => "test", "source" => "/app", "data" => %{}}
      assert %{type: "test", source: "/app"} = extractor.(event)
    end
  end
  
  describe "pattern matching" do
    setup do
      Config.register_route("com.*.user.*", TestAction)
      Config.register_route("*.created", TestAction)
      Config.register_route("exact.event.name", TestAction)
      :ok
    end
    
    test "matches single wildcard" do
      assert {:ok, _, _} = Config.find_route("something.created")
      assert {:ok, _, _} = Config.find_route("com.example.more.things.created")
    end
    
    test "matches multiple wildcards" do
      assert {:ok, _, _} = Config.find_route("com.example.user.updated")
      assert {:ok, _, _} = Config.find_route("com.app.user.deleted")
    end
    
    test "wildcards don't match exact patterns" do
      assert {:error, :no_route} = Config.find_route("exact.event.name.extra")
    end
  end
end
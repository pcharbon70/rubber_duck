defmodule RubberDuck.Jido.Signals.SignalRouterTest do
  use ExUnit.Case
  
  alias RubberDuck.Jido.Signals.SignalRouter
  
  # Test handler modules
  defmodule TestHandler do
    def handle(signal), do: {:ok, signal}
  end
  
  defmodule AnotherHandler do
    def handle(signal), do: {:ok, signal}
  end
  
  setup do
    # Start a new router for each test
    {:ok, pid} = SignalRouter.start_link(routing_strategy: :round_robin)
    
    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)
    
    {:ok, router: pid}
  end
  
  describe "register_route/3" do
    test "registers a string pattern route" do
      assert :ok = SignalRouter.register_route("user.*", TestHandler)
      
      routes = SignalRouter.list_routes()
      assert length(routes) == 1
      assert hd(routes).pattern == "user.*"
      assert hd(routes).handler == TestHandler
    end
    
    test "registers a regex pattern route" do
      assert :ok = SignalRouter.register_route(~r/^order\..*/, TestHandler)
      
      routes = SignalRouter.list_routes()
      assert length(routes) == 1
      assert %Regex{} = hd(routes).pattern
    end
    
    test "registers route with custom options" do
      assert :ok = SignalRouter.register_route(
        "critical.*",
        TestHandler,
        category: :command,
        priority: :critical
      )
      
      routes = SignalRouter.list_routes()
      route = hd(routes)
      assert route.category == :command
      assert route.priority == :critical
    end
  end
  
  describe "unregister_route/1" do
    test "removes a registered route" do
      SignalRouter.register_route("user.*", TestHandler)
      assert length(SignalRouter.list_routes()) == 1
      
      assert :ok = SignalRouter.unregister_route("user.*")
      assert length(SignalRouter.list_routes()) == 0
    end
  end
  
  describe "route_signal/1" do
    test "routes signal to matching handler" do
      SignalRouter.register_route("user.*", TestHandler)
      
      signal = %{type: "user.created", source: "test", data: %{}}
      assert {:ok, handlers} = SignalRouter.route_signal(signal)
      assert TestHandler in handlers
    end
    
    test "routes to multiple matching handlers" do
      SignalRouter.register_route("user.*", TestHandler)
      SignalRouter.register_route("*.created", AnotherHandler)
      
      signal = %{type: "user.created", source: "test", data: %{}}
      assert {:ok, handlers} = SignalRouter.route_signal(signal)
      assert TestHandler in handlers
      assert AnotherHandler in handlers
    end
    
    test "returns error for no matching routes" do
      signal = %{type: "unknown.signal", source: "test", data: %{}}
      assert {:error, :no_matching_routes} = SignalRouter.route_signal(signal)
    end
    
    test "respects priority ordering" do
      SignalRouter.register_route("user.*", TestHandler, priority: :low)
      SignalRouter.register_route("*.created", AnotherHandler, priority: :critical)
      
      signal = %{type: "user.created", source: "test", data: %{}}
      assert {:ok, [first | _]} = SignalRouter.route_signal(signal)
      
      # Critical priority handler should be first
      assert first == AnotherHandler
    end
  end
  
  describe "get_metrics/0" do
    test "returns routing metrics" do
      SignalRouter.register_route("user.*", TestHandler)
      
      # Route some signals
      SignalRouter.route_signal(%{type: "user.created", source: "test", data: %{}})
      SignalRouter.route_signal(%{type: "user.updated", source: "test", data: %{}})
      SignalRouter.route_signal(%{type: "unknown.signal", source: "test", data: %{}})
      
      metrics = SignalRouter.get_metrics()
      assert metrics.routed_count == 2
      assert metrics.no_route_count == 1
      assert Map.has_key?(metrics.by_category, :event)
    end
  end
end
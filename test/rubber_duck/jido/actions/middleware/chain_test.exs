defmodule RubberDuck.Jido.Actions.Middleware.ChainTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido.Actions.Middleware.Chain
  
  # Test middleware
  defmodule CounterMiddleware do
    use RubberDuck.Jido.Actions.Middleware
    
    def call(_action, params, context, next) do
      # Increment counter before
      counter = Map.get(context, :counter, 0) + 1
      updated_context = Map.put(context, :counter, counter)
      
      # Call next
      result = next.(params, updated_context)
      
      # Increment counter after
      case result do
        {:ok, data, ctx} ->
          {:ok, data, Map.update(ctx, :counter, 1, &(&1 + 1))}
        error ->
          error
      end
    end
  end
  
  defmodule TransformMiddleware do
    use RubberDuck.Jido.Actions.Middleware
    
    def call(_action, params, context, next) do
      # Transform params
      transformed = Map.update(params, :value, 0, &(&1 * 2))
      
      # Call next with transformed params
      next.(transformed, context)
    end
  end
  
  defmodule ErrorMiddleware do
    use RubberDuck.Jido.Actions.Middleware
    
    def call(_action, _params, _context, _next) do
      {:error, :middleware_error}
    end
  end
  
  # Test action
  defmodule TestAction do
    use Jido.Action,
      name: "test",
      schema: [value: [type: :integer, default: 1]]
    
    def run(params, context) do
      {:ok, params.value, context}
    end
  end
  
  describe "new/0" do
    test "creates an empty chain" do
      chain = Chain.new()
      assert chain.middlewares == []
    end
  end
  
  describe "add/3" do
    test "adds middleware to the chain" do
      chain = Chain.new()
        |> Chain.add(CounterMiddleware)
        |> Chain.add(TransformMiddleware, [])
      
      assert length(chain.middlewares) == 2
      assert Chain.has_middleware?(chain, CounterMiddleware)
      assert Chain.has_middleware?(chain, TransformMiddleware)
    end
  end
  
  describe "prepend/3" do
    test "prepends middleware to the beginning" do
      chain = Chain.new()
        |> Chain.add(CounterMiddleware)
        |> Chain.prepend(TransformMiddleware)
      
      assert [{TransformMiddleware, _}, {CounterMiddleware, _}] = chain.middlewares
    end
  end
  
  describe "remove/2" do
    test "removes middleware from the chain" do
      chain = Chain.new()
        |> Chain.add(CounterMiddleware)
        |> Chain.add(TransformMiddleware)
        |> Chain.remove(CounterMiddleware)
      
      assert length(chain.middlewares) == 1
      refute Chain.has_middleware?(chain, CounterMiddleware)
      assert Chain.has_middleware?(chain, TransformMiddleware)
    end
  end
  
  describe "execute/4" do
    test "executes middleware chain in order" do
      chain = Chain.new()
        |> Chain.add(CounterMiddleware)
        |> Chain.add(TransformMiddleware)
      
      params = %{value: 5}
      context = %{counter: 0}
      
      assert {:ok, result, updated_context} = Chain.execute(chain, TestAction, params, context)
      
      # Value should be doubled by TransformMiddleware
      assert result == 10
      
      # Counter should be incremented twice by CounterMiddleware
      assert updated_context.counter == 2
    end
    
    test "stops execution if middleware returns error" do
      chain = Chain.new()
        |> Chain.add(CounterMiddleware)
        |> Chain.add(ErrorMiddleware)
        |> Chain.add(TransformMiddleware)
      
      params = %{value: 5}
      context = %{counter: 0}
      
      assert {:error, :middleware_error} = Chain.execute(chain, TestAction, params, context)
    end
    
    test "executes action directly with empty chain" do
      chain = Chain.new()
      
      params = %{value: 42}
      context = %{}
      
      assert {:ok, 42, _} = Chain.execute(chain, TestAction, params, context)
    end
  end
  
  describe "from_specs/1" do
    test "creates chain from middleware specs" do
      specs = [
        {CounterMiddleware, []},
        TransformMiddleware,
        {CounterMiddleware, [option: :value]}
      ]
      
      chain = Chain.from_specs(specs)
      
      assert length(chain.middlewares) == 3
      assert Chain.list_middlewares(chain) == [CounterMiddleware, TransformMiddleware, CounterMiddleware]
    end
  end
  
  describe "sort_by_priority/1" do
    defmodule HighPriorityMiddleware do
      use RubberDuck.Jido.Actions.Middleware, priority: 100
    end
    
    defmodule LowPriorityMiddleware do
      use RubberDuck.Jido.Actions.Middleware, priority: 10
    end
    
    test "sorts middleware by priority" do
      chain = Chain.new()
        |> Chain.add(LowPriorityMiddleware)
        |> Chain.add(HighPriorityMiddleware)
        |> Chain.add(CounterMiddleware)  # Default priority 50
        |> Chain.sort_by_priority()
      
      middlewares = Chain.list_middlewares(chain)
      assert [HighPriorityMiddleware, CounterMiddleware, LowPriorityMiddleware] = middlewares
    end
  end
end
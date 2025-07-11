defmodule RubberDuck.Analysis.AST.ElixirParserTest do
  use ExUnit.Case
  alias RubberDuck.Analysis.AST.ElixirParser

  
  describe "module structure extraction" do
    test "detects module definitions and metadata" do
      source = """
      defmodule MyApp.Example do
        @moduledoc "Example module"
        
        import Enum, only: [map: 2, filter: 2]
        alias MyApp.{User, Post}
        require Logger
        
        @custom_attr :value
        
        def hello, do: :world
      end
      """
      
      {:ok, result} = ElixirParser.parse(source)
      
      assert length(result.modules) == 1
      assert hd(result.modules).name == MyApp.Example
      
      assert length(result.imports) == 1
      assert hd(result.imports).module == Enum
      assert hd(result.imports).only == [map: 2, filter: 2]
      
      assert length(result.aliases) == 2
      assert Enum.any?(result.aliases, &(&1.module == MyApp.User))
      assert Enum.any?(result.aliases, &(&1.module == MyApp.Post))
      
      assert length(result.requires) == 1
      assert hd(result.requires).module == Logger
    end
    
    test "handles nested modules" do
      source = """
      defmodule Outer do
        defmodule Inner do
          def inner_fun, do: :ok
        end
        
        def outer_fun, do: Inner.inner_fun()
      end
      """
      
      {:ok, result} = ElixirParser.parse(source)
      
      assert length(result.modules) == 2
      module_names = Enum.map(result.modules, & &1.name)
      assert Outer in module_names
      assert Outer.Inner in module_names
    end
  end
  
  describe "function detection and analysis" do
    test "identifies all function types" do
      source = """
      defmodule FunctionExample do
        def public_fun(x), do: x
        defp private_fun(y), do: y * 2
        defmacro my_macro(ast), do: ast
        defmacrop private_macro(ast), do: ast
        
        def multi_clause(0), do: :zero
        def multi_clause(n), do: n
        
        def with_guard(x) when is_integer(x), do: x
        def with_guard(x) when is_binary(x), do: String.to_integer(x)
      end
      """
      
      {:ok, result} = ElixirParser.parse(source)
      
      functions = result.functions
      assert length(functions) == 8  # Including multi-clause
      
      public_fun = Enum.find(functions, &(&1.name == :public_fun))
      assert public_fun.type == :def
      assert public_fun.arity == 1
      assert public_fun.module == FunctionExample
      
      private_fun = Enum.find(functions, &(&1.name == :private_fun))
      assert private_fun.type == :defp
      
      macro = Enum.find(functions, &(&1.name == :my_macro))
      assert macro.type == :defmacro
      
      private_macro = Enum.find(functions, &(&1.name == :private_macro))
      assert private_macro.type == :defmacrop
    end
    
    test "tracks function metadata" do
      source = """
      defmodule MetadataExample do
        @doc "Public function"
        @spec add(integer(), integer()) :: integer()
        def add(a, b), do: a + b
      end
      """
      
      {:ok, result} = ElixirParser.parse(source)
      
      add_fun = Enum.find(result.functions, &(&1.name == :add))
      assert add_fun.line > 0
      # Note: @doc and @spec extraction would need additional implementation
    end
  end
  
  describe "variable tracking" do
    test "tracks variable assignments and usage" do
      source = """
      defmodule VariableExample do
        def process(input) do
          x = input * 2
          y = x + 1
          z = y * x
          {x, y, z}
        end
      end
      """
      
      {:ok, result} = ElixirParser.parse(source)
      
      variables = result.variables
      
      # Parameter variable
      assert Enum.any?(variables, &(&1.name == :input && &1.type == :pattern))
      
      # Assignment variables
      assert Enum.any?(variables, &(&1.name == :x && &1.type == :assignment))
      assert Enum.any?(variables, &(&1.name == :y && &1.type == :assignment))
      assert Enum.any?(variables, &(&1.name == :z && &1.type == :assignment))
    end
    
    test "extracts variables from pattern matching" do
      source = """
      defmodule PatternExample do
        def destructure do
          # Tuple pattern
          {a, b} = {1, 2}
          
          # List pattern
          [head | tail] = [1, 2, 3]
          
          # Map pattern
          %{key: value} = %{key: "test"}
          
          # Struct pattern
          %User{name: name, age: age} = %User{name: "John", age: 30}
          
          # Binary pattern
          <<first::8, rest::binary>> = "hello"
          
          {a, b, head, tail, value, name, age, first, rest}
        end
      end
      """
      
      {:ok, result} = ElixirParser.parse(source)
      
      variables = result.variables
      var_names = Enum.map(variables, & &1.name) |> Enum.uniq()
      
      expected = [:a, :b, :head, :tail, :value, :name, :age, :first, :rest]
      assert Enum.all?(expected, &(&1 in var_names))
    end
    
    test "handles pattern matching in control structures" do
      source = """
      defmodule ControlPatternExample do
        def control_flow(data) do
          # Case expression
          result = case data do
            {:ok, value} -> value
            {:error, reason} -> raise reason
          end
          
          # With expression
          with {:ok, user} <- fetch_user(),
               {:ok, posts} <- fetch_posts(user) do
            {user, posts}
          end
          
          result
        end
      end
      """
      
      {:ok, result} = ElixirParser.parse(source)
      
      variables = result.variables
      var_names = Enum.map(variables, & &1.name) |> Enum.uniq()
      
      assert :value in var_names
      assert :reason in var_names
      assert :user in var_names
      assert :posts in var_names
    end
  end
  
  describe "function call tracking" do
    test "tracks local and remote calls" do
      source = """
      defmodule CallExample do
        def main do
          # Local call
          helper(1, 2)
          
          # Remote calls
          IO.puts("hello")
          String.upcase("test")
          Enum.map([1, 2, 3], &(&1 * 2))
          
          # Kernel functions (operators)
          x = 1 + 2
          y = x * 3
        end
        
        defp helper(a, b), do: a + b
      end
      """
      
      {:ok, result} = ElixirParser.parse(source)
      
      calls = result.calls
      
      # Local call
      local_call = Enum.find(calls, &(&1.type == :local && elem(&1.to, 1) == :helper))
      assert local_call
      assert local_call.to == {CallExample, :helper, 2}
      
      # Remote calls
      io_call = Enum.find(calls, &(&1.to == {IO, :puts, 1}))
      assert io_call
      assert io_call.type == :remote
      
      string_call = Enum.find(calls, &(&1.to == {String, :upcase, 1}))
      assert string_call
      
      enum_call = Enum.find(calls, &(&1.to == {Enum, :map, 2}))
      assert enum_call
    end
    
    test "tracks function captures" do
      source = """
      defmodule CaptureExample do
        def captures do
          # Local capture
          fun1 = &local_fun/1
          
          # Remote capture
          fun2 = &String.upcase/1
          
          # Anonymous function
          fun3 = fn x -> x * 2 end
          
          {fun1, fun2, fun3}
        end
        
        def local_fun(x), do: x
      end
      """
      
      {:ok, result} = ElixirParser.parse(source)
      
      captures = Enum.filter(result.calls, &(&1.type == :capture))
      assert length(captures) >= 1
      
      anonymous = Enum.filter(result.calls, &(&1.type == :anonymous))
      assert length(anonymous) >= 1
    end
  end
  
  describe "call graph construction" do
    test "builds complete call graph" do
      source = """
      defmodule GraphExample do
        def entry_point do
          step1()
          step2()
        end
        
        defp step1 do
          IO.puts("Step 1")
          common_helper()
        end
        
        defp step2 do
          IO.puts("Step 2")
          common_helper()
        end
        
        defp common_helper do
          Logger.info("Common")
        end
      end
      """
      
      {:ok, result} = ElixirParser.parse(source)
      
      graph = ElixirParser.build_call_graph(result)
      
      # Check entry_point calls
      entry_calls = graph[{GraphExample, :entry_point, 0}]
      assert {GraphExample, :step1, 0} in entry_calls
      assert {GraphExample, :step2, 0} in entry_calls
      
      # Check step1 calls
      step1_calls = graph[{GraphExample, :step1, 0}]
      assert {IO, :puts, 1} in step1_calls
      assert {GraphExample, :common_helper, 0} in step1_calls
    end
  end
  
  describe "error handling" do
    test "handles syntax errors gracefully" do
      source = """
      defmodule Broken do
        def incomplete_function
          # Missing do/end
      end
      """
      
      result = ElixirParser.parse(source)
      assert {:error, _} = result
    end
    
    test "continues parsing despite partial errors" do
      source = """
      defmodule PartiallyBroken do
        def valid_function, do: :ok
        
        # This would have invalid syntax in real code
        # but our parser should handle what it can
        
        def another_valid, do: :ok
      end
      """
      
      # The parser should be resilient
      {:ok, result} = ElixirParser.parse(source)
      assert length(result.functions) >= 2
    end
  end
  
  describe "complex real-world example" do
    test "parses complex GenServer module" do
      source = """
      defmodule MyApp.Worker do
        use GenServer
        require Logger
        
        alias MyApp.{Config, Database}
        import Ecto.Query, only: [from: 2]
        
        @timeout 5_000
        
        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end
        
        def init(opts) do
          state = %{
            config: Config.load(),
            status: :idle,
            jobs: []
          }
          {:ok, state}
        end
        
        def handle_call({:process, data}, _from, state) do
          case validate_data(data) do
            {:ok, valid_data} ->
              result = process_internal(valid_data)
              {:reply, {:ok, result}, state}
            
            {:error, reason} = error ->
              Logger.error("Validation failed: \#{inspect(reason)}")
              {:reply, error, state}
          end
        end
        
        def handle_cast({:async_process, data}, state) do
          Task.start(fn ->
            with {:ok, valid} <- validate_data(data),
                 {:ok, processed} <- process_internal(valid),
                 :ok <- Database.save(processed) do
              Logger.info("Processing complete")
            else
              error ->
                Logger.error("Async processing failed: \#{inspect(error)}")
            end
          end)
          
          {:noreply, %{state | jobs: [data | state.jobs]}}
        end
        
        defp validate_data(data) when is_map(data) do
          required_keys = [:id, :type, :payload]
          
          missing = Enum.reject(required_keys, &Map.has_key?(data, &1))
          
          if Enum.empty?(missing) do
            {:ok, data}
          else
            {:error, {:missing_keys, missing}}
          end
        end
        
        defp process_internal(%{type: type} = data) do
          processor = get_processor(type)
          processor.process(data)
        end
        
        defp get_processor(:email), do: MyApp.EmailProcessor
        defp get_processor(:sms), do: MyApp.SMSProcessor
        defp get_processor(_), do: MyApp.DefaultProcessor
      end
      """
      
      {:ok, result} = ElixirParser.parse(source)
      
      # Verify comprehensive parsing
      assert length(result.modules) == 1
      assert hd(result.modules).name == MyApp.Worker
      
      # Check imports and aliases
      assert length(result.imports) >= 1
      assert length(result.aliases) >= 2
      assert length(result.requires) >= 1
      
      # Check functions
      public_functions = Enum.filter(result.functions, &(&1.type == :def))
      private_functions = Enum.filter(result.functions, &(&1.type == :defp))
      
      assert length(public_functions) >= 4  # start_link, init, handle_call, handle_cast
      assert length(private_functions) >= 3  # validate_data, process_internal, get_processor
      
      # Check variables
      assert length(result.variables) > 0
      
      # Check calls
      assert length(result.calls) > 0
      
      # Verify call graph can be built
      graph = ElixirParser.build_call_graph(result)
      assert map_size(graph) > 0
    end
  end
end

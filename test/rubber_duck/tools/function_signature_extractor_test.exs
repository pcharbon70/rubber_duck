defmodule RubberDuck.Tools.FunctionSignatureExtractorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.FunctionSignatureExtractor
  
  describe "tool definition" do
    test "has correct metadata" do
      assert FunctionSignatureExtractor.name() == :function_signature_extractor
      
      metadata = FunctionSignatureExtractor.metadata()
      assert metadata.name == :function_signature_extractor
      assert metadata.description == "Extracts function names, arities, and documentation from code"
      assert metadata.category == :analysis
      assert metadata.version == "1.0.0"
      assert :analysis in metadata.tags
      assert :documentation in metadata.tags
    end
    
    test "has required parameters" do
      params = FunctionSignatureExtractor.parameters()
      
      code_param = Enum.find(params, &(&1.name == :code))
      assert code_param.required == true
      assert code_param.type == :string
      
      include_private_param = Enum.find(params, &(&1.name == :include_private))
      assert include_private_param.default == false
      
      group_by_param = Enum.find(params, &(&1.name == :group_by))
      assert group_by_param.default == "module"
    end
    
    test "supports different grouping options" do
      params = FunctionSignatureExtractor.parameters()
      group_by_param = Enum.find(params, &(&1.name == :group_by))
      
      allowed_groups = group_by_param.constraints[:enum]
      assert "module" in allowed_groups
      assert "arity" in allowed_groups
      assert "visibility" in allowed_groups
      assert "type" in allowed_groups
    end
  end
  
  describe "function extraction" do
    test "extracts public functions" do
      code = """
      defmodule MyModule do
        def public_function(arg1, arg2) do
          arg1 + arg2
        end
        
        def another_function do
          :ok
        end
      end
      """
      
      params = %{
        code: code,
        include_private: false,
        include_docs: false,
        include_specs: false,
        include_guards: false,
        include_examples: false,
        group_by: "none",
        filter_pattern: "",
        sort_by: "name"
      }
      
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      
      functions = result.functions["all"]
      assert length(functions) == 2
      
      public_func = Enum.find(functions, &(&1.name == :public_function))
      assert public_func.arity == 2
      assert public_func.visibility == :public
      assert public_func.signature == "public_function/2"
      
      another_func = Enum.find(functions, &(&1.name == :another_function))
      assert another_func.arity == 0
      assert another_func.visibility == :public
    end
    
    test "includes private functions when requested" do
      code = """
      defmodule MyModule do
        def public_function do
          private_helper()
        end
        
        defp private_helper do
          :helper_result
        end
      end
      """
      
      params = %{
        code: code,
        include_private: true,
        include_docs: false,
        include_specs: false,
        include_guards: false,
        include_examples: false,
        group_by: "visibility",
        filter_pattern: "",
        sort_by: "name"
      }
      
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      
      assert Map.has_key?(result.functions, :public)
      assert Map.has_key?(result.functions, :private)
      
      public_functions = result.functions[:public]
      private_functions = result.functions[:private]
      
      assert length(public_functions) == 1
      assert length(private_functions) == 1
      
      private_func = hd(private_functions)
      assert private_func.name == :private_helper
      assert private_func.visibility == :private
    end
    
    test "excludes private functions by default" do
      code = """
      defmodule MyModule do
        def public_function, do: :ok
        defp private_function, do: :private
      end
      """
      
      params = %{
        code: code,
        include_private: false,
        include_docs: false,
        include_specs: false,
        include_guards: false,
        include_examples: false,
        group_by: "none",
        filter_pattern: "",
        sort_by: "name"
      }
      
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      
      functions = result.functions["all"]
      assert length(functions) == 1
      assert hd(functions).name == :public_function
    end
  end
  
  describe "function arguments" do
    test "extracts argument information" do
      code = """
      defmodule MyModule do
        def function_with_args(first, second, third) do
          {first, second, third}
        end
        
        def function_with_defaults(required, optional \\\\ :default) do
          {required, optional}
        end
      end
      """
      
      params = %{
        code: code,
        include_private: false,
        include_docs: false,
        include_specs: false,
        include_guards: false,
        include_examples: false,
        group_by: "none",
        filter_pattern: "",
        sort_by: "name"
      }
      
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      
      functions = result.functions["all"]
      
      args_func = Enum.find(functions, &(&1.name == :function_with_args))
      assert length(args_func.arguments) == 3
      assert Enum.at(args_func.arguments, 0).name == :first
      assert Enum.at(args_func.arguments, 1).name == :second
      
      defaults_func = Enum.find(functions, &(&1.name == :function_with_defaults))
      assert length(defaults_func.arguments) == 2
      required_arg = Enum.at(defaults_func.arguments, 0)
      optional_arg = Enum.at(defaults_func.arguments, 1)
      
      assert required_arg.name == :required
      assert required_arg.default == nil
      assert optional_arg.name == :optional
      assert optional_arg.default == ":default"
    end
  end
  
  describe "guards extraction" do
    test "extracts guard information when enabled" do
      code = """
      defmodule MyModule do
        def guarded_function(x) when is_integer(x) and x > 0 do
          x * 2
        end
        
        def simple_guard(value) when is_atom(value) do
          value
        end
      end
      """
      
      params = %{
        code: code,
        include_private: false,
        include_docs: false,
        include_specs: false,
        include_guards: true,
        include_examples: false,
        group_by: "none",
        filter_pattern: "",
        sort_by: "name"
      }
      
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      
      functions = result.functions["all"]
      
      guarded_func = Enum.find(functions, &(&1.name == :guarded_function))
      simple_guard_func = Enum.find(functions, &(&1.name == :simple_guard))
      
      assert guarded_func.guard != nil
      assert simple_guard_func.guard != nil
      assert result.statistics.functions_with_guards == 2
    end
  end
  
  describe "pattern filtering" do
    test "filters functions by regex pattern" do
      code = """
      defmodule MyModule do
        def get_user(id), do: {:ok, id}
        def get_post(id), do: {:ok, id}
        def create_user(data), do: {:ok, data}
        def delete_post(id), do: :ok
      end
      """
      
      params = %{
        code: code,
        include_private: false,
        include_docs: false,
        include_specs: false,
        include_guards: false,
        include_examples: false,
        group_by: "none",
        filter_pattern: "^get_",
        sort_by: "name"
      }
      
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      
      functions = result.functions["all"]
      assert length(functions) == 2
      
      function_names = Enum.map(functions, & &1.name)
      assert :get_user in function_names
      assert :get_post in function_names
      refute :create_user in function_names
    end
  end
  
  describe "grouping" do
    test "groups by arity" do
      code = """
      defmodule MyModule do
        def zero_arity, do: :ok
        def one_arity(x), do: x
        def two_arity(x, y), do: {x, y}
        def another_one_arity(z), do: z
      end
      """
      
      params = %{
        code: code,
        include_private: false,
        include_docs: false,
        include_specs: false,
        include_guards: false,
        include_examples: false,
        group_by: "arity",
        filter_pattern: "",
        sort_by: "name"
      }
      
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      
      assert Map.has_key?(result.functions, 0)
      assert Map.has_key?(result.functions, 1)
      assert Map.has_key?(result.functions, 2)
      
      assert length(result.functions[0]) == 1
      assert length(result.functions[1]) == 2
      assert length(result.functions[2]) == 1
    end
    
    test "groups by function type/category" do
      code = """
      defmodule MyModule do
        def new(), do: %{}
        def get(key), do: {:ok, key}
        def put(data, key, value), do: Map.put(data, key, value)
        def valid?(data), do: is_map(data)
        def create!(data), do: data
      end
      """
      
      params = %{
        code: code,
        include_private: false,
        include_docs: false,
        include_specs: false,
        include_guards: false,
        include_examples: false,
        group_by: "type",
        filter_pattern: "",
        sort_by: "name"
      }
      
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      
      # Should have different categories based on function naming patterns
      assert Map.has_key?(result.functions, :constructor)  # new
      assert Map.has_key?(result.functions, :getter)       # get
      assert Map.has_key?(result.functions, :setter)       # put
      assert Map.has_key?(result.functions, :predicate)    # valid?
      assert Map.has_key?(result.functions, :bang)         # create!
    end
  end
  
  describe "sorting" do
    test "sorts by function name" do
      code = """
      defmodule MyModule do
        def zebra, do: :z
        def alpha, do: :a
        def beta, do: :b
      end
      """
      
      params = %{
        code: code,
        include_private: false,
        include_docs: false,
        include_specs: false,
        include_guards: false,
        include_examples: false,
        group_by: "none",
        filter_pattern: "",
        sort_by: "name"
      }
      
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      
      functions = result.functions["all"]
      names = Enum.map(functions, & &1.name)
      assert names == [:alpha, :beta, :zebra]
    end
    
    test "sorts by arity" do
      code = """
      defmodule MyModule do
        def three_args(a, b, c), do: {a, b, c}
        def no_args, do: :ok
        def one_arg(x), do: x
      end
      """
      
      params = %{
        code: code,
        include_private: false,
        include_docs: false,
        include_specs: false,
        include_guards: false,
        include_examples: false,
        group_by: "none",
        filter_pattern: "",
        sort_by: "arity"
      }
      
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      
      functions = result.functions["all"]
      arities = Enum.map(functions, & &1.arity)
      assert arities == [0, 1, 3]
    end
  end
  
  describe "statistics" do
    test "calculates comprehensive statistics" do
      code = """
      defmodule MyModule do
        def public_one, do: :ok
        def public_two(x), do: x
        defp private_one, do: :private
        
        def guarded(x) when is_integer(x), do: x
        def complex(a, b, c, d, e, f), do: {a, b, c, d, e, f}
      end
      """
      
      params = %{
        code: code,
        include_private: true,
        include_docs: true,
        include_specs: true,
        include_guards: true,
        include_examples: false,
        group_by: "none",
        filter_pattern: "",
        sort_by: "name"
      }
      
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      
      assert result.summary.total_functions == 5
      assert result.summary.public_functions == 4
      assert result.summary.private_functions == 1
      
      stats = result.statistics
      assert Map.has_key?(stats.arity_distribution, 0)  # public_one, private_one
      assert Map.has_key?(stats.arity_distribution, 1)  # public_two, guarded
      assert Map.has_key?(stats.arity_distribution, 6)  # complex
      
      assert stats.max_arity == 6
      assert stats.functions_with_guards == 1
    end
  end
  
  describe "error handling" do
    test "handles syntax errors gracefully" do
      code = """
      defmodule Broken do
        def incomplete_function(
      """
      
      params = %{
        code: code,
        include_private: false,
        include_docs: false,
        include_specs: false,
        include_guards: false,
        include_examples: false,
        group_by: "none",
        filter_pattern: "",
        sort_by: "name"
      }
      
      {:error, message} = FunctionSignatureExtractor.execute(params, %{})
      assert message =~ "Parse error"
    end
    
    test "handles invalid regex patterns" do
      code = "def test, do: :ok"
      
      params = %{
        code: code,
        include_private: false,
        include_docs: false,
        include_specs: false,
        include_guards: false,
        include_examples: false,
        group_by: "none",
        filter_pattern: "[invalid regex",
        sort_by: "name"
      }
      
      # Should handle gracefully and return all functions
      {:ok, result} = FunctionSignatureExtractor.execute(params, %{})
      assert length(result.functions["all"]) == 1
    end
  end
end
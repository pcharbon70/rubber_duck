defmodule RubberDuck.Tools.CodeSummarizerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.CodeSummarizer
  
  describe "tool definition" do
    test "has correct metadata" do
      assert CodeSummarizer.name() == :code_summarizer
      
      metadata = CodeSummarizer.metadata()
      assert metadata.name == :code_summarizer
      assert metadata.description == "Summarizes the responsibilities and purpose of a file or module"
      assert metadata.category == :documentation
      assert metadata.version == "1.0.0"
      assert :documentation in metadata.tags
      assert :analysis in metadata.tags
    end
    
    test "has required parameters" do
      params = CodeSummarizer.parameters()
      
      code_param = Enum.find(params, &(&1.name == :code))
      assert code_param.required == true
      assert code_param.type == :string
      
      summary_type_param = Enum.find(params, &(&1.name == :summary_type))
      assert summary_type_param.default == "comprehensive"
      
      focus_level_param = Enum.find(params, &(&1.name == :focus_level))
      assert focus_level_param.default == "module"
    end
    
    test "supports different summary types" do
      params = CodeSummarizer.parameters()
      summary_type_param = Enum.find(params, &(&1.name == :summary_type))
      
      allowed_types = summary_type_param.constraints[:enum]
      assert "brief" in allowed_types
      assert "comprehensive" in allowed_types
      assert "technical" in allowed_types
      assert "functional" in allowed_types
      assert "architectural" in allowed_types
    end
    
    test "supports different target audiences" do
      params = CodeSummarizer.parameters()
      target_audience_param = Enum.find(params, &(&1.name == :target_audience))
      
      allowed_audiences = target_audience_param.constraints[:enum]
      assert "developer" in allowed_audiences
      assert "manager" in allowed_audiences
      assert "newcomer" in allowed_audiences
      assert "maintainer" in allowed_audiences
    end
  end
  
  describe "brief summary" do
    test "generates brief summary for simple module" do
      code = """
      defmodule Calculator do
        def add(a, b), do: a + b
        def subtract(a, b), do: a - b
      end
      """
      
      params = %{
        code: code,
        summary_type: "brief",
        focus_level: "module",
        include_examples: false,
        include_dependencies: false,
        include_complexity: false,
        target_audience: "developer",
        max_length: 50
      }
      
      {:ok, result} = CodeSummarizer.execute(params, %{})
      
      assert is_binary(result.summary)
      assert result.summary =~ "Calculator"
      assert result.summary =~ "2 functions"
    end
    
    test "generates brief summary for multiple modules" do
      code = """
      defmodule Math.Calculator do
        def add(a, b), do: a + b
      end
      
      defmodule Math.Formatter do
        def format(number), do: to_string(number)
      end
      """
      
      params = %{
        code: code,
        summary_type: "brief",
        focus_level: "file",
        include_examples: false,
        include_dependencies: false,
        include_complexity: false,
        target_audience: "developer",
        max_length: 50
      }
      
      {:ok, result} = CodeSummarizer.execute(params, %{})
      
      assert result.summary =~ "2 modules"
    end
  end
  
  describe "code analysis" do
    test "analyzes module structure" do
      code = """
      defmodule UserService do
        @moduledoc "Service for user operations"
        
        def create_user(params) do
          validate_params(params)
        end
        
        defp validate_params(params) do
          # validation logic
          params
        end
      end
      """
      
      params = %{
        code: code,
        summary_type: "comprehensive",
        focus_level: "module",
        include_examples: true,
        include_dependencies: true,
        include_complexity: true,
        target_audience: "developer",
        max_length: 200
      }
      
      {:ok, result} = CodeSummarizer.execute(params, %{})
      
      assert length(result.analysis.modules) == 1
      module = hd(result.analysis.modules)
      assert module.name == UserService
      assert length(module.functions) == 2
      
      assert length(result.analysis.functions) == 2
      public_functions = Enum.filter(result.analysis.functions, &(&1.visibility == :public))
      private_functions = Enum.filter(result.analysis.functions, &(&1.visibility == :private))
      assert length(public_functions) == 1
      assert length(private_functions) == 1
    end
    
    test "identifies function purposes" do
      code = """
      defmodule DataProcessor do
        def create_record(data), do: data
        def get_record(id), do: {:ok, id}
        def update_record(id, changes), do: {id, changes}
        def delete_record(id), do: :ok
        def valid_record?(record), do: is_map(record)
        def format_output(data), do: inspect(data)
      end
      """
      
      params = %{
        code: code,
        summary_type: "functional",
        focus_level: "function",
        include_examples: false,
        include_dependencies: false,
        include_complexity: false,
        target_audience: "developer",
        max_length: 200
      }
      
      {:ok, result} = CodeSummarizer.execute(params, %{})
      
      functions = result.analysis.functions
      purposes = Enum.map(functions, & &1.purpose)
      
      assert :constructor in purposes  # create_record
      assert :getter in purposes       # get_record
      assert :setter in purposes       # update_record
      assert :destructor in purposes   # delete_record
      assert :predicate in purposes    # valid_record?
      assert :formatter in purposes    # format_output
    end
  end
  
  describe "pattern detection" do
    test "detects GenServer pattern" do
      code = """
      defmodule MyServer do
        use GenServer
        
        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end
        
        def init(state) do
          {:ok, state}
        end
        
        def handle_call(:get_state, _from, state) do
          {:reply, state, state}
        end
      end
      """
      
      params = %{
        code: code,
        summary_type: "architectural",
        focus_level: "module",
        include_examples: false,
        include_dependencies: true,
        include_complexity: false,
        target_audience: "developer",
        max_length: 200
      }
      
      {:ok, result} = CodeSummarizer.execute(params, %{})
      
      assert :genserver in result.analysis.patterns
      assert result.summary =~ "genserver"
    end
    
    test "detects struct pattern" do
      code = """
      defmodule User do
        defstruct [:name, :email, :age]
        
        def new(name, email) do
          %User{name: name, email: email, age: nil}
        end
      end
      """
      
      params = %{
        code: code,
        summary_type: "architectural",
        focus_level: "module",
        include_examples: false,
        include_dependencies: false,
        include_complexity: false,
        target_audience: "developer",
        max_length: 200
      }
      
      {:ok, result} = CodeSummarizer.execute(params, %{})
      
      assert :struct in result.analysis.patterns
    end
    
    test "detects pipeline pattern" do
      code = """
      defmodule DataPipeline do
        def process(data) do
          data
          |> validate()
          |> transform()
          |> save()
        end
        
        defp validate(data), do: data
        defp transform(data), do: data
        defp save(data), do: data
      end
      """
      
      params = %{
        code: code,
        summary_type: "architectural",
        focus_level: "module",
        include_examples: false,
        include_dependencies: false,
        include_complexity: false,
        target_audience: "developer",
        max_length: 200
      }
      
      {:ok, result} = CodeSummarizer.execute(params, %{})
      
      assert :pipeline in result.analysis.patterns
    end
  end
  
  describe "dependency analysis" do
    test "identifies imports and aliases" do
      code = """
      defmodule MyModule do
        import Ecto.Query
        alias MyApp.{User, Account}
        use Phoenix.Controller
        
        def list_users do
          User |> select([u], u.name) |> Repo.all()
        end
      end
      """
      
      params = %{
        code: code,
        summary_type: "technical",
        focus_level: "module",
        include_examples: false,
        include_dependencies: true,
        include_complexity: false,
        target_audience: "developer",
        max_length: 200
      }
      
      {:ok, result} = CodeSummarizer.execute(params, %{})
      
      deps = result.analysis.dependencies
      assert Ecto.Query in deps.imports
      assert MyApp.User in deps.aliases
      assert MyApp.Account in deps.aliases
      assert Phoenix.Controller in deps.uses
    end
  end
  
  describe "complexity analysis" do
    test "analyzes code complexity" do
      code = """
      defmodule ComplexModule do
        def complex_function(data) do
          if data.valid do
            case data.type do
              :user -> handle_user(data)
              :admin -> handle_admin(data)
              _ -> {:error, :unknown_type}
            end
          else
            {:error, :invalid_data}
          end
        end
        
        defp handle_user(data), do: {:ok, data}
        defp handle_admin(data), do: {:ok, data}
      end
      """
      
      params = %{
        code: code,
        summary_type: "technical",
        focus_level: "module",
        include_examples: false,
        include_dependencies: false,
        include_complexity: true,
        target_audience: "developer",
        max_length: 200
      }
      
      {:ok, result} = CodeSummarizer.execute(params, %{})
      
      complexity = result.analysis.complexity
      assert complexity.cyclomatic > 1
      assert is_integer(complexity.max_nesting)
    end
  end
  
  describe "different focus levels" do
    test "function-level focus provides detailed function analysis" do
      code = """
      defmodule Calculator do
        def add(a, b), do: a + b
        def multiply(a, b), do: a * b
      end
      """
      
      params = %{
        code: code,
        summary_type: "comprehensive",
        focus_level: "function",
        include_examples: false,
        include_dependencies: false,
        include_complexity: false,
        target_audience: "developer",
        max_length: 200
      }
      
      {:ok, result} = CodeSummarizer.execute(params, %{})
      
      function_summary = result.analysis.function_summary
      assert is_list(function_summary)
      assert length(function_summary) == 2
      
      first_func = hd(function_summary)
      assert Map.has_key?(first_func, :signature)
      assert Map.has_key?(first_func, :purpose)
      assert Map.has_key?(first_func, :complexity)
    end
  end
  
  describe "metrics calculation" do
    test "calculates code metrics" do
      code = """
      defmodule TestModule do
        # This is a comment
        
        def function_one do
          :ok
        end
        
        # Another comment
        def function_two, do: :ok
      end
      """
      
      params = %{
        code: code,
        summary_type: "technical",
        focus_level: "file",
        include_examples: false,
        include_dependencies: false,
        include_complexity: false,
        target_audience: "developer",
        max_length: 200
      }
      
      {:ok, result} = CodeSummarizer.execute(params, %{})
      
      metrics = result.metadata.code_metrics
      assert metrics.lines_of_code > 0
      assert metrics.comment_lines == 2
      assert metrics.blank_lines >= 1
      assert metrics.code_lines > 0
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
        summary_type: "brief",
        focus_level: "module",
        include_examples: false,
        include_dependencies: false,
        include_complexity: false,
        target_audience: "developer",
        max_length: 100
      }
      
      {:error, message} = CodeSummarizer.execute(params, %{})
      assert message =~ "Parse error"
    end
  end
end
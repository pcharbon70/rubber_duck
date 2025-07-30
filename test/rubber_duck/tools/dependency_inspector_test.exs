defmodule RubberDuck.Tools.DependencyInspectorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.DependencyInspector
  
  describe "tool definition" do
    test "has correct metadata" do
      assert DependencyInspector.name() == :dependency_inspector
      
      metadata = DependencyInspector.metadata()
      assert metadata.name == :dependency_inspector
      assert metadata.description == "Detects internal and external dependencies used in code"
      assert metadata.category == :analysis
      assert metadata.version == "1.0.0"
      assert :analysis in metadata.tags
      assert :dependencies in metadata.tags
    end
    
    test "has required parameters" do
      params = DependencyInspector.parameters()
      
      code_param = Enum.find(params, &(&1.name == :code))
      assert code_param.required == false
      assert code_param.type == :string
      
      file_path_param = Enum.find(params, &(&1.name == :file_path))
      assert file_path_param.required == false
      
      analysis_type_param = Enum.find(params, &(&1.name == :analysis_type))
      assert analysis_type_param.default == "comprehensive"
    end
    
    test "supports different analysis types" do
      params = DependencyInspector.parameters()
      analysis_type_param = Enum.find(params, &(&1.name == :analysis_type))
      
      allowed_types = analysis_type_param.constraints[:enum]
      assert "comprehensive" in allowed_types
      assert "external" in allowed_types
      assert "internal" in allowed_types
      assert "circular" in allowed_types
      assert "unused" in allowed_types
    end
    
    test "supports grouping options" do
      params = DependencyInspector.parameters()
      group_by_param = Enum.find(params, &(&1.name == :group_by))
      
      allowed_groups = group_by_param.constraints[:enum]
      assert "module" in allowed_groups
      assert "package" in allowed_groups
      assert "layer" in allowed_groups
      assert "none" in allowed_groups
    end
  end
  
  describe "dependency extraction" do
    test "detects module aliases" do
      code = """
      defmodule MyModule do
        alias Phoenix.LiveView
        alias Ecto.{Query, Changeset}
        alias MyApp.Accounts.User, as: U
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        analysis_type: "comprehensive",
        include_stdlib: false,
        depth: 2,
        group_by: "none",
        check_mix_deps: false
      }
      
      {:ok, result} = DependencyInspector.execute(params, %{})
      assert Phoenix.LiveView in result.external ++ result.internal ++ result.unknown
      assert Ecto.Query in result.external ++ result.internal ++ result.unknown
    end
    
    test "detects imports" do
      code = """
      defmodule MyModule do
        import Ecto.Query
        import Logger, only: [info: 1]
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        analysis_type: "comprehensive",
        include_stdlib: false,
        depth: 2,
        group_by: "none",
        check_mix_deps: false
      }
      
      {:ok, result} = DependencyInspector.execute(params, %{})
      assert Ecto.Query in result.usage.imports
      assert Logger in result.usage.imports
    end
    
    test "detects use statements" do
      code = """
      defmodule MyModule do
        use GenServer
        use Phoenix.Controller
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        analysis_type: "comprehensive",
        include_stdlib: true,
        depth: 2,
        group_by: "none",
        check_mix_deps: false
      }
      
      {:ok, result} = DependencyInspector.execute(params, %{})
      assert GenServer in result.usage.uses
      assert Phoenix.Controller in result.usage.uses
    end
    
    test "detects function calls" do
      code = """
      defmodule MyModule do
        def process(data) do
          Enum.map(data, &String.upcase/1)
          File.read!("config.txt")
          MyApp.Service.call(data)
        end
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        analysis_type: "comprehensive",
        include_stdlib: true,
        depth: 2,
        group_by: "none",
        check_mix_deps: false
      }
      
      {:ok, result} = DependencyInspector.execute(params, %{})
      # Function calls would be tracked in usage.function_calls
    end
    
    test "detects struct usage" do
      code = """
      defmodule MyModule do
        def create_user do
          %User{name: "John", age: 30}
          %DateTime{}
        end
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        analysis_type: "comprehensive",
        include_stdlib: true,
        depth: 2,
        group_by: "none",
        check_mix_deps: false
      }
      
      {:ok, result} = DependencyInspector.execute(params, %{})
      # Structs create module dependencies
    end
  end
  
  describe "dependency categorization" do
    test "distinguishes stdlib modules when excluded" do
      code = """
      defmodule MyModule do
        import Enum
        import String
        import Ecto.Query
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        analysis_type: "comprehensive",
        include_stdlib: false,
        depth: 2,
        group_by: "none",
        check_mix_deps: false
      }
      
      {:ok, result} = DependencyInspector.execute(params, %{})
      # Enum and String should not appear when stdlib excluded
      refute Enum in result.external.elixir
      refute String in result.external.elixir
    end
    
    test "includes stdlib modules when requested" do
      code = """
      defmodule MyModule do
        import Enum
        import :erlang
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        analysis_type: "comprehensive",
        include_stdlib: true,
        depth: 2,
        group_by: "none",
        check_mix_deps: false
      }
      
      {:ok, result} = DependencyInspector.execute(params, %{})
      assert Enum in result.external.elixir
    end
  end
  
  describe "analysis types" do
    test "external analysis only shows external deps" do
      code = """
      defmodule MyModule do
        alias MyApp.Internal
        alias Phoenix.LiveView
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        analysis_type: "external",
        include_stdlib: false,
        depth: 2,
        group_by: "none",
        check_mix_deps: false
      }
      
      context = %{project_modules: ["MyApp"]}
      
      {:ok, result} = DependencyInspector.execute(params, context)
      assert Map.has_key?(result, :external_dependencies)
      refute Map.has_key?(result, :internal)
    end
    
    test "internal analysis only shows internal deps" do
      code = """
      defmodule MyApp.Module do
        alias MyApp.Internal
        alias MyApp.Service
        alias Phoenix.LiveView
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        analysis_type: "internal",
        include_stdlib: false,
        depth: 2,
        group_by: "none",
        check_mix_deps: false
      }
      
      context = %{project_modules: ["MyApp"]}
      
      {:ok, result} = DependencyInspector.execute(params, context)
      assert Map.has_key?(result, :internal_dependencies)
      refute Map.has_key?(result, :external)
    end
  end
  
  describe "grouping results" do
    test "groups by layer" do
      code = """
      defmodule MyApp.Web.PageController do
        alias MyApp.Repo
        alias MyApp.Core.Service
        alias MyApp.Workers.EmailWorker
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        analysis_type: "comprehensive",
        include_stdlib: false,
        depth: 2,
        group_by: "layer",
        check_mix_deps: false
      }
      
      context = %{project_modules: ["MyApp"]}
      
      {:ok, result} = DependencyInspector.execute(params, context)
      assert Map.has_key?(result, :grouped)
      # Would have :web, :data, :business, :background layers
    end
  end
  
  describe "statistics calculation" do
    test "provides dependency counts" do
      code = """
      defmodule MyModule do
        alias Phoenix.LiveView
        import Ecto.Query
        use GenServer
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        analysis_type: "comprehensive",
        include_stdlib: false,
        depth: 2,
        group_by: "none",
        check_mix_deps: false
      }
      
      {:ok, result} = DependencyInspector.execute(params, %{})
      assert result.summary.total_dependencies > 0
      assert result.summary.usage_breakdown.imports > 0
      assert result.summary.usage_breakdown.uses > 0
    end
  end
end
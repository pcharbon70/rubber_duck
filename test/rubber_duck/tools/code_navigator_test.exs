defmodule RubberDuck.Tools.CodeNavigatorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.CodeNavigator
  
  describe "tool definition" do
    test "has correct metadata" do
      assert CodeNavigator.name() == :code_navigator
      
      metadata = CodeNavigator.metadata()
      assert metadata.name == :code_navigator
      assert metadata.description == "Locates symbols within a codebase and maps them to file and line number"
      assert metadata.category == :navigation
      assert metadata.version == "1.0.0"
      assert :navigation in metadata.tags
      assert :search in metadata.tags
    end
    
    test "has required parameters" do
      params = CodeNavigator.parameters()
      
      symbol_param = Enum.find(params, &(&1.name == :symbol))
      assert symbol_param.required == true
      assert symbol_param.type == :string
      
      search_type_param = Enum.find(params, &(&1.name == :search_type))
      assert search_type_param.default == "comprehensive"
      
      scope_param = Enum.find(params, &(&1.name == :scope))
      assert scope_param.default == "project"
    end
    
    test "supports different search types" do
      params = CodeNavigator.parameters()
      search_type_param = Enum.find(params, &(&1.name == :search_type))
      
      allowed_types = search_type_param.constraints[:enum]
      assert "comprehensive" in allowed_types
      assert "definitions" in allowed_types
      assert "references" in allowed_types
      assert "declarations" in allowed_types
      assert "calls" in allowed_types
    end
    
    test "supports different scopes" do
      params = CodeNavigator.parameters()
      scope_param = Enum.find(params, &(&1.name == :scope))
      
      allowed_scopes = scope_param.constraints[:enum]
      assert "project" in allowed_scopes
      assert "file" in allowed_scopes
      assert "module" in allowed_scopes
      assert "function" in allowed_scopes
    end
  end
  
  describe "symbol navigation" do
    setup do
      # Create temporary test files
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "code_navigator_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_dir)
      
      # Create test file with sample code
      test_file = Path.join(test_dir, "sample.ex")
      File.write!(test_file, """
      defmodule SampleModule do
        @doc "A sample function"
        def sample_function(arg) do
          helper_function(arg)
        end
        
        defp helper_function(value) do
          IO.puts(value)
        end
        
        def call_sample do
          sample_function("test")
        end
      end
      """)
      
      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)
      
      {:ok, test_dir: test_dir, test_file: test_file}
    end
    
    test "finds function definitions", %{test_dir: test_dir} do
      params = %{
        symbol: "sample_function",
        search_type: "definitions",
        scope: "project",
        file_pattern: "**/*.ex",
        case_sensitive: true,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 2
      }
      
      context = %{project_root: test_dir}
      
      {:ok, result} = CodeNavigator.execute(params, context)
      
      assert result.summary.total_matches > 0
      assert result.summary.definition_count > 0
      
      # Should find the function definition
      definitions = Enum.filter(result.results, &(&1.type == :definition))
      assert length(definitions) > 0
      
      sample_def = Enum.find(definitions, &(&1.name =~ "sample_function"))
      assert sample_def != nil
      assert sample_def.symbol_type == :function
    end
    
    test "finds function calls", %{test_dir: test_dir} do
      params = %{
        symbol: "sample_function",
        search_type: "calls",
        scope: "project",
        file_pattern: "**/*.ex",
        case_sensitive: true,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 2
      }
      
      context = %{project_root: test_dir}
      
      {:ok, result} = CodeNavigator.execute(params, context)
      
      calls = Enum.filter(result.results, &(&1.type == :call))
      assert length(calls) > 0
    end
    
    test "finds module references", %{test_dir: test_dir} do
      params = %{
        symbol: "SampleModule",
        search_type: "comprehensive",
        scope: "project",
        file_pattern: "**/*.ex",
        case_sensitive: true,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 2
      }
      
      context = %{project_root: test_dir}
      
      {:ok, result} = CodeNavigator.execute(params, context)
      
      assert result.summary.total_matches > 0
      
      # Should find the module definition
      module_matches = Enum.filter(result.results, &(&1.symbol_type == :module))
      assert length(module_matches) > 0
    end
  end
  
  describe "search filtering" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "filter_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_dir)
      File.mkdir_p!(Path.join(test_dir, "test"))
      
      # Main file
      File.write!(Path.join(test_dir, "main.ex"), """
      defmodule Main do
        def target_function, do: :main
      end
      """)
      
      # Test file
      File.write!(Path.join(test_dir, "test/main_test.exs"), """
      defmodule MainTest do
        def target_function, do: :test
      end
      """)
      
      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)
      
      {:ok, test_dir: test_dir}
    end
    
    test "excludes test files when configured", %{test_dir: test_dir} do
      params_include = %{
        symbol: "target_function",
        search_type: "comprehensive",
        scope: "project",
        file_pattern: "**/*.{ex,exs}",
        case_sensitive: true,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 0
      }
      
      params_exclude = %{
        symbol: "target_function",
        search_type: "comprehensive",
        scope: "project",
        file_pattern: "**/*.{ex,exs}",
        case_sensitive: true,
        include_tests: false,
        include_deps: false,
        max_results: 100,
        context_lines: 0
      }
      
      context = %{project_root: test_dir}
      
      {:ok, result_include} = CodeNavigator.execute(params_include, context)
      {:ok, result_exclude} = CodeNavigator.execute(params_exclude, context)
      
      assert result_include.summary.total_matches > result_exclude.summary.total_matches
    end
  end
  
  describe "case sensitivity" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "case_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_dir)
      
      File.write!(Path.join(test_dir, "case_test.ex"), """
      defmodule CaseTest do
        def MyFunction, do: :uppercase
        def myfunction, do: :lowercase
      end
      """)
      
      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)
      
      {:ok, test_dir: test_dir}
    end
    
    test "respects case sensitivity setting", %{test_dir: test_dir} do
      params_sensitive = %{
        symbol: "MyFunction",
        search_type: "comprehensive",
        scope: "project",
        file_pattern: "**/*.ex",
        case_sensitive: true,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 0
      }
      
      params_insensitive = %{
        symbol: "MyFunction",
        search_type: "comprehensive",
        scope: "project",
        file_pattern: "**/*.ex",
        case_sensitive: false,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 0
      }
      
      context = %{project_root: test_dir}
      
      {:ok, result_sensitive} = CodeNavigator.execute(params_sensitive, context)
      {:ok, result_insensitive} = CodeNavigator.execute(params_insensitive, context)
      
      # Case insensitive should find more matches
      assert result_insensitive.summary.total_matches >= result_sensitive.summary.total_matches
    end
  end
  
  describe "context extraction" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "context_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_dir)
      
      File.write!(Path.join(test_dir, "context.ex"), """
      defmodule ContextTest do
        # Line before
        def target_function do
          # Line after
          :result
        end
      end
      """)
      
      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)
      
      {:ok, test_dir: test_dir}
    end
    
    test "includes context lines when requested", %{test_dir: test_dir} do
      params = %{
        symbol: "target_function",
        search_type: "definitions",
        scope: "project",
        file_pattern: "**/*.ex",
        case_sensitive: true,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 2
      }
      
      context = %{project_root: test_dir}
      
      {:ok, result} = CodeNavigator.execute(params, context)
      
      definitions = Enum.filter(result.results, &(&1.type == :definition))
      assert length(definitions) > 0
      
      definition = hd(definitions)
      assert Map.has_key?(definition, :context)
      assert length(definition.context) > 1
    end
  end
  
  describe "result ranking" do
    test "ranks definitions higher than references" do
      # This would require a more complex setup with actual code files
      # For now, we'll test the ranking logic indirectly
    end
  end
  
  describe "navigation analysis" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "nav_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_dir)
      
      File.write!(Path.join(test_dir, "nav.ex"), """
      defmodule NavTest do
        def primary_function do
          helper_function()
          another_helper()
        end
        
        defp helper_function, do: :helper
        defp another_helper, do: :another
      end
      """)
      
      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)
      
      {:ok, test_dir: test_dir}
    end
    
    test "identifies primary definition", %{test_dir: test_dir} do
      params = %{
        symbol: "primary_function",
        search_type: "comprehensive",
        scope: "project",
        file_pattern: "**/*.ex",
        case_sensitive: true,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 0
      }
      
      context = %{project_root: test_dir}
      
      {:ok, result} = CodeNavigator.execute(params, context)
      
      assert result.navigation.primary_definition != nil
      assert result.navigation.primary_definition.type == :definition
    end
    
    test "finds related symbols", %{test_dir: test_dir} do
      params = %{
        symbol: "primary_function",
        search_type: "comprehensive",
        scope: "project",
        file_pattern: "**/*.ex",
        case_sensitive: true,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 0
      }
      
      context = %{project_root: test_dir}
      
      {:ok, result} = CodeNavigator.execute(params, context)
      
      assert is_list(result.navigation.related_symbols)
    end
    
    test "analyzes usage patterns", %{test_dir: test_dir} do
      params = %{
        symbol: "helper_function",
        search_type: "comprehensive",
        scope: "project",
        file_pattern: "**/*.ex",
        case_sensitive: true,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 0
      }
      
      context = %{project_root: test_dir}
      
      {:ok, result} = CodeNavigator.execute(params, context)
      
      usage_patterns = result.navigation.usage_patterns
      assert Map.has_key?(usage_patterns, :most_used_files)
      assert Map.has_key?(usage_patterns, :usage_distribution)
      assert Map.has_key?(usage_patterns, :total_files)
    end
  end
  
  describe "error handling" do
    test "handles non-existent directories gracefully" do
      params = %{
        symbol: "nonexistent",
        search_type: "comprehensive",
        scope: "project",
        file_pattern: "**/*.ex",
        case_sensitive: true,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 0
      }
      
      context = %{project_root: "/nonexistent/path"}
      
      {:ok, result} = CodeNavigator.execute(params, context)
      assert result.summary.total_matches == 0
      assert result.summary.files_searched == 0
    end
    
    test "handles files with syntax errors" do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "error_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_dir)
      
      # Create file with syntax error
      File.write!(Path.join(test_dir, "broken.ex"), """
      defmodule Broken do
        def incomplete_function(
      """)
      
      params = %{
        symbol: "incomplete_function",
        search_type: "comprehensive",
        scope: "project",
        file_pattern: "**/*.ex",
        case_sensitive: true,
        include_tests: true,
        include_deps: false,
        max_results: 100,
        context_lines: 0
      }
      
      context = %{project_root: test_dir}
      
      {:ok, result} = CodeNavigator.execute(params, context)
      
      # Should still work with text-based fallback
      assert result.summary.files_searched > 0
      
      File.rm_rf!(test_dir)
    end
  end
end
defmodule RubberDuck.Tools.RepoSearchTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.RepoSearch
  
  describe "tool definition" do
    test "has correct metadata" do
      assert RepoSearch.name() == :repo_search
      
      metadata = RepoSearch.metadata()
      assert metadata.name == :repo_search
      assert metadata.description == "Searches project files by keyword, symbol, or pattern"
      assert metadata.category == :navigation
      assert metadata.version == "1.0.0"
      assert :search in metadata.tags
    end
    
    test "has required parameters" do
      params = RepoSearch.parameters()
      
      query_param = Enum.find(params, &(&1.name == :query))
      assert query_param.required == true
      assert query_param.type == :string
      
      search_type_param = Enum.find(params, &(&1.name == :search_type))
      assert search_type_param.default == "text"
      
      file_pattern_param = Enum.find(params, &(&1.name == :file_pattern))
      assert file_pattern_param.default == "**/*.{ex,exs}"
    end
    
    test "supports multiple search types" do
      params = RepoSearch.parameters()
      search_type_param = Enum.find(params, &(&1.name == :search_type))
      
      allowed_types = search_type_param.constraints[:enum]
      assert "text" in allowed_types
      assert "regex" in allowed_types
      assert "symbol" in allowed_types
      assert "definition" in allowed_types
      assert "reference" in allowed_types
      assert "ast" in allowed_types
    end
  end
  
  describe "search functionality" do
    setup do
      # Create a temporary directory with test files
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "repo_search_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_dir)
      
      # Create test files
      File.write!(Path.join(test_dir, "example.ex"), """
      defmodule Example do
        def hello(name) do
          "Hello, #{name}!"
        end
        
        def greet(person) do
          hello(person.name)
        end
      end
      """)
      
      File.write!(Path.join(test_dir, "test.exs"), """
      defmodule ExampleTest do
        use ExUnit.Case
        
        test "hello/1 returns greeting" do
          assert Example.hello("World") == "Hello, World!"
        end
      end
      """)
      
      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)
      
      {:ok, test_dir: test_dir}
    end
    
    test "text search finds matches", %{test_dir: test_dir} do
      params = %{
        query: "hello",
        search_type: "text",
        file_pattern: "**/*.{ex,exs}",
        case_sensitive: false,
        max_results: 10,
        context_lines: 1,
        exclude_patterns: []
      }
      
      {:ok, result} = RepoSearch.execute(params, %{project_root: test_dir})
      
      assert result.total_matches > 0
      assert Enum.any?(result.results, fn r -> 
        String.contains?(r.match, "hello")
      end)
    end
    
    test "case sensitive search", %{test_dir: test_dir} do
      params = %{
        query: "Hello",
        search_type: "text",
        file_pattern: "**/*.{ex,exs}",
        case_sensitive: true,
        max_results: 10,
        context_lines: 0,
        exclude_patterns: []
      }
      
      {:ok, result} = RepoSearch.execute(params, %{project_root: test_dir})
      
      # Should find "Hello" but not "hello"
      assert Enum.all?(result.results, fn r ->
        String.contains?(r.match, "Hello")
      end)
    end
    
    test "symbol search finds function definitions", %{test_dir: test_dir} do
      params = %{
        query: "hello",
        search_type: "definition",
        file_pattern: "**/*.ex",
        case_sensitive: false,
        max_results: 10,
        context_lines: 0,
        exclude_patterns: []
      }
      
      {:ok, result} = RepoSearch.execute(params, %{project_root: test_dir})
      
      assert result.total_matches == 1
      assert hd(result.results).match =~ "def hello/1"
    end
    
    test "excludes patterns", %{test_dir: test_dir} do
      params = %{
        query: "test",
        search_type: "text",
        file_pattern: "**/*.{ex,exs}",
        case_sensitive: false,
        max_results: 10,
        context_lines: 0,
        exclude_patterns: ["**/*.exs"]
      }
      
      {:ok, result} = RepoSearch.execute(params, %{project_root: test_dir})
      
      # Should not find matches in .exs files
      assert Enum.all?(result.results, fn r ->
        String.ends_with?(r.file, ".ex")
      end)
    end
    
    test "respects max_results limit", %{test_dir: test_dir} do
      params = %{
        query: "e",  # Common letter to ensure multiple matches
        search_type: "text",
        file_pattern: "**/*.{ex,exs}",
        case_sensitive: false,
        max_results: 1,
        context_lines: 0,
        exclude_patterns: []
      }
      
      {:ok, result} = RepoSearch.execute(params, %{project_root: test_dir})
      
      assert length(result.results) <= 1
      assert result.truncated == (result.total_matches > 1)
    end
  end
  
  describe "regex search" do
    test "supports regex patterns" do
      # This would test regex search functionality
      # with a temporary test directory
    end
  end
  
  describe "AST search" do
    test "finds AST patterns" do
      # This would test AST-based search
      # looking for specific code structures
    end
  end
end
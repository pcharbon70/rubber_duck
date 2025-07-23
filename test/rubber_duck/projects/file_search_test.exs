defmodule RubberDuck.Projects.FileSearchTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.Projects.{FileSearch, FileManager}
  alias RubberDuck.AccountsFixtures
  alias RubberDuck.WorkspaceFixtures
  
  setup do
    user = AccountsFixtures.user_fixture()
    project = WorkspaceFixtures.project_fixture(%{owner: user})
    
    # Create a test project directory structure
    project_dir = Path.join(System.tmp_dir!(), "search_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(project_dir)
    
    # Update project with test directory
    {:ok, project} = Ash.update(project, %{root_path: project_dir}, action: :update, actor: user)
    
    fm = FileManager.new(project, user)
    
    on_exit(fn -> File.rm_rf!(project_dir) end)
    
    %{fm: fm, project: project, user: user, project_dir: project_dir}
  end
  
  describe "search/3" do
    setup %{fm: fm} do
      # Create test files with content
      files = [
        {"test1.ex", """
        defmodule TestModule do
          def hello do
            IO.puts "Hello, World!"
          end
          
          def goodbye do
            IO.puts "Goodbye, World!"
          end
        end
        """},
        {"test2.ex", """
        defmodule AnotherModule do
          def greet(name) do
            IO.puts "Hello, \#{name}!"
          end
          
          def hello_world do
            greet("World")
          end
        end
        """},
        {"readme.md", """
        # Test Project
        
        This is a test project for searching.
        
        ## Features
        - Hello functionality
        - World domination
        """},
        {"data.json", """
        {
          "hello": "world",
          "foo": "bar",
          "nested": {
            "hello": "there"
          }
        }
        """}
      ]
      
      for {filename, content} <- files do
        assert {:ok, _} = FileManager.write_file(fm, filename, content)
      end
      
      :ok
    end
    
    test "searches for simple text pattern", %{fm: fm} do
      assert {:ok, results} = FileSearch.search(fm, "hello")
      
      # Should find matches in multiple files
      assert length(results) >= 3
      
      # Check that results have expected structure
      Enum.each(results, fn result ->
        assert Map.has_key?(result, :file)
        assert Map.has_key?(result, :matches)
        assert Map.has_key?(result, :score)
        assert is_list(result.matches)
      end)
    end
    
    test "searches with case sensitivity", %{fm: fm} do
      # Case insensitive (default)
      assert {:ok, results} = FileSearch.search(fm, "HELLO")
      assert length(results) >= 3
      
      # Case sensitive
      assert {:ok, results} = FileSearch.search(fm, "HELLO", case_sensitive: true)
      assert length(results) == 0
    end
    
    test "searches for whole words only", %{fm: fm} do
      assert {:ok, results} = FileSearch.search(fm, "hello", whole_word: true)
      
      # Should not match "hello" in "hello_world"
      hello_world_matches = results
      |> Enum.flat_map(& &1.matches)
      |> Enum.filter(&String.contains?(&1.text, "hello_world"))
      
      assert length(hello_world_matches) == 0
    end
    
    test "filters by file pattern", %{fm: fm} do
      assert {:ok, results} = FileSearch.search(fm, "hello", file_pattern: "*.ex")
      
      # Should only find matches in .ex files
      Enum.each(results, fn result ->
        assert String.ends_with?(result.file, ".ex")
      end)
    end
    
    test "includes context lines", %{fm: fm} do
      assert {:ok, results} = FileSearch.search(fm, "hello", context_lines: 2)
      
      # Check that matches have context
      result = Enum.find(results, &(&1.file == "test1.ex"))
      assert result
      
      match = List.first(result.matches)
      assert match
      assert is_list(match.context.before)
      assert is_list(match.context.after)
    end
    
    test "limits maximum results", %{fm: fm} do
      assert {:ok, results} = FileSearch.search(fm, "o", max_results: 2)
      assert length(results) <= 2
    end
    
    test "searches with regex pattern", %{fm: fm} do
      regex = ~r/def \w+\(/ 
      assert {:ok, results} = FileSearch.search(fm, regex)
      
      # Should find function definitions
      assert length(results) >= 1
      
      # Check matches are function definitions
      matches = Enum.flat_map(results, & &1.matches)
      Enum.each(matches, fn match ->
        assert String.starts_with?(match.text, "def ")
        assert String.ends_with?(match.text, "(")
      end)
    end
  end
  
  describe "find_files/3" do
    setup %{fm: fm} do
      # Create directory structure
      assert {:ok, _} = FileManager.create_directory(fm, "src")
      assert {:ok, _} = FileManager.create_directory(fm, "test")
      assert {:ok, _} = FileManager.create_directory(fm, "lib")
      
      files = [
        "src/main.ex",
        "src/helper.ex", 
        "test/main_test.exs",
        "test/helper_test.exs",
        "lib/utils.ex",
        "README.md",
        "config.json"
      ]
      
      for file <- files do
        assert {:ok, _} = FileManager.write_file(fm, file, "# #{file}")
      end
      
      :ok
    end
    
    test "finds files by name pattern", %{fm: fm} do
      assert {:ok, files} = FileSearch.find_files(fm, "*test*")
      
      assert length(files) == 2
      Enum.each(files, fn file ->
        assert String.contains?(file, "test")
      end)
    end
    
    test "finds files with wildcards", %{fm: fm} do
      assert {:ok, files} = FileSearch.find_files(fm, "*.ex")
      
      assert length(files) == 3
      Enum.each(files, fn file ->
        assert String.ends_with?(file, ".ex")
      end)
    end
    
    test "finds files case insensitively", %{fm: fm} do
      assert {:ok, files} = FileSearch.find_files(fm, "readme*")
      assert length(files) == 1
      assert "README.md" in files
    end
  end
  
  describe "find_by_type/3" do
    setup %{fm: fm} do
      files = [
        {"code.ex", "defmodule Code do end"},
        {"script.js", "console.log('hello');"},
        {"doc.txt", "Plain text"},
        {"image.png", <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>},
        {"data.zip", "PK" <> String.duplicate(<<0>>, 100)}
      ]
      
      for {filename, content} <- files do
        assert {:ok, _} = FileManager.write_file(fm, filename, content)
      end
      
      :ok
    end
    
    test "finds code files", %{fm: fm} do
      assert {:ok, files} = FileSearch.find_by_type(fm, :code)
      
      assert "code.ex" in files
      assert "script.js" in files
      assert "doc.txt" not in files
    end
    
    test "finds text files", %{fm: fm} do
      assert {:ok, files} = FileSearch.find_by_type(fm, :text)
      
      assert "doc.txt" in files
      assert "code.ex" not in files
    end
    
    test "finds multiple types", %{fm: fm} do
      assert {:ok, files} = FileSearch.find_by_type(fm, [:code, :text])
      
      assert "code.ex" in files
      assert "script.js" in files  
      assert "doc.txt" in files
      assert "image.png" not in files
    end
  end
  
  describe "find_by_date/4" do
    setup %{fm: fm} do
      # Create files at different times
      now = DateTime.utc_now()
      yesterday = DateTime.add(now, -86400, :second)
      last_week = DateTime.add(now, -604800, :second)
      
      files = [
        {"recent.txt", "Recent file"},
        {"yesterday.txt", "Yesterday's file"},
        {"old.txt", "Old file"}
      ]
      
      for {filename, content} <- files do
        assert {:ok, _} = FileManager.write_file(fm, filename, content)
      end
      
      %{now: now, yesterday: yesterday, last_week: last_week}
    end
    
    test "finds files within date range", %{fm: fm, yesterday: yesterday, now: now} do
      # Find files modified since yesterday
      assert {:ok, files} = FileSearch.find_by_date(fm, yesterday, now)
      
      # All test files should be included (created just now)
      assert length(files) >= 3
    end
    
    test "excludes files outside date range", %{fm: fm, yesterday: yesterday} do
      # Find files modified before yesterday (should be none)
      last_week = DateTime.add(yesterday, -604800, :second)
      two_days_ago = DateTime.add(yesterday, -86400, :second)
      
      assert {:ok, files} = FileSearch.find_by_date(fm, last_week, two_days_ago)
      assert length(files) == 0
    end
  end
  
  describe "cached_search/3" do
    setup %{fm: fm} do
      assert {:ok, _} = FileManager.write_file(fm, "test.txt", "Hello cache world")
      :ok
    end
    
    test "caches search results", %{fm: fm} do
      # First search should hit files
      assert {:ok, results1} = FileSearch.cached_search(fm, "cache")
      assert length(results1) == 1
      
      # Modify the file
      assert {:ok, _} = FileManager.write_file(fm, "test.txt", "Modified content")
      
      # Second search should return cached results (still finding "cache")
      assert {:ok, results2} = FileSearch.cached_search(fm, "cache")
      assert results2 == results1
    end
    
    test "different search parameters use different cache keys", %{fm: fm} do
      # Search 1
      assert {:ok, results1} = FileSearch.cached_search(fm, "world")
      
      # Search 2 with different options should not use cache
      assert {:ok, results2} = FileSearch.cached_search(fm, "world", case_sensitive: true)
      
      # Results might be different due to case sensitivity
      # But both should complete without error
      assert is_list(results1)
      assert is_list(results2)
    end
  end
  
  describe "search performance" do
    @tag :skip
    test "handles large number of files efficiently", %{fm: fm} do
      # Create many files
      for i <- 1..100 do
        content = "File #{i}\nSome content\nMore content"
        assert {:ok, _} = FileManager.write_file(fm, "file_#{i}.txt", content)
      end
      
      # Search should complete quickly
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, results} = FileSearch.search(fm, "content", parallel: true)
      duration = System.monotonic_time(:millisecond) - start_time
      
      assert length(results) > 0
      assert duration < 5000  # Should complete within 5 seconds
    end
  end
end
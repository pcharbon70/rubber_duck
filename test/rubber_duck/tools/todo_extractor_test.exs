defmodule RubberDuck.Tools.TodoExtractorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.TodoExtractor
  
  describe "tool definition" do
    test "has correct metadata" do
      assert TodoExtractor.name() == :todo_extractor
      
      metadata = TodoExtractor.metadata()
      assert metadata.name == :todo_extractor
      assert metadata.description == "Scans code for TODO, FIXME, and other deferred work comments"
      assert metadata.category == :maintenance
      assert metadata.version == "1.0.0"
      assert :maintenance in metadata.tags
      assert :debt in metadata.tags
    end
    
    test "has required parameters" do
      params = TodoExtractor.parameters()
      
      code_param = Enum.find(params, &(&1.name == :code))
      assert code_param.required == false
      assert code_param.type == :string
      
      patterns_param = Enum.find(params, &(&1.name == :patterns))
      assert "TODO" in patterns_param.default
      assert "FIXME" in patterns_param.default
      
      group_by_param = Enum.find(params, &(&1.name == :group_by))
      assert group_by_param.default == "type"
    end
    
    test "supports different grouping options" do
      params = TodoExtractor.parameters()
      group_by_param = Enum.find(params, &(&1.name == :group_by))
      
      allowed_groups = group_by_param.constraints[:enum]
      assert "type" in allowed_groups
      assert "file" in allowed_groups
      assert "priority" in allowed_groups
      assert "author" in allowed_groups
      assert "none" in allowed_groups
    end
  end
  
  describe "TODO extraction" do
    test "extracts basic TODO comments" do
      code = """
      defmodule MyModule do
        # TODO: Implement this function
        def incomplete_function do
          # FIXME: This is broken
          :not_implemented
        end
        
        # HACK: Temporary workaround
        def workaround, do: :ok
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        patterns: ["TODO", "FIXME", "HACK"],
        include_standard: true,
        priority_keywords: ["URGENT"],
        author_extraction: false,
        group_by: "type",
        include_context: false,
        context_lines: 2
      }
      
      {:ok, result} = TodoExtractor.execute(params, %{})
      
      assert result.summary.total_count == 3
      assert Map.has_key?(result.todos, "todo")
      assert Map.has_key?(result.todos, "fixme")
      assert Map.has_key?(result.todos, "hack")
    end
    
    test "extracts TODOs with descriptions" do
      code = """
      # TODO: Refactor this to use better error handling
      # FIXME: Handle edge case when user is nil
      """
      
      params = %{
        code: code,
        file_path: "",
        patterns: [],
        include_standard: true,
        priority_keywords: [],
        author_extraction: false,
        group_by: "none",
        include_context: false,
        context_lines: 0
      }
      
      {:ok, result} = TodoExtractor.execute(params, %{})
      
      todos = result.todos["all"]
      todo_item = Enum.find(todos, &(&1.type == "todo"))
      fixme_item = Enum.find(todos, &(&1.type == "fixme"))
      
      assert todo_item.description =~ "Refactor this"
      assert fixme_item.description =~ "Handle edge case"
    end
    
    test "handles different comment styles" do
      code = """
      # TODO: Hash comment style
      // TODO: Double slash style
      /* TODO: Block comment style */
      \"TODO: String comment style\"
      """
      
      params = %{
        code: code,
        file_path: "",
        patterns: [],
        include_standard: true,
        priority_keywords: [],
        author_extraction: false,
        group_by: "none",
        include_context: false,
        context_lines: 0
      }
      
      {:ok, result} = TodoExtractor.execute(params, %{})
      
      # Should find TODOs in different comment styles
      assert result.summary.total_count >= 2  # At least hash and string styles should work
    end
  end
  
  describe "priority analysis" do
    test "identifies high priority items" do
      code = """
      # TODO URGENT: Fix this immediately
      # FIXME: This is broken
      # BUG CRITICAL: Major issue here
      # NOTE: Just a note
      """
      
      params = %{
        code: code,
        file_path: "",
        patterns: [],
        include_standard: true,
        priority_keywords: ["URGENT", "CRITICAL"],
        author_extraction: false,
        group_by: "priority",
        include_context: false,
        context_lines: 0
      }
      
      {:ok, result} = TodoExtractor.execute(params, %{})
      
      assert Map.has_key?(result.todos, :high)
      assert Map.has_key?(result.todos, :low)
      
      high_priority = result.todos[:high]
      assert length(high_priority) >= 2  # URGENT and CRITICAL items
    end
    
    test "categorizes by TODO type priority" do
      code = """
      # TODO: Regular todo
      # FIXME: Something to fix
      # BUG: A bug report
      # NOTE: Just a note
      """
      
      params = %{
        code: code,
        file_path: "",
        patterns: [],
        include_standard: true,
        priority_keywords: [],
        author_extraction: false,
        group_by: "none",
        include_context: false,
        context_lines: 0
      }
      
      {:ok, result} = TodoExtractor.execute(params, %{})
      
      todos = result.todos["all"]
      bug_item = Enum.find(todos, &(&1.type == "bug"))
      fixme_item = Enum.find(todos, &(&1.type == "fixme"))
      note_item = Enum.find(todos, &(&1.type == "note"))
      
      assert bug_item.priority == :high
      assert fixme_item.priority == :high
      assert note_item.priority == :low
    end
  end
  
  describe "author extraction" do
    test "extracts authors from comments" do
      code = """
      # TODO @john: Implement this feature
      # FIXME [alice]: Fix the bug here
      # NOTE (bob): Remember to update docs
      # HACK by charlie: Temporary solution
      """
      
      params = %{
        code: code,
        file_path: "",
        patterns: [],
        include_standard: true,
        priority_keywords: [],
        author_extraction: true,
        group_by: "author",
        include_context: false,
        context_lines: 0
      }
      
      {:ok, result} = TodoExtractor.execute(params, %{})
      
      assert Map.has_key?(result.todos, "john")
      assert Map.has_key?(result.todos, "alice")
      assert Map.has_key?(result.todos, "bob")
      assert Map.has_key?(result.todos, "charlie")
    end
  end
  
  describe "context extraction" do
    test "includes surrounding code context" do
      code = """
      defmodule Test do
        def function_one do
          # TODO: Implement this
          :not_done
        end
      end
      """
      
      params = %{
        code: code,
        file_path: "",
        patterns: [],
        include_standard: true,
        priority_keywords: [],
        author_extraction: false,
        group_by: "none",
        include_context: true,
        context_lines: 2
      }
      
      {:ok, result} = TodoExtractor.execute(params, %{})
      
      todo = hd(result.todos["all"])
      assert todo.context != nil
      assert length(todo.context) > 1
      
      # Should include the function definition line
      context_content = Enum.map(todo.context, & &1.content) |> Enum.join("\n")
      assert context_content =~ "def function_one"
    end
  end
  
  describe "complexity analysis" do
    test "analyzes TODO complexity" do
      code = """
      # TODO: Simple
      # FIXME: This is a much longer description that explains a complex issue with multiple parts and considerations
      # HACK: Medium length description with some details
      """
      
      params = %{
        code: code,
        file_path: "",
        patterns: [],
        include_standard: true,
        priority_keywords: [],
        author_extraction: false,
        group_by: "none",
        include_context: false,
        context_lines: 0
      }
      
      {:ok, result} = TodoExtractor.execute(params, %{})
      
      todos = result.todos["all"]
      simple_todo = Enum.find(todos, &(&1.description == "Simple"))
      complex_todo = Enum.find(todos, &String.contains?(&1.description, "complex issue"))
      
      assert simple_todo.complexity == :simple
      assert complex_todo.complexity == :complex
    end
  end
  
  describe "grouping" do
    test "groups by file" do
      # Would need to test with actual files or mock file system
      # For now, test with inline code
      code = """
      # TODO: First todo
      # FIXME: First fixme
      """
      
      params = %{
        code: code,
        file_path: "",
        patterns: [],
        include_standard: true,
        priority_keywords: [],
        author_extraction: false,
        group_by: "file",
        include_context: false,
        context_lines: 0
      }
      
      {:ok, result} = TodoExtractor.execute(params, %{})
      
      assert Map.has_key?(result.todos, "inline_code")
      assert length(result.todos["inline_code"]) == 2
    end
  end
  
  describe "statistics" do
    test "calculates comprehensive statistics" do
      code = """
      # TODO URGENT: High priority item
      # FIXME: Regular fix needed
      # NOTE: Simple note here
      # HACK: Complex workaround that needs significant refactoring and careful consideration of edge cases
      """
      
      params = %{
        code: code,
        file_path: "",
        patterns: [],
        include_standard: true,
        priority_keywords: ["URGENT"],
        author_extraction: false,
        group_by: "none",
        include_context: false,
        context_lines: 0
      }
      
      {:ok, result} = TodoExtractor.execute(params, %{})
      
      stats = result.statistics
      assert stats.total_todos == 4
      assert stats.has_high_priority == true
      assert Map.has_key?(stats.complexity_distribution, :simple)
      assert Map.has_key?(stats.complexity_distribution, :complex)
      assert stats.avg_description_length > 0
    end
  end
  
  describe "recommendations" do
    test "generates helpful recommendations" do
      code = """
      # TODO URGENT: Critical issue
      # FIXME IMPORTANT: Another critical issue
      # TODO: Remove this old deprecated code
      # TODO: Clean up legacy implementation
      """
      
      params = %{
        code: code,
        file_path: "",
        patterns: [],
        include_standard: true,
        priority_keywords: ["URGENT", "IMPORTANT"],
        author_extraction: false,
        group_by: "none",
        include_context: false,
        context_lines: 0
      }
      
      {:ok, result} = TodoExtractor.execute(params, %{})
      
      recommendations = result.recommendations
      assert length(recommendations) > 0
      
      # Should recommend addressing high priority items
      high_priority_rec = Enum.find(recommendations, &String.contains?(&1, "high-priority"))
      assert high_priority_rec != nil
    end
  end
end
defmodule RubberDuck.Tools.CodeComparerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.CodeComparer
  
  describe "tool definition" do
    test "has correct metadata" do
      assert CodeComparer.name() == :code_comparer
      
      metadata = CodeComparer.metadata()
      assert metadata.name == :code_comparer
      assert metadata.description == "Compares two code versions and highlights semantic differences"
      assert metadata.category == :analysis
      assert metadata.version == "1.0.0"
      assert :comparison in metadata.tags
      assert :diff in metadata.tags
    end
    
    test "has required parameters" do
      params = CodeComparer.parameters()
      
      code_a_param = Enum.find(params, &(&1.name == :code_a))
      assert code_a_param.required == true
      assert code_a_param.type == :string
      
      code_b_param = Enum.find(params, &(&1.name == :code_b))
      assert code_b_param.required == true
      assert code_b_param.type == :string
      
      comparison_type_param = Enum.find(params, &(&1.name == :comparison_type))
      assert comparison_type_param.default == "comprehensive"
    end
    
    test "supports different comparison types" do
      params = CodeComparer.parameters()
      comparison_type_param = Enum.find(params, &(&1.name == :comparison_type))
      
      allowed_types = comparison_type_param.constraints[:enum]
      assert "comprehensive" in allowed_types
      assert "semantic" in allowed_types
      assert "structural" in allowed_types
      assert "textual" in allowed_types
      assert "functional" in allowed_types
    end
    
    test "supports different output formats" do
      params = CodeComparer.parameters()
      output_format_param = Enum.find(params, &(&1.name == :output_format))
      
      allowed_formats = output_format_param.constraints[:enum]
      assert "structured" in allowed_formats
      assert "unified" in allowed_formats
      assert "side_by_side" in allowed_formats
      assert "json" in allowed_formats
    end
  end
  
  describe "textual comparison" do
    test "detects line additions" do
      code_a = """
      def hello do
        :world
      end
      """
      
      code_b = """
      def hello do
        IO.puts("Hello")
        :world
      end
      """
      
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "textual",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      assert result.summary.total_differences > 0
      additions = get_differences_by_type(result.comparison, :addition)
      assert length(additions) > 0
    end
    
    test "detects line deletions" do
      code_a = """
      def hello do
        IO.puts("Debug")
        :world
      end
      """
      
      code_b = """
      def hello do
        :world
      end
      """
      
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "textual",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      deletions = get_differences_by_type(result.comparison, :deletion)
      assert length(deletions) > 0
    end
    
    test "detects line modifications" do
      code_a = """
      def greet(name) do
        "Hello #{name}"
      end
      """
      
      code_b = """
      def greet(name) do
        "Hi #{name}!"
      end
      """
      
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "textual",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      modifications = get_differences_by_type(result.comparison, :modification)
      assert length(modifications) > 0
    end
  end
  
  describe "structural comparison" do
    test "detects function additions" do
      code_a = """
      defmodule MyModule do
        def existing_function, do: :ok
      end
      """
      
      code_b = """
      defmodule MyModule do
        def existing_function, do: :ok
        def new_function, do: :new
      end
      """
      
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "structural",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      additions = get_differences_by_type(result.comparison, :structural_addition)
      assert length(additions) > 0
    end
    
    test "detects function removals" do
      code_a = """
      defmodule MyModule do
        def function_to_remove, do: :remove_me
        def keep_function, do: :keep
      end
      """
      
      code_b = """
      defmodule MyModule do
        def keep_function, do: :keep
      end
      """
      
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "structural",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      deletions = get_differences_by_type(result.comparison, :structural_deletion)
      assert length(deletions) > 0
    end
  end
  
  describe "functional comparison" do
    test "detects function signature changes" do
      code_a = """
      defmodule MyModule do
        def process(data), do: data
      end
      """
      
      code_b = """
      defmodule MyModule do
        def process(data, options), do: {data, options}
      end
      """
      
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "functional",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      # Should detect removal of old signature and addition of new one
      assert result.summary.total_differences > 0
    end
  end
  
  describe "whitespace handling" do
    test "ignores whitespace when configured" do
      code_a = "def hello,do: :world"
      code_b = "def hello, do: :world"
      
      params_ignore = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "textual",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      params_include = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "textual",
        ignore_whitespace: false,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result_ignore} = CodeComparer.execute(params_ignore, %{})
      {:ok, result_include} = CodeComparer.execute(params_include, %{})
      
      assert result_ignore.summary.total_differences < result_include.summary.total_differences
    end
  end
  
  describe "comment handling" do
    test "ignores comments when configured" do
      code_a = """
      def hello do
        # This is a comment
        :world
      end
      """
      
      code_b = """
      def hello do
        # This is a different comment
        :world
      end
      """
      
      params_ignore = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "textual",
        ignore_whitespace: false,
        ignore_comments: true,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      params_include = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "textual",
        ignore_whitespace: false,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result_ignore} = CodeComparer.execute(params_ignore, %{})
      {:ok, result_include} = CodeComparer.execute(params_include, %{})
      
      assert result_ignore.summary.total_differences < result_include.summary.total_differences
    end
  end
  
  describe "output formats" do
    setup do
      code_a = "def hello, do: :world"
      code_b = "def greetings, do: :world"
      
      {:ok, code_a: code_a, code_b: code_b}
    end
    
    test "structured format", %{code_a: code_a, code_b: code_b} do
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "comprehensive",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      assert is_map(result.comparison)
      assert Map.has_key?(result.comparison, :critical)
      assert Map.has_key?(result.comparison, :important)
      assert Map.has_key?(result.comparison, :normal)
      assert Map.has_key?(result.comparison, :trivial)
    end
    
    test "unified diff format", %{code_a: code_a, code_b: code_b} do
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "textual",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "unified"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      assert Map.has_key?(result.comparison, :unified_diff)
      assert is_binary(result.comparison.unified_diff)
    end
    
    test "json format", %{code_a: code_a, code_b: code_b} do
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "textual",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "json"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      assert is_binary(result.comparison)
      # Should be valid JSON
      assert {:ok, _} = Jason.decode(result.comparison)
    end
  end
  
  describe "similarity scoring" do
    test "identical code has high similarity" do
      code = "def hello, do: :world"
      
      params = %{
        code_a: code,
        code_b: code,
        comparison_type: "comprehensive",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      assert result.summary.similarity_score > 0.9
      assert result.summary.total_differences == 0
    end
    
    test "completely different code has low similarity" do
      code_a = "def hello, do: :world"
      code_b = "defmodule Completely.Different do end"
      
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "comprehensive",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      assert result.summary.similarity_score < 0.5
      assert result.summary.total_differences > 0
    end
  end
  
  describe "significance assessment" do
    test "categorizes differences by significance" do
      code_a = """
      defmodule MyModule do
        # A comment
        def important_function, do: :ok
      end
      """
      
      code_b = """
      defmodule MyModule do
        # A different comment
        def important_function, do: :changed
        def new_critical_function, do: :critical
      end
      """
      
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "comprehensive",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:ok, result} = CodeComparer.execute(params, %{})
      
      # Should have differences in multiple significance categories
      assert length(result.comparison.critical ++ result.comparison.important) > 0
      assert result.summary.significant_changes > 0
    end
  end
  
  describe "error handling" do
    test "handles syntax errors gracefully" do
      code_a = "def valid, do: :ok"
      code_b = "def invalid("
      
      params = %{
        code_a: code_a,
        code_b: code_b,
        comparison_type: "comprehensive",
        ignore_whitespace: true,
        ignore_comments: false,
        context_lines: 2,
        highlight_moves: false,
        similarity_threshold: 0.8,
        output_format: "structured"
      }
      
      {:error, message} = CodeComparer.execute(params, %{})
      assert message =~ "Failed to parse code"
    end
  end
  
  # Helper function to extract differences by type
  defp get_differences_by_type(comparison, type) do
    comparison
    |> Map.values()
    |> List.flatten()
    |> Enum.filter(&(&1.type == type))
  end
end
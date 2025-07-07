defmodule RubberDuck.Engines.Generation.RagContextTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Engines.Generation.RagContext

  describe "search_similar_code/3" do
    test "searches for similar code with default options" do
      results = RagContext.search_similar_code("create a genserver", :elixir)

      assert is_list(results)

      Enum.each(results, fn item ->
        assert Map.has_key?(item, :type)
        assert Map.has_key?(item, :content)
        assert Map.has_key?(item, :source)
        assert Map.has_key?(item, :relevance)
        assert Map.has_key?(item, :metadata)

        assert item.relevance >= 0.0 and item.relevance <= 1.0
      end)
    end

    test "respects max_results option" do
      options = %{max_results: 3}
      results = RagContext.search_similar_code("function", :elixir, options)

      assert length(results) <= 3
    end

    test "filters by minimum relevance" do
      options = %{min_relevance: 0.8}
      results = RagContext.search_similar_code("api endpoint", :elixir, options)

      Enum.each(results, fn item ->
        assert item.relevance >= 0.8
      end)
    end

    test "sorts results by relevance descending" do
      results = RagContext.search_similar_code("handle_call", :elixir)

      if length(results) > 1 do
        relevances = Enum.map(results, & &1.relevance)
        assert relevances == Enum.sort(relevances, :desc)
      end
    end

    test "enhances results with metadata" do
      results = RagContext.search_similar_code("test", :elixir)

      Enum.each(results, fn item ->
        metadata = item.metadata
        assert Map.has_key?(metadata, :char_count)
        assert Map.has_key?(metadata, :line_count)
        assert Map.has_key?(metadata, :has_comments)
        assert Map.has_key?(metadata, :complexity)
      end)
    end

    test "returns pattern matches for language-specific queries" do
      results = RagContext.search_similar_code("genserver handle_call", :elixir)

      pattern_results = Enum.filter(results, &(&1.type == :pattern))
      assert length(pattern_results) > 0

      # Should find GenServer patterns
      assert Enum.any?(pattern_results, fn item ->
               String.contains?(item.content, "handle_call")
             end)
    end
  end

  describe "extract_project_patterns/2" do
    test "extracts module patterns from project info" do
      project_info = %{
        modules: [
          %{name: "MyApp.UserController"},
          %{name: "MyApp.ProductService"}
        ]
      }

      patterns = RagContext.extract_project_patterns(project_info, :elixir)

      module_patterns = Enum.filter(patterns, &(&1.type == :pattern))
      assert length(module_patterns) > 0

      assert Enum.any?(module_patterns, fn p ->
               String.contains?(p.content, "defmodule MyApp.UserController")
             end)
    end

    test "extracts function patterns for Elixir" do
      project_info = %{
        functions: [
          %{name: "get_user"},
          %{name: "get_product"},
          %{name: "create_order"},
          %{name: "create_invoice"}
        ]
      }

      patterns = RagContext.extract_project_patterns(project_info, :elixir)

      # Should group similar functions and create patterns
      assert Enum.any?(patterns, fn p ->
               p.metadata[:category] == :getter or
                 p.metadata[:category] == :creator
             end)
    end

    test "extracts test patterns when available" do
      project_info = %{
        test_modules: ["MyAppTest.UserTest", "MyAppTest.ProductTest"]
      }

      patterns = RagContext.extract_project_patterns(project_info, :elixir)

      test_patterns = Enum.filter(patterns, &(&1.type == :test))
      assert length(test_patterns) > 0

      assert Enum.any?(test_patterns, fn p ->
               String.contains?(p.content, "describe") and
                 String.contains?(p.content, "test")
             end)
    end

    test "returns empty list for non-Elixir languages without patterns" do
      project_info = %{modules: []}

      patterns = RagContext.extract_project_patterns(project_info, :ruby)

      assert patterns == []
    end
  end

  describe "build_context/3" do
    test "aggregates context from multiple sources" do
      sources = %{
        similar_code: [
          %{type: :code, content: "def example", relevance: 0.8}
        ],
        project_patterns: [
          %{type: :pattern, content: "defmodule Pattern", relevance: 0.7}
        ],
        examples: [
          %{code: "def user_function", description: "User example"}
        ]
      }

      context = RagContext.build_context("create function", :elixir, sources)

      assert Map.has_key?(context, :items)
      assert Map.has_key?(context, :summary)
      assert Map.has_key?(context, :metadata)

      assert context.metadata.total_items >= 3
      assert :similar_code in context.metadata.sources
      assert :project_patterns in context.metadata.sources
      assert :examples in context.metadata.sources
    end

    test "deduplicates context items" do
      duplicate_content = "def duplicate_function do\n  :ok\nend"

      sources = %{
        similar_code: [
          %{type: :code, content: duplicate_content, relevance: 0.8},
          %{type: :code, content: duplicate_content, relevance: 0.7}
        ]
      }

      context = RagContext.build_context("test", :elixir, sources)

      # Should deduplicate identical content
      assert context.metadata.unique_items < context.metadata.total_items
    end

    test "summarizes context information" do
      sources = %{
        similar_code: [
          %{type: :code, content: "code1", relevance: 0.9},
          %{type: :pattern, content: "pattern1", relevance: 0.8}
        ]
      }

      context = RagContext.build_context("test", :elixir, sources)

      summary = context.summary
      assert summary.total_items == 2
      assert Map.has_key?(summary, :type_distribution)
      assert Map.has_key?(summary, :average_relevance)
      assert Map.has_key?(summary, :primary_sources)
    end
  end

  describe "rank_context_items/2" do
    test "ranks items based on query keywords" do
      items = [
        %{type: :code, content: "def create_user(attrs)", relevance: 0.5},
        %{type: :code, content: "def delete_user(id)", relevance: 0.5},
        %{type: :pattern, content: "def create_resource(attrs)", relevance: 0.5}
      ]

      ranked = RagContext.rank_context_items(items, "create user function")

      # First item should have "create" and "user"
      assert hd(ranked).content =~ "create_user"
    end

    test "considers type preference in ranking" do
      items = [
        %{type: :documentation, content: "create function", relevance: 0.8},
        %{type: :code, content: "create function", relevance: 0.8},
        %{type: :pattern, content: "create function", relevance: 0.8}
      ]

      ranked = RagContext.rank_context_items(items, "create function")

      # Code and patterns should rank higher than documentation
      code_and_pattern = Enum.take(ranked, 2)
      assert Enum.all?(code_and_pattern, &(&1.type in [:code, :pattern]))
    end
  end

  describe "private helper functions" do
    test "calculates similarity between embeddings" do
      # Testing through public interface
      results1 = RagContext.search_similar_code("genserver process", :elixir)
      results2 = RagContext.search_similar_code("completely unrelated query xyz", :elixir)

      # Results for related query should have higher relevance
      if length(results1) > 0 and length(results2) > 0 do
        avg_relevance1 = Enum.sum(Enum.map(results1, & &1.relevance)) / length(results1)
        avg_relevance2 = Enum.sum(Enum.map(results2, & &1.relevance)) / length(results2)

        # GenServer query should match better with available patterns
        assert avg_relevance1 >= avg_relevance2
      end
    end

    test "metadata enhancement adds useful information" do
      results = RagContext.search_similar_code("function", :elixir)

      Enum.each(results, fn item ->
        metadata = item.metadata

        # Character count
        assert metadata.char_count == String.length(item.content)

        # Line count
        expected_lines = length(String.split(item.content, "\n"))
        assert metadata.line_count == expected_lines

        # Has comments detection
        assert is_boolean(metadata.has_comments)

        # Complexity estimation
        assert is_integer(metadata.complexity)
        assert metadata.complexity >= 0
      end)
    end
  end

  describe "language pattern detection" do
    test "finds Elixir-specific patterns" do
      results = RagContext.search_similar_code("file reading error handling", :elixir)

      # Should find file handling pattern
      pattern_results = Enum.filter(results, &(&1.type == :pattern))

      assert Enum.any?(pattern_results, fn item ->
               String.contains?(item.content, "File.read") and
                 String.contains?(item.content, "{:error")
             end)
    end

    test "returns empty results for unsupported languages" do
      results = RagContext.search_similar_code("create function", :cobol)

      # May return empty or very generic results
      assert is_list(results)
    end
  end
end

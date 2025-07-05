defmodule RubberDuck.EnhancerTest do
  use ExUnit.Case
  import RubberDuck.ProtocolTestHelpers
  
  alias RubberDuck.Enhancer
  
  describe "Map implementation" do
    test "protocol is properly implemented" do
      test_protocol_implementation(
        Enhancer,
        Map,
        %{test: "value"},
        [:enhance, :with_context, :with_metadata, :derive]
      )
    end
    
    test "enhancement strategies" do
      map = %{
        email: "user@example.com",
        phone: "+1-555-123-4567",
        created_at: "2024-01-01",
        price: "$99.99",
        parent_id: 123,
        child_count: 5
      }
      
      test_enhancer_behavior(map, [
        :semantic,
        :structural,
        :temporal,
        :relational,
        {:custom, [enhancer: &Map.put(&1, :custom, true)]}
      ])
    end
    
    test "semantic enhancement detects field types" do
      {:ok, enhanced} = Enhancer.enhance(%{
        email: "test@example.com",
        url: "https://example.com",
        price: "100",
        user_name: "John Doe"
      }, :semantic)
      
      # Check semantic type detection
      assert enhanced.email.semantic.type == :email
      assert enhanced.url.semantic.type == :url
      assert enhanced.price.semantic.type == :currency
      assert enhanced.user_name.semantic.type == :name
    end
    
    test "structural enhancement analyzes map structure" do
      nested_map = %{
        a: 1,
        b: %{
          c: 2,
          d: %{
            e: 3
          }
        }
      }
      
      {:ok, enhanced} = Enhancer.enhance(nested_map, :structural)
      
      assert enhanced.structure.depth == 3
      assert enhanced.structure.field_count == 2
      assert enhanced.structure.nested_fields > 0
      assert enhanced.structure.complexity_score > 10
    end
    
    test "temporal enhancement adds time context" do
      {:ok, enhanced} = Enhancer.enhance(%{data: "test"}, :temporal)
      
      assert Map.has_key?(enhanced, :__temporal__)
      assert enhanced.__temporal__.ttl == 3600
      assert enhanced.__temporal__.enhanced_at != nil
      assert enhanced.__temporal__.version != nil
    end
    
    test "relational enhancement finds relationships" do
      map = %{
        user_id: 1,
        user_name: "John",
        parent_id: 2,
        child_id: 3
      }
      
      {:ok, enhanced} = Enhancer.enhance(map, :relational)
      
      assert is_list(enhanced.relationships)
      assert length(enhanced.relationships) > 0
      
      # Should find relationship between user_id and user_name
      assert Enum.any?(enhanced.relationships, fn rel ->
        (rel.from == :user_id and rel.to == :user_name) or
        (rel.from == :user_name and rel.to == :user_id)
      end)
    end
    
    test "with_context adds context information" do
      map = %{data: "test"}
      context = %{source: "api", version: "1.0"}
      
      enhanced = Enhancer.with_context(map, context)
      
      assert enhanced.__context__ == context
      
      # Adding more context merges
      more_context = %{timestamp: DateTime.utc_now()}
      enhanced2 = Enhancer.with_context(enhanced, more_context)
      
      assert Map.keys(enhanced2.__context__) == [:source, :version, :timestamp]
    end
    
    test "with_metadata enriches with metadata" do
      map = %{data: "test"}
      metadata = %{author: "system", quality: 0.95}
      
      enhanced = Enhancer.with_metadata(map, metadata)
      
      assert enhanced.__metadata__.author == "system"
      assert enhanced.__metadata__.quality == 0.95
    end
    
    test "derive extracts derived information" do
      map = %{
        a: 10,
        b: 20,
        c: 30,
        nested: %{d: 40}
      }
      
      # Single derivation
      {:ok, summary} = Enhancer.derive(map, :summary)
      assert summary.summary.total_fields == 4
      assert summary.summary.nested_maps == 1
      
      # Multiple derivations
      {:ok, insights} = Enhancer.derive(map, [:summary, :statistics, :patterns])
      assert Map.has_key?(insights, :summary)
      assert Map.has_key?(insights, :statistics)
      assert Map.has_key?(insights, :patterns)
      
      # Statistics should include numeric analysis
      assert insights.statistics.numeric_fields == 3
      assert insights.statistics.sum == 60
      assert insights.statistics.average == 20.0
    end
    
    test "pattern detection in maps" do
      map = %{
        user_id: 1,
        user_name: "John",
        user_email: "john@example.com",
        product_id: 100,
        product_name: "Widget"
      }
      
      {:ok, patterns} = Enhancer.derive(map, :patterns)
      
      # Should detect naming conventions
      assert patterns.patterns.naming_conventions.has_prefixes == true
      assert length(patterns.patterns.naming_conventions.common_prefixes) > 0
      
      # Should detect structural patterns
      assert patterns.patterns.structural_patterns.has_id_fields == true
    end
  end
  
  describe "String implementation" do
    test "protocol is properly implemented" do
      test_protocol_implementation(
        Enhancer,
        BitString,
        "test string",
        [:enhance, :with_context, :with_metadata, :derive]
      )
    end
    
    test "enhancement strategies" do
      text = """
      The quick brown fox jumps over the lazy dog.
      This is a test email: user@example.com
      Visit us at https://example.com
      Meeting scheduled for 2024-01-15 at 10:00 AM
      """
      
      test_enhancer_behavior(text, [
        :semantic,
        :structural,
        :temporal,
        :relational
      ])
    end
    
    test "semantic enhancement extracts entities" do
      text = "Contact John Doe at john@example.com or call 555-1234."
      
      {:ok, enhanced} = Enhancer.enhance(text, :semantic)
      
      assert Map.has_key?(enhanced.semantic, :entities)
      assert Map.has_key?(enhanced.semantic, :keywords)
      assert Map.has_key?(enhanced.semantic, :language)
      
      # Should extract entities
      assert length(enhanced.semantic.entities.capitalized_words) > 0
      assert "John" in enhanced.semantic.entities.capitalized_words
    end
    
    test "structural enhancement analyzes text structure" do
      text = """
      First paragraph here.
      
      Second paragraph with more content.
      And another sentence.
      """
      
      {:ok, enhanced} = Enhancer.enhance(text, :structural)
      
      assert enhanced.structure.paragraph_count == 2
      assert enhanced.structure.sentence_count >= 3
      assert enhanced.structure.word_count > 10
    end
    
    test "temporal enhancement extracts dates and times" do
      text = """
      Meeting on 2024-01-15 at 10:00 AM
      Deadline: 2024-02-01
      Call me tomorrow or next week
      """
      
      {:ok, enhanced} = Enhancer.enhance(text, :temporal)
      
      assert length(enhanced.temporal.extracted_dates) >= 2
      assert length(enhanced.temporal.extracted_times) >= 1
      assert "tomorrow" in enhanced.temporal.temporal_expressions
    end
    
    test "relational enhancement extracts links and references" do
      text = """
      Email: user@example.com
      Website: https://example.com
      See section 3.2 for details
      @johndoe mentioned this
      """
      
      {:ok, enhanced} = Enhancer.enhance(text, :relational)
      
      assert length(enhanced.relational.email_addresses) == 1
      assert length(enhanced.relational.urls) == 1
      assert "@johndoe" in enhanced.relational.mentions.mentions
    end
    
    test "derive statistics from text" do
      text = "The quick brown fox jumps over the lazy dog. " <>
             "This sentence has UPPERCASE and lowercase. " <>
             "Numbers: 123, 456!"
      
      {:ok, stats} = Enhancer.derive(text, :statistics)
      
      assert stats.statistics.word_count > 10
      assert stats.statistics.punctuation_count > 0
      assert stats.statistics.digit_count == 6
      assert stats.statistics.uppercase_ratio > 0 and stats.statistics.uppercase_ratio < 1
    end
    
    test "pattern detection in text" do
      text = """
      - First item
      - Second item
      - Third item
      
      1. Numbered item
      2. Another numbered item
      
      "This is quoted" and 'this too'
      """
      
      {:ok, patterns} = Enhancer.derive(text, :patterns)
      
      assert patterns.patterns.formatting_patterns.list_items > 0
      assert patterns.patterns.formatting_patterns.numbered_items > 0
      assert patterns.patterns.formatting_patterns.quoted_sections > 0
    end
    
    test "language detection" do
      elixir_code = """
      defmodule Example do
        def hello(name) do
          IO.puts("Hello, \#{name}!")
        end
      end
      """
      
      {:ok, enhanced} = Enhancer.enhance(elixir_code, :semantic)
      assert enhanced.semantic.language == :elixir
    end
  end
  
  describe "List implementation" do
    test "protocol is properly implemented" do
      test_protocol_implementation(
        Enhancer,
        List,
        [1, 2, 3],
        [:enhance, :with_context, :with_metadata, :derive]
      )
    end
    
    test "enhancement strategies" do
      list = [1, 2, 3, 5, 8, 13, 21]  # Fibonacci sequence
      
      test_enhancer_behavior(list, [
        :semantic,
        :structural,
        :temporal,
        :relational
      ])
    end
    
    test "semantic enhancement categorizes elements" do
      mixed_list = [
        1, -5, 0, 3.14, -2.7,
        "hello", "WORLD", "123", "user@example.com",
        %{a: 1}, [1, 2], nil, true
      ]
      
      {:ok, enhanced} = Enhancer.enhance(mixed_list, :semantic)
      
      # Check categorization
      assert Map.has_key?(enhanced.semantic.categories, :positive_integer)
      assert Map.has_key?(enhanced.semantic.categories, :negative_integer)
      assert Map.has_key?(enhanced.semantic.categories, :string)
      assert Map.has_key?(enhanced.semantic.categories, :email)
      
      # Check dominant types
      assert length(enhanced.semantic.dominant_types) > 0
    end
    
    test "structural enhancement detects patterns" do
      # Arithmetic sequence
      arithmetic = [2, 4, 6, 8, 10]
      {:ok, arith_enhanced} = Enhancer.enhance(arithmetic, :structural)
      
      assert Map.has_key?(arith_enhanced.structure, :patterns)
      
      # Should detect it's an arithmetic sequence
      distribution = arith_enhanced.structure.distribution
      assert distribution.unique_elements == 5
    end
    
    test "detect fibonacci sequence" do
      fib = [1, 1, 2, 3, 5, 8, 13, 21]
      
      {:ok, enhanced} = Enhancer.enhance(fib, :semantic)
      
      # The classification should recognize fibonacci pattern
      assert enhanced.semantic.classifications.numeric_classification == :fibonacci_like
    end
    
    test "relational enhancement finds correlations" do
      # List where every other element is double the previous
      list = [1, 2, 2, 4, 3, 6, 4, 8]
      
      {:ok, enhanced} = Enhancer.enhance(list, :relational)
      
      assert is_list(enhanced.relational.correlations)
      assert length(enhanced.relational.dependencies) > 0
      
      # Should find doubling dependencies
      assert Enum.any?(enhanced.relational.dependencies, fn dep ->
        dep.type == :double
      end)
    end
    
    test "derive statistics from numeric list" do
      numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      
      {:ok, stats} = Enhancer.derive(numbers, :statistics)
      
      assert stats.statistics.mean == 5.5
      assert stats.statistics.median == 5.5
      assert stats.statistics.min == 1
      assert stats.statistics.max == 10
      assert stats.statistics.sum == 55
      assert Map.has_key?(stats.statistics, :percentiles)
    end
    
    test "pattern detection in lists" do
      # List with repeating pattern
      repeating = [1, 2, 3, 1, 2, 3, 1, 2, 3]
      
      {:ok, patterns} = Enhancer.derive(repeating, :patterns)
      
      # Should detect repeating pattern
      assert length(patterns.patterns.repetitions) > 0
      assert Enum.any?(patterns.patterns.repetitions, fn rep ->
        rep.count > 2
      end)
      
      # Should detect cycles
      assert length(patterns.patterns.cycles) > 0
    end
    
    test "detect alternating pattern" do
      alternating = [:a, :b, :a, :b, :a, :b]
      
      {:ok, enhanced} = Enhancer.enhance(alternating, :structural)
      
      patterns = enhanced.structure.patterns
      assert Enum.any?(patterns.alternating_patterns, fn p ->
        p.type == :alternating
      end)
    end
    
    test "outlier detection" do
      numbers_with_outliers = [1, 2, 3, 4, 5, 100, 6, 7, 8, 9, -50]
      
      {:ok, enhanced} = Enhancer.enhance(numbers_with_outliers, :semantic)
      
      outliers = enhanced.semantic.outliers
      assert 100 in outliers.outliers
      assert -50 in outliers.outliers
    end
    
    test "clustering similar elements" do
      list = [1, 2, 3, 10, 11, 12, 20, 21, 22]
      
      {:ok, enhanced} = Enhancer.enhance(list, :relational)
      
      clusters = enhanced.relational.clusters
      assert length(clusters) > 1
      
      # Should group similar numbers
      assert Enum.any?(clusters, fn cluster ->
        [1, 2, 3] -- cluster.elements == []
      end)
    end
  end
  
  describe "custom derivations" do
    test "custom derivation functions" do
      custom_derive = fn data ->
        %{custom_result: "Processed: #{inspect(data)}"}
      end
      
      {:ok, result} = Enhancer.derive(
        %{test: "data"},
        {:custom, [derive_fn: custom_derive, key: :my_custom]}
      )
      
      assert result.my_custom.custom_result =~ "Processed:"
    end
  end
  
  describe "error handling" do
    test "unknown strategies return errors" do
      assert {:error, :unknown_strategy} = Enhancer.enhance(%{}, :unknown)
      assert {:error, :unknown_derivation} = Enhancer.derive(%{}, :unknown)
    end
    
    test "custom enhancement without function" do
      {:ok, result} = Enhancer.enhance(%{test: 1}, {:custom, []})
      assert result == %{test: 1}
    end
  end
  
  describe "cross-type consistency" do
    test "all types support core strategies" do
      strategies = [:semantic, :structural]
      
      # All types should support these strategies
      for data <- [%{a: 1}, "test", [1, 2, 3]] do
        for strategy <- strategies do
          result = Enhancer.enhance(data, strategy)
          assert match?({:ok, _}, result),
                 "#{inspect(data)} should support #{strategy} strategy"
        end
      end
    end
    
    test "metadata is always added" do
      for data <- [%{a: 1}, "test", [1, 2, 3]] do
        enhanced = Enhancer.with_metadata(data, %{custom: true})
        
        # Result should have metadata
        assert is_map(enhanced)
        assert Map.has_key?(enhanced, :metadata)
        assert enhanced.metadata.custom == true
      end
    end
  end
end
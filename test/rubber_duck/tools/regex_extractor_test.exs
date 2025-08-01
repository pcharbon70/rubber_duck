defmodule RubberDuck.Tools.RegexExtractorTest do
  use ExUnit.Case, async: true
  alias RubberDuck.Tools.RegexExtractor
  
  setup do
    # Register the tool
    RubberDuck.Tool.Registry.register(RegexExtractor)
    :ok
  end
  
  describe "parameter validation" do
    test "validates required parameters" do
      assert {:error, %{parameter: :content}} = RegexExtractor.execute(%{}, %{})
    end
    
    test "validates pattern parameter" do
      params = %{
        content: "test content",
        pattern: "" # Empty pattern should fail
      }
      
      assert {:error, %{parameter: :pattern}} = RegexExtractor.execute(params, %{})
    end
    
    test "validates extraction mode enum" do
      params = %{
        content: "test content",
        pattern: "test",
        extraction_mode: "invalid_mode"
      }
      
      assert {:error, %{parameter: :extraction_mode}} = RegexExtractor.execute(params, %{})
    end
  end
  
  describe "basic pattern matching" do
    test "extracts simple matches" do
      params = %{
        content: "The quick brown fox jumps over the lazy dog",
        pattern: "\\b\\w{5}\\b", # 5-letter words
        extraction_mode: "matches"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.extraction_mode == "matches"
      assert result.total_matches > 0
      assert "quick" in result.results
      assert "brown" in result.results
      assert "jumps" in result.results
    end
    
    test "extracts with captures" do
      params = %{
        content: "Email: user@example.com, Phone: 123-456-7890",
        pattern: "(\\w+)@(\\w+\\.\\w+)", # Email parts
        extraction_mode: "captures"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.extraction_mode == "captures"
      assert result.total_matches == 1
      assert result.results == [["user", "example.com"]]
    end
    
    test "counts matches only" do
      params = %{
        content: "apple banana apple cherry apple",
        pattern: "apple",
        extraction_mode: "count"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.extraction_mode == "count"
      assert result.total_matches == 3
      assert result.results == 3
    end
  end
  
  describe "pattern library" do
    test "uses email pattern from library" do
      params = %{
        content: "Contact us at support@example.com or admin@test.org",
        pattern_library: "email",
        extraction_mode: "matches"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.total_matches == 2
      assert "support@example.com" in result.results
      assert "admin@test.org" in result.results
    end
    
    test "uses URL pattern from library" do
      params = %{
        content: "Visit https://example.com or http://test.org for more info",
        pattern_library: "url",
        extraction_mode: "matches"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.total_matches == 2
      assert "https://example.com" in result.results
      assert "http://test.org" in result.results
    end
    
    test "uses Elixir function pattern from library" do
      params = %{
        content: """
        defmodule MyModule do
          def hello_world do
            :ok
          end
          
          def process_data(input) do
            input
          end
        end
        """,
        pattern_library: "elixir_function",
        extraction_mode: "captures"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.total_matches == 2
      function_names = result.results |> List.flatten()
      assert "hello_world" in function_names
      assert "process_data" in function_names
    end
  end
  
  describe "extraction modes" do
    test "replace mode substitutes matches" do
      params = %{
        content: "Hello world, hello universe!",
        pattern: "hello",
        extraction_mode: "replace",
        substitution: "hi",
        case_sensitive: false
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.extraction_mode == "replace"
      assert result.results == "hi world, hi universe!"
    end
    
    test "split mode divides content" do
      params = %{
        content: "apple,banana,cherry,date",
        pattern: ",",
        extraction_mode: "split"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.extraction_mode == "split"
      assert result.results == ["apple", "banana", "cherry", "date"]
    end
    
    test "scan mode includes position information" do
      params = %{
        content: "The cat sat on the mat",
        pattern: "\\bcat\\b",
        extraction_mode: "scan"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.extraction_mode == "scan"
      assert result.total_matches == 1
      
      match = hd(result.results)
      assert match.text == "cat"
      assert is_integer(match.start_position)
      assert is_integer(match.end_position)
      assert is_integer(match.line_number)
    end
  end
  
  describe "options and limits" do
    test "respects max_matches limit" do
      params = %{
        content: "apple apple apple apple apple",
        pattern: "apple",
        extraction_mode: "matches",
        max_matches: 3
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.total_matches == 3
      assert length(result.results) == 3
    end
    
    test "handles case insensitive matching" do
      params = %{
        content: "Hello HELLO hElLo",
        pattern: "hello",
        extraction_mode: "matches",
        case_sensitive: false
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.total_matches == 3
    end
    
    test "handles multiline matching" do
      params = %{
        content: "Line 1\nLine 2\nLine 3",
        pattern: "^Line",
        extraction_mode: "matches",
        multiline: true
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.total_matches == 3
    end
  end
  
  describe "output formats" do
    test "formats output as JSON" do
      params = %{
        content: "test content with test word",
        pattern: "test",
        extraction_mode: "matches",
        output_format: "json"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert is_binary(result.results)
      {:ok, parsed} = Jason.decode(result.results)
      assert is_list(parsed)
    end
    
    test "formats output as CSV" do
      params = %{
        content: "apple banana cherry",
        pattern: "\\b\\w+\\b",
        extraction_mode: "matches",
        output_format: "csv"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert is_binary(result.results)
      assert String.contains?(result.results, "Index,Match")
      assert String.contains?(result.results, "apple")
    end
    
    test "formats output as plain text" do
      params = %{
        content: "one two three",
        pattern: "\\b\\w+\\b",
        extraction_mode: "matches",
        output_format: "plain"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert is_binary(result.results)
      lines = String.split(result.results, "\n")
      assert "one" in lines
      assert "two" in lines
      assert "three" in lines
    end
    
    test "formats output as detailed" do
      params = %{
        content: "test content",
        pattern: "test",
        extraction_mode: "matches",
        output_format: "detailed"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert is_map(result.results)
      assert Map.has_key?(result.results, :extraction_summary)
      assert Map.has_key?(result.results, :results)
      assert Map.has_key?(result.results, :statistics)
    end
  end
  
  describe "statistics and metadata" do
    test "provides comprehensive statistics" do
      params = %{
        content: "apple banana apple cherry apple date",
        pattern: "\\b\\w+\\b",
        extraction_mode: "matches"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      stats = result.statistics
      assert stats.total_matches == 6
      assert stats.unique_matches == 4 # apple, banana, cherry, date
      assert is_float(stats.average_match_length)
      assert is_map(stats.match_distribution)
      assert is_float(stats.extraction_efficiency)
    end
    
    test "includes metadata about execution" do
      params = %{
        content: "simple test",
        pattern: "test"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      metadata = result.metadata
      assert metadata.content_length == String.length(params.content)
      assert is_integer(metadata.pattern_complexity)
      assert is_integer(metadata.execution_time)
    end
  end
  
  describe "error handling" do
    test "handles invalid regex patterns" do
      params = %{
        content: "test content",
        pattern: "[invalid" # Unclosed bracket
      }
      
      assert {:error, reason} = RegexExtractor.execute(params, %{})
      assert String.contains?(reason, "compilation failed")
    end
    
    test "handles unknown pattern library" do
      params = %{
        content: "test content",
        pattern_library: "nonexistent_pattern"
      }
      
      assert {:error, reason} = RegexExtractor.execute(params, %{})
      assert String.contains?(reason, "Unknown pattern library")
    end
  end
  
  describe "complex patterns" do
    test "extracts IP addresses" do
      params = %{
        content: "Server 192.168.1.1 and client 10.0.0.5 connected",
        pattern_library: "ip_address",
        extraction_mode: "matches"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.total_matches == 2
      assert "192.168.1.1" in result.results
      assert "10.0.0.5" in result.results
    end
    
    test "extracts version numbers" do
      params = %{
        content: "Elixir v1.14.2, Phoenix 1.7.0, Ecto v3.9.4",
        pattern_library: "version_number",
        extraction_mode: "matches"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.total_matches == 3
      version_numbers = result.results
      assert Enum.any?(version_numbers, &String.contains?(&1, "1.14.2"))
      assert Enum.any?(version_numbers, &String.contains?(&1, "1.7.0"))
      assert Enum.any?(version_numbers, &String.contains?(&1, "3.9.4"))
    end
    
    test "extracts UUIDs" do
      params = %{
        content: "Request ID: 550e8400-e29b-41d4-a716-446655440000, Session: 6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        pattern_library: "uuid",
        extraction_mode: "matches"
      }
      
      {:ok, result} = RegexExtractor.execute(params, %{})
      
      assert result.total_matches == 2
      assert "550e8400-e29b-41d4-a716-446655440000" in result.results
      assert "6ba7b810-9dad-11d1-80b4-00c04fd430c8" in result.results
    end
  end
end
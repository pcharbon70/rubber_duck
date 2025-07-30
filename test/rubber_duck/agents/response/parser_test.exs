defmodule RubberDuck.Agents.Response.ParserTest do
  use ExUnit.Case, async: true
  alias RubberDuck.Agents.Response.Parser
  
  describe "format detection" do
    test "detects JSON format" do
      json_content = ~s({"name": "John", "age": 30})
      
      {:ok, format} = Parser.detect_format(json_content)
      
      assert format == :json
    end
    
    test "detects Markdown format" do
      markdown_content = """
      # Header
      
      This is **bold** text with a [link](http://example.com).
      
      ```elixir
      def hello do
        "world"
      end
      ```
      """
      
      {:ok, format} = Parser.detect_format(markdown_content)
      
      assert format == :markdown
    end
    
    test "detects XML format" do
      xml_content = """
      <?xml version="1.0" encoding="UTF-8"?>
      <root>
        <item>value</item>
      </root>
      """
      
      {:ok, format} = Parser.detect_format(xml_content)
      
      assert format == :xml
    end
    
    test "defaults to text for unknown formats" do
      plain_content = "This is just plain text without any special formatting."
      
      {:ok, format} = Parser.detect_format(plain_content)
      
      assert format == :text
    end
    
    test "respects forced format" do
      plain_content = "This looks like text but we'll force it as JSON"
      
      {:ok, format} = Parser.detect_format(plain_content, %{force_format: :json})
      
      assert format == :json
    end
  end
  
  describe "content parsing" do
    test "parses JSON content successfully" do
      json_content = ~s({"name": "Alice", "scores": [95, 87, 92]})
      
      {:ok, parsed_content, format, metadata} = Parser.parse(json_content)
      
      assert format == :json
      assert parsed_content["name"] == "Alice"
      assert parsed_content["scores"] == [95, 87, 92]
      assert Map.has_key?(metadata, :processing_time)
    end
    
    test "handles malformed JSON gracefully" do
      malformed_json = ~s({"name": "Alice", "age": 30,})  # trailing comma
      
      # Should fallback to text parsing rather than crash
      {:ok, parsed_content, format, metadata} = Parser.parse(malformed_json)
      
      # Either succeeds as JSON (if recovery works) or falls back to text
      assert format in [:json, :text]
      assert Map.has_key?(metadata, :processing_time)
    end
    
    test "parses Markdown content with structure extraction" do
      markdown_content = """
      # Main Title
      
      This is a paragraph with **bold** and *italic* text.
      
      ## Subsection
      
      - Item 1
      - Item 2
      - Item 3
      
      ```elixir
      def example do
        :ok
      end
      ```
      """
      
      {:ok, parsed_content, format, metadata} = Parser.parse(markdown_content)
      
      assert format == :markdown
      assert Map.has_key?(parsed_content, :structure)
      assert Map.has_key?(parsed_content, :metadata)
      assert Map.has_key?(parsed_content, :elements)
      assert Map.has_key?(metadata, :processing_time)
    end
    
    test "parses plain text with analysis" do
      text_content = """
      This is a sample text document with multiple sentences. 
      It contains various elements like URLs (https://example.com), 
      email addresses (test@example.com), and dates (2024-01-15).
      
      The text also has some technical terms like API, JSON, and HTTP.
      """
      
      {:ok, parsed_content, format, metadata} = Parser.parse(text_content)
      
      assert format == :text
      assert Map.has_key?(parsed_content, :structure)
      assert Map.has_key?(parsed_content, :metadata)
      assert Map.has_key?(parsed_content, :analysis)
      assert parsed_content.analysis.has_urls == true
      assert parsed_content.analysis.has_emails == true
      assert parsed_content.analysis.has_technical_terms == true
    end
    
    test "handles empty content" do
      {:ok, parsed_content, format, _metadata} = Parser.parse("")
      
      assert format == :text
      assert parsed_content.raw_content == ""
    end
  end
  
  describe "parsing with specific format" do
    test "parses JSON with forced format" do
      content = ~s({"key": "value"})
      
      {:ok, parsed_content} = Parser.parse_with_format(content, :json)
      
      assert parsed_content["key"] == "value"
    end
    
    test "handles unsupported format gracefully" do
      content = "some content"
      
      {:ok, parsed_content} = Parser.parse_with_format(content, :unsupported_format)
      
      # Should return content as-is for unsupported formats
      assert parsed_content == content
    end
  end
  
  describe "metadata extraction" do
    test "extracts JSON metadata" do
      parsed_json = %{
        "user" => %{
          "name" => "Alice",
          "details" => %{
            "age" => 30,
            "city" => "New York"
          }
        },
        "scores" => [95, 87, 92]
      }
      
      metadata = Parser.extract_metadata(parsed_json, :json)
      
      assert Map.has_key?(metadata, :keys)
      assert Map.has_key?(metadata, :depth)
      assert metadata.depth == 3  # user -> details -> age/city
    end
    
    test "extracts Markdown metadata" do
      markdown_content = """
      # Title
      
      This is a paragraph with [a link](http://example.com).
      
      ```elixir
      code_block
      ```
      
      More content here.
      """
      
      metadata = Parser.extract_metadata(markdown_content, :markdown)
      
      assert Map.has_key?(metadata, :headers)
      assert Map.has_key?(metadata, :links)
      assert Map.has_key?(metadata, :code_blocks)
      assert metadata.headers == 1
      assert metadata.links == 1
      assert metadata.code_blocks == 1
    end
  end
  
  describe "validation" do
    test "validates JSON structure" do
      valid_json = %{"name" => "Alice", "age" => 30}
      
      {:ok, validated} = Parser.validate_parsed_content(valid_json, :json)
      
      assert validated == valid_json
    end
    
    test "validates Markdown structure" do
      markdown_content = """
      # Header
      
      Valid markdown content.
      """
      
      {:ok, validated} = Parser.validate_parsed_content(markdown_content, :markdown)
      
      assert validated == markdown_content
    end
  end
  
  describe "supported formats" do
    test "lists all supported formats" do
      formats = Parser.supported_formats()
      
      assert is_list(formats)
      assert :json in formats
      assert :markdown in formats
      assert :text in formats
      assert :xml in formats
    end
    
    test "checks format support" do
      assert Parser.format_supported?(:json)
      assert Parser.format_supported?(:markdown)
      assert Parser.format_supported?(:text)
      refute Parser.format_supported?(:nonexistent_format)
    end
  end
end
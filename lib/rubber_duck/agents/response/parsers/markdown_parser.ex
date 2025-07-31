defmodule RubberDuck.Agents.Response.Parser.MarkdownParser do
  @moduledoc """
  Markdown response parser with structure extraction and enhancement.
  """

  use RubberDuck.Agents.Response.Parser
  require Logger

  @impl true
  def parse(content, _options \\ %{}) do
    try do
      parsed = %{
        raw_content: content,
        structure: extract_structure(content),
        metadata: extract_metadata(content),
        elements: extract_elements(content)
      }
      
      {:ok, parsed}
    rescue
      error ->
        Logger.warning("Markdown parsing failed: #{inspect(error)}")
        {:error, "Markdown parsing failed: #{Exception.message(error)}"}
    end
  end

  @impl true
  def detect(content) do
    confidence = calculate_markdown_confidence(content)
    {:ok, confidence}
  end

  @impl true
  def format, do: :markdown

  @impl true
  def supports_streaming?, do: true

  # Private functions

  defp extract_structure(content) do
    headers = extract_headers(content)
    
    %{
      headers: headers,
      outline: build_outline(headers),
      sections: build_sections(content, headers),
      toc: generate_table_of_contents(headers)
    }
  end

  defp extract_headers(content) do
    Regex.scan(~r/^(#+)\s+(.+)$/m, content, capture: :all_but_first)
    |> Enum.with_index()
    |> Enum.map(fn {[level_str, title], index} ->
      %{
        level: String.length(level_str),
        title: String.trim(title),
        id: generate_header_id(title),
        index: index,
        line: find_line_number(content, title)
      }
    end)
    |> Enum.filter(fn header -> header.level <= 6 end)
  end

  defp build_outline(headers) do
    headers
    |> Enum.map(fn header ->
      %{
        level: header.level,
        title: header.title,
        id: header.id
      }
    end)
  end

  defp build_sections(content, headers) do
    lines = String.split(content, "\n")
    
    headers
    |> Enum.with_index()
    |> Enum.map(fn {header, index} ->
      start_line = header.line
      end_line = case Enum.at(headers, index + 1) do
        nil -> length(lines)
        next_header -> next_header.line - 1
      end
      
      section_content = lines
      |> Enum.slice(start_line, end_line - start_line)
      |> Enum.join("\n")
      
      %{
        header: header,
        content: section_content,
        word_count: count_words(section_content),
        elements: extract_section_elements(section_content)
      }
    end)
  end

  defp generate_table_of_contents(headers) do
    headers
    |> Enum.map(fn header ->
      indent = String.duplicate("  ", header.level - 1)
      "#{indent}- [#{header.title}](##{header.id})"
    end)
    |> Enum.join("\n")
  end

  defp extract_metadata(content) do
    %{
      word_count: count_words(content),
      character_count: String.length(content),
      line_count: length(String.split(content, "\n")),
      reading_time: estimate_reading_time(content),
      complexity_score: calculate_complexity_score(content),
      language: detect_language(content)
    }
  end

  defp extract_elements(content) do
    %{
      links: extract_links(content),
      images: extract_images(content),
      code_blocks: extract_code_blocks(content),
      inline_code: extract_inline_code(content),
      lists: extract_lists(content),
      tables: extract_tables(content),
      blockquotes: extract_blockquotes(content),
      emphasis: extract_emphasis(content)
    }
  end

  defp extract_links(content) do
    # Extract both reference-style and inline links
    inline_links = Regex.scan(~r/\[([^\]]+)\]\(([^)]+)\)/, content, capture: :all_but_first)
    |> Enum.map(fn [text, url] -> %{type: :inline, text: text, url: url} end)
    
    reference_links = Regex.scan(~r/\[([^\]]+)\]\[([^\]]+)\]/, content, capture: :all_but_first)
    |> Enum.map(fn [text, ref] -> %{type: :reference, text: text, reference: ref} end)
    
    inline_links ++ reference_links
  end

  defp extract_images(content) do
    Regex.scan(~r/!\[([^\]]*)\]\(([^)]+)\)/, content, capture: :all_but_first)
    |> Enum.map(fn [alt_text, src] -> 
      %{alt_text: alt_text, src: src, type: determine_image_type(src)}
    end)
  end

  defp extract_code_blocks(content) do
    Regex.scan(~r/```(\w*)\n(.*?)```/s, content, capture: :all_but_first)
    |> Enum.map(fn [language, code] ->
      %{
        language: if(language == "", do: nil, else: language),
        code: code,
        line_count: length(String.split(code, "\n"))
      }
    end)
  end

  defp extract_inline_code(content) do
    Regex.scan(~r/`([^`]+)`/, content, capture: :all_but_first)
    |> Enum.map(fn [code] -> %{code: code} end)
  end

  defp extract_lists(content) do
    # Extract both ordered and unordered lists
    unordered = Regex.scan(~r/^[\s]*[-*+]\s+(.+)$/m, content, capture: :all_but_first)
    |> Enum.map(fn [item] -> %{type: :unordered, content: item} end)
    
    ordered = Regex.scan(~r/^[\s]*\d+\.\s+(.+)$/m, content, capture: :all_but_first)
    |> Enum.map(fn [item] -> %{type: :ordered, content: item} end)
    
    unordered ++ ordered
  end

  defp extract_tables(content) do
    # Extract markdown tables
    table_pattern = ~r/^\|(.+)\|\s*\n\|[-\s|]+\|\s*\n((?:\|.+\|\s*\n?)*)/m
    
    Regex.scan(table_pattern, content, capture: :all_but_first)
    |> Enum.map(fn [header_row, body_rows] ->
      headers = String.split(header_row, "|") 
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      
      rows = String.split(body_rows, "\n")
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn row ->
        String.split(row, "|")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      end)
      
      %{headers: headers, rows: rows, column_count: length(headers)}
    end)
  end

  defp extract_blockquotes(content) do
    Regex.scan(~r/^>\s*(.+)$/m, content, capture: :all_but_first)
    |> Enum.map(fn [quote] -> %{content: quote} end)
  end

  defp extract_emphasis(content) do
    bold = Regex.scan(~r/\*\*([^*]+)\*\*|__([^_]+)__/, content, capture: :all_but_first)
    |> Enum.map(fn captures -> 
      text = Enum.find(captures, &(&1 != ""))
      %{type: :bold, text: text}
    end)
    
    italic = Regex.scan(~r/\*([^*]+)\*|_([^_]+)_/, content, capture: :all_but_first)
    |> Enum.map(fn captures ->
      text = Enum.find(captures, &(&1 != ""))
      %{type: :italic, text: text}
    end)
    
    bold ++ italic
  end

  defp extract_section_elements(content) do
    %{
      paragraphs: count_paragraphs(content),
      sentences: count_sentences(content),
      lists: length(extract_lists(content)),
      code_blocks: length(extract_code_blocks(content))
    }
  end

  defp generate_header_id(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  defp find_line_number(content, title) do
    String.split(content, "\n")
    |> Enum.with_index()
    |> Enum.find_value(fn {line, index} ->
      if String.contains?(line, title), do: index, else: nil
    end) || 0
  end

  defp count_words(content) do
    content
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> length()
  end

  defp count_paragraphs(content) do
    content
    |> String.split(~r/\n\s*\n/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end

  defp count_sentences(content) do
    content
    |> String.split(~r/[.!?]+/)
    |> Enum.reject(&(&1 == "" or String.trim(&1) == ""))
    |> length()
  end

  defp estimate_reading_time(content) do
    words = count_words(content)
    # Average reading speed: 200 words per minute
    max(1, div(words, 200))
  end

  defp calculate_complexity_score(content) do
    # Simple complexity score based on various factors
    word_count = count_words(content)
    sentence_count = count_sentences(content)
    code_blocks = length(extract_code_blocks(content))
    tables = length(extract_tables(content))
    
    avg_words_per_sentence = if sentence_count > 0, do: word_count / sentence_count, else: 0
    
    base_score = min(avg_words_per_sentence / 20, 1.0)  # Normalize to 0-1
    complexity_bonus = (code_blocks * 0.1) + (tables * 0.1)
    
    min(base_score + complexity_bonus, 1.0)
  end

  defp detect_language(content) do
    # Simple language detection based on common patterns
    cond do
      Regex.match?(~r/\b(the|and|or|but|in|on|at|to|for|of|with|by)\b/i, content) -> "en"
      Regex.match?(~r/\b(le|la|les|de|du|des|et|ou|mais|dans|sur|à|pour|avec|par)\b/i, content) -> "fr"
      Regex.match?(~r/\b(der|die|das|und|oder|aber|in|auf|zu|für|von|mit|durch)\b/i, content) -> "de"
      true -> "unknown"
    end
  end

  defp determine_image_type(src) do
    cond do
      String.match?(src, ~r/\.(jpg|jpeg|png|gif|webp)$/i) -> :raster
      String.match?(src, ~r/\.(svg)$/i) -> :vector
      String.starts_with?(src, "http") -> :external
      true -> :local
    end
  end

  defp calculate_markdown_confidence(content) do
    indicators = [
      {~r/^#+\s/m, 0.3},          # Headers
      {~r/\*\*[^*]+\*\*/, 0.2},   # Bold text
      {~r/\*[^*]+\*/, 0.1},       # Italic text
      {~r/```[^`]*```/s, 0.4},    # Code blocks
      {~r/\[[^\]]+\]\([^)]+\)/, 0.3}, # Links
      {~r/^\s*[-*+]\s/m, 0.2},    # Lists
      {~r/^\s*\d+\.\s/m, 0.2},    # Numbered lists
      {~r/^\|.*\|/m, 0.2},        # Tables
      {~r/^>\s/m, 0.1}            # Blockquotes
    ]
    
    indicators
    |> Enum.map(fn {pattern, weight} ->
      matches = Regex.scan(pattern, content) |> length()
      min(matches * weight, weight)  # Cap contribution at the weight
    end)
    |> Enum.sum()
    |> min(1.0)
  end
end
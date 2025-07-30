defmodule RubberDuck.Agents.Response.Parser.TextParser do
  @moduledoc """
  Plain text response parser with structure extraction and analysis.
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
        analysis: analyze_content(content)
      }
      
      {:ok, parsed}
    rescue
      error ->
        Logger.warning("Text parsing failed: #{inspect(error)}")
        {:error, "Text parsing failed: #{Exception.message(error)}"}
    end
  end

  @impl true
  def detect(content) do
    # Text parser is the fallback, so it always has some confidence
    confidence = calculate_text_confidence(content)
    {:ok, confidence}
  end

  @impl true
  def format, do: :text

  @impl true
  def supports_streaming?, do: true

  # Private functions

  defp extract_structure(content) do
    lines = String.split(content, "\n")
    paragraphs = extract_paragraphs(content)
    sentences = extract_sentences(content)
    
    %{
      lines: lines,
      line_count: length(lines),
      paragraphs: paragraphs,
      paragraph_count: length(paragraphs),
      sentences: sentences,
      sentence_count: length(sentences),
      sections: detect_sections(content),
      formatting: detect_formatting_patterns(content)
    }
  end

  defp extract_metadata(content) do
    %{
      character_count: String.length(content),
      word_count: count_words(content),
      reading_time: estimate_reading_time(content),
      language: detect_language(content),
      encoding: detect_encoding(content),
      complexity: calculate_readability_score(content),
      sentiment: analyze_sentiment(content),
      topics: extract_topics(content)
    }
  end

  defp analyze_content(content) do
    %{
      has_code: detect_code_patterns(content),
      has_urls: detect_urls(content),
      has_emails: detect_emails(content),
      has_dates: detect_dates(content),
      has_numbers: detect_numbers(content),
      has_lists: detect_list_patterns(content),
      has_questions: detect_questions(content),
      has_technical_terms: detect_technical_terms(content),
      content_type: classify_content_type(content)
    }
  end

  defp extract_paragraphs(content) do
    content
    |> String.split(~r/\n\s*\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index()
    |> Enum.map(fn {paragraph, index} ->
      %{
        content: paragraph,
        index: index,
        word_count: count_words(paragraph),
        sentence_count: count_sentences(paragraph)
      }
    end)
  end

  defp extract_sentences(content) do
    # Simple sentence splitting on periods, exclamation marks, and question marks
    content
    |> String.split(~r/[.!?]+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index()
    |> Enum.map(fn {sentence, index} ->
      %{
        content: sentence,
        index: index,
        word_count: count_words(sentence),
        type: classify_sentence_type(sentence)
      }
    end)
  end

  defp detect_sections(content) do
    # Look for section-like patterns
    sections = []
    
    # Number-based sections (1. 2. 3.)
    numbered_sections = Regex.scan(~r/^\s*(\d+\.)\s*(.+)$/m, content, capture: :all_but_first)
    |> Enum.map(fn [number, title] ->
      %{type: :numbered, number: number, title: String.trim(title)}
    end)
    
    # Letter-based sections (a. b. c.)
    letter_sections = Regex.scan(~r/^\s*([a-z]\.)\s*(.+)$/m, content, capture: :all_but_first)
    |> Enum.map(fn [letter, title] ->
      %{type: :lettered, letter: letter, title: String.trim(title)}
    end)
    
    # Dash/bullet sections
    bullet_sections = Regex.scan(~r/^\s*[-•*]\s*(.+)$/m, content, capture: :all_but_first)
    |> Enum.map(fn [title] ->
      %{type: :bullet, title: String.trim(title)}
    end)
    
    sections ++ numbered_sections ++ letter_sections ++ bullet_sections
  end

  defp detect_formatting_patterns(content) do
    %{
      has_indentation: Regex.match?(~r/^\s{2,}/m, content),
      has_all_caps: Regex.match?(~r/\b[A-Z]{3,}\b/, content),
      has_emphasis_markers: Regex.match?(~r/\*[^*]+\*|_[^_]+_/, content),
      has_parentheses: Regex.match?(~r/\([^)]+\)/, content),
      has_brackets: Regex.match?(~r/\[[^\]]+\]/, content),
      has_quotes: Regex.match?(~r/["'][^"']+["']/, content),
      line_breaks: count_line_breaks(content)
    }
  end

  defp count_words(content) do
    content
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> length()
  end

  defp count_sentences(content) do
    content
    |> String.split(~r/[.!?]+/)
    |> Enum.reject(&(&1 == "" or String.trim(&1) == ""))
    |> length()
  end

  defp count_line_breaks(content) do
    (String.split(content, "\n") |> length()) - 1
  end

  defp estimate_reading_time(content) do
    words = count_words(content)
    # Average reading speed: 200 words per minute
    max(1, div(words, 200))
  end

  defp detect_language(content) do
    # Simple language detection based on common words
    english_indicators = ~w[the and or but in on at to for of with by is are was were be been being have has had do does did will would could should]
    french_indicators = ~w[le la les de du des et ou mais dans sur à pour avec par est sont était étaient être été ayant avoir a eu faire fait]
    german_indicators = ~w[der die das und oder aber in auf zu für von mit durch ist sind war waren sein gewesen haben hat hatte tun]
    spanish_indicators = ~w[el la los las de del y o pero en sobre a para con por es son era eran ser sido tener tiene tuvo hacer]
    
    words = content
    |> String.downcase()
    |> String.split()
    |> Enum.take(100)  # Check first 100 words
    
    english_score = count_language_indicators(words, english_indicators)
    french_score = count_language_indicators(words, french_indicators)
    german_score = count_language_indicators(words, german_indicators)
    spanish_score = count_language_indicators(words, spanish_indicators)
    
    scores = [
      {"en", english_score},
      {"fr", french_score},
      {"de", german_score},
      {"es", spanish_score}
    ]
    
    case Enum.max_by(scores, fn {_lang, score} -> score end) do
      {lang, score} when score > 2 -> lang
      _ -> "unknown"
    end
  end

  defp count_language_indicators(words, indicators) do
    words
    |> Enum.count(&(&1 in indicators))
  end

  defp detect_encoding(content) do
    # Simple encoding detection
    cond do
      String.valid?(content) -> "utf-8"
      true -> "unknown"
    end
  end

  defp calculate_readability_score(content) do
    # Simplified readability score (like Flesch Reading Ease)
    sentences = count_sentences(content)
    words = count_words(content)
    syllables = estimate_syllables(content)
    
    if sentences > 0 and words > 0 do
      avg_sentence_length = words / sentences
      avg_syllables_per_word = syllables / words
      
      # Simplified Flesch formula
      score = 206.835 - (1.015 * avg_sentence_length) - (84.6 * avg_syllables_per_word)
      max(0, min(100, score)) / 100  # Normalize to 0-1
    else
      0.5  # Default to medium complexity
    end
  end

  defp estimate_syllables(content) do
    content
    |> String.downcase()
    |> String.replace(~r/[^a-z\s]/, "")
    |> String.split()
    |> Enum.map(&count_syllables_in_word/1)
    |> Enum.sum()
  end

  defp count_syllables_in_word(word) do
    # Simple syllable counting
    vowels = ~r/[aeiouy]/
    syllable_count = Regex.scan(vowels, word) |> length()
    
    # Adjust for silent e
    syllable_count = if String.ends_with?(word, "e") and syllable_count > 1 do
      syllable_count - 1
    else
      syllable_count
    end
    
    max(1, syllable_count)
  end

  defp analyze_sentiment(content) do
    # Very basic sentiment analysis
    positive_words = ~w[good great excellent amazing wonderful fantastic happy pleased satisfied love like enjoy]
    negative_words = ~w[bad terrible awful horrible disappointing sad angry hate dislike problem issue error]
    
    words = content
    |> String.downcase()
    |> String.split()
    
    positive_count = Enum.count(words, &(&1 in positive_words))
    negative_count = Enum.count(words, &(&1 in negative_words))
    
    cond do
      positive_count > negative_count -> "positive"
      negative_count > positive_count -> "negative"
      true -> "neutral"
    end
  end

  defp extract_topics(content) do
    # Simple topic extraction based on frequent nouns
    words = content
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    
    # Filter out common stop words
    stop_words = ~w[the and or but in on at to for of with by is are was were be been being have has had do does did will would could should a an this that these those]
    
    content_words = words -- stop_words
    
    # Count word frequencies
    word_frequencies = Enum.frequencies(content_words)
    
    # Get top 5 most frequent words as topics
    word_frequencies
    |> Enum.sort_by(fn {_word, count} -> count end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {word, _count} -> word end)
  end

  defp detect_code_patterns(content) do
    code_indicators = [
      ~r/function\s+\w+\s*\(/,
      ~r/class\s+\w+/,
      ~r/def\s+\w+/,
      ~r/import\s+\w+/,
      ~r/from\s+\w+\s+import/,
      ~r/\w+\s*=\s*\w+\([^)]*\)/,
      ~r/\{[^}]*\}/,
      ~r/\[[^\]]*\]/,
      ~r/;$/m,
      ~r/\/\/|\/\*|\*/
    ]
    
    Enum.any?(code_indicators, &Regex.match?(&1, content))
  end

  defp detect_urls(content) do
    Regex.match?(~r/https?:\/\/[^\s]+/, content)
  end

  defp detect_emails(content) do
    Regex.match?(~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, content)
  end

  defp detect_dates(content) do
    date_patterns = [
      ~r/\d{1,2}\/\d{1,2}\/\d{4}/,
      ~r/\d{4}-\d{2}-\d{2}/,
      ~r/\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}/i
    ]
    
    Enum.any?(date_patterns, &Regex.match?(&1, content))
  end

  defp detect_numbers(content) do
    Regex.match?(~r/\b\d+(?:\.\d+)?\b/, content)
  end

  defp detect_list_patterns(content) do
    list_patterns = [
      ~r/^\s*\d+\.\s/m,
      ~r/^\s*[-•*]\s/m,
      ~r/^\s*[a-zA-Z]\.\s/m
    ]
    
    Enum.any?(list_patterns, &Regex.match?(&1, content))
  end

  defp detect_questions(content) do
    Regex.match?(~r/\?/, content)
  end

  defp detect_technical_terms(content) do
    # Look for technical patterns
    technical_patterns = [
      ~r/\b(API|HTTP|JSON|XML|SQL|HTML|CSS|JavaScript|Python|Java|React|Node\.js)\b/i,
      ~r/\b(database|server|client|endpoint|authentication|authorization)\b/i,
      ~r/\b(algorithm|function|method|class|object|array|string|integer|boolean)\b/i
    ]
    
    Enum.any?(technical_patterns, &Regex.match?(&1, content))
  end

  defp classify_content_type(content) do
    cond do
      detect_code_patterns(content) -> :code_or_technical
      detect_questions(content) -> :qa_or_help
      detect_list_patterns(content) -> :instructional_or_list
      detect_technical_terms(content) -> :technical_documentation
      String.length(content) < 100 -> :short_response
      count_sentences(content) < 3 -> :brief_answer
      true -> :general_text
    end
  end

  defp classify_sentence_type(sentence) do
    trimmed = String.trim(sentence)
    
    cond do
      String.ends_with?(trimmed, "?") -> :question
      String.ends_with?(trimmed, "!") -> :exclamation
      Regex.match?(~r/^(please|could you|would you|can you)/i, trimmed) -> :request
      Regex.match?(~r/^(first|second|third|next|then|finally)/i, trimmed) -> :instruction
      true -> :statement
    end
  end

  defp calculate_text_confidence(content) do
    # Text parser is always available as fallback
    # But give higher confidence to content that looks like plain text
    
    # Lower confidence if it looks like structured data
    if Regex.match?(~r/^\s*[\{\[]/, content) or 
       Regex.match?(~r/<[^>]+>/, content) or
       String.contains?(content, "```") do
      0.3
    else
      0.6  # Decent confidence for plain text
    end
  end
end
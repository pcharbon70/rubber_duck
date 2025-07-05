defimpl RubberDuck.Enhancer, for: BitString do
  @moduledoc """
  Enhancer implementation for String/BitString data type.
  
  Provides enhancement capabilities for text data including:
  - Language detection and analysis
  - Sentiment and tone analysis
  - Entity extraction
  - Content classification
  """
  
  @doc """
  Enhance the string using the specified strategy.
  
  ## Strategies
  
  - `:semantic` - Extract semantic meaning (entities, topics)
  - `:structural` - Analyze text structure (paragraphs, sentences)
  - `:temporal` - Extract temporal references
  - `:relational` - Identify relationships and references
  - `{:custom, opts}` - Custom enhancement with options
  """
  def enhance(string, strategy) when is_binary(string) do
    enhanced = case strategy do
      :semantic -> enhance_semantic(string)
      :structural -> enhance_structural(string)
      :temporal -> enhance_temporal(string)
      :relational -> enhance_relational(string)
      {:custom, opts} -> enhance_custom(string, opts)
      _ -> {:error, :unknown_strategy}
    end
    
    case enhanced do
      {:error, _} = error -> error
      result -> {:ok, result}
    end
  end
  
  @doc """
  Add contextual information to the string.
  """
  def with_context(string, context) do
    %{
      content: string,
      context: context
    }
  end
  
  @doc """
  Enrich string with metadata.
  """
  def with_metadata(string, metadata) do
    %{
      content: string,
      metadata: Map.merge(extract_base_metadata(string), metadata)
    }
  end
  
  @doc """
  Derive new information from the string data.
  """
  def derive(string, derivations) when is_list(derivations) do
    results = Enum.reduce(derivations, %{}, fn derivation, acc ->
      case derive_single(string, derivation) do
        {:ok, key, value} -> Map.put(acc, key, value)
        _ -> acc
      end
    end)
    
    {:ok, results}
  end
  
  def derive(string, derivation) do
    case derive_single(string, derivation) do
      {:ok, key, value} -> {:ok, %{key => value}}
      error -> error
    end
  end
  
  # Private functions
  
  defp enhance_semantic(string) do
    %{
      text: string,
      semantic: %{
        entities: extract_entities(string),
        keywords: extract_keywords(string),
        topics: infer_topics(string),
        language: detect_language(string),
        readability_score: calculate_readability(string)
      }
    }
  end
  
  defp enhance_structural(string) do
    sentences = String.split(string, ~r/[.!?]+\s*/)
    paragraphs = String.split(string, ~r/\n\n+/)
    words = String.split(string, ~r/\s+/)
    
    %{
      text: string,
      structure: %{
        paragraph_count: length(paragraphs),
        sentence_count: length(sentences),
        word_count: length(words),
        average_sentence_length: calculate_avg_sentence_length(sentences),
        sections: analyze_sections(string),
        formatting: detect_formatting(string)
      }
    }
  end
  
  defp enhance_temporal(string) do
    %{
      text: string,
      temporal: %{
        extracted_dates: extract_dates(string),
        extracted_times: extract_times(string),
        temporal_expressions: extract_temporal_expressions(string),
        enhanced_at: DateTime.utc_now()
      }
    }
  end
  
  defp enhance_relational(string) do
    %{
      text: string,
      relational: %{
        urls: extract_urls(string),
        email_addresses: extract_emails(string),
        references: extract_references(string),
        mentions: extract_mentions(string)
      }
    }
  end
  
  defp enhance_custom(string, opts) do
    case Keyword.get(opts, :enhancer) do
      nil -> string
      func when is_function(func, 1) -> func.(string)
      _ -> string
    end
  end
  
  defp derive_single(string, :summary) do
    summary = generate_summary(string)
    {:ok, :summary, summary}
  end
  
  defp derive_single(string, :statistics) do
    stats = %{
      character_count: String.length(string),
      byte_size: byte_size(string),
      line_count: length(String.split(string, "\n")),
      word_count: length(String.split(string, ~r/\s+/)),
      unique_words: string |> String.split(~r/\s+/) |> Enum.uniq() |> length(),
      average_word_length: calculate_avg_word_length(string),
      punctuation_count: count_punctuation(string),
      digit_count: count_digits(string),
      uppercase_ratio: calculate_uppercase_ratio(string)
    }
    {:ok, :statistics, stats}
  end
  
  defp derive_single(string, :relationships) do
    rels = %{
      cross_references: find_cross_references(string),
      repeated_phrases: find_repeated_phrases(string),
      connections: analyze_connections(string)
    }
    {:ok, :relationships, rels}
  end
  
  defp derive_single(string, :patterns) do
    patterns = %{
      formatting_patterns: detect_formatting_patterns(string),
      linguistic_patterns: detect_linguistic_patterns(string),
      structural_patterns: detect_text_patterns(string)
    }
    {:ok, :patterns, patterns}
  end
  
  defp derive_single(string, {:custom, opts}) do
    case Keyword.get(opts, :derive_fn) do
      nil -> {:error, :no_derive_function}
      func when is_function(func, 1) ->
        result = func.(string)
        {:ok, Keyword.get(opts, :key, :custom), result}
    end
  end
  
  defp derive_single(_string, _unknown) do
    {:error, :unknown_derivation}
  end
  
  # Helper functions
  
  defp extract_base_metadata(string) do
    %{
      length: String.length(string),
      encoding: :utf8,
      has_unicode: String.match?(string, ~r/[^\x00-\x7F]/),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp extract_entities(string) do
    # Simple entity extraction - in a real system, use NLP library
    %{
      capitalized_words: extract_capitalized_words(string),
      numbers: Regex.scan(~r/\b\d+(?:\.\d+)?\b/, string) |> List.flatten(),
      potential_names: extract_potential_names(string)
    }
  end
  
  defp extract_capitalized_words(string) do
    string
    |> String.split(~r/\s+/)
    |> Enum.filter(&String.match?(&1, ~r/^[A-Z]/))
    |> Enum.uniq()
  end
  
  defp extract_potential_names(string) do
    # Simple heuristic: capitalized words that aren't at sentence start
    ~r/(?<![.!?]\s)[A-Z][a-z]+(?:\s[A-Z][a-z]+)*/
    |> Regex.scan(string)
    |> List.flatten()
    |> Enum.uniq()
  end
  
  defp extract_keywords(string) do
    # Simple keyword extraction based on frequency
    words = string
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(&(String.length(&1) > 3))
    
    word_frequencies = Enum.frequencies(words)
    
    word_frequencies
    |> Enum.sort_by(fn {_word, count} -> -count end)
    |> Enum.take(10)
    |> Enum.map(fn {word, _count} -> word end)
  end
  
  defp infer_topics(string) do
    # Simple topic inference based on keywords
    keywords = extract_keywords(string)
    
    topics = []
    topics = if Enum.any?(keywords, &String.match?(&1, ~r/code|program|software|function/i)), do: [:programming | topics], else: topics
    topics = if Enum.any?(keywords, &String.match?(&1, ~r/data|database|query|table/i)), do: [:data | topics], else: topics
    topics = if Enum.any?(keywords, &String.match?(&1, ~r/user|customer|client|person/i)), do: [:people | topics], else: topics
    topics = if Enum.any?(keywords, &String.match?(&1, ~r/system|server|network|cloud/i)), do: [:infrastructure | topics], else: topics
    
    topics
  end
  
  defp detect_language(string) do
    # Simple language detection heuristics
    cond do
      String.match?(string, ~r/\bdef\s+\w+|defmodule\s+|defp\s+/) -> :elixir
      String.match?(string, ~r/\bfunction\s+\w+|const\s+|let\s+|var\s+/) -> :javascript
      String.match?(string, ~r/\bdef\s+\w+:|class\s+\w+:|import\s+/) -> :python
      String.match?(string, ~r/\bfn\s+\w+|impl\s+|trait\s+|struct\s+/) -> :rust
      String.match?(string, ~r/[áéíóúñ]/i) -> :spanish
      String.match?(string, ~r/[àèìòùç]/i) -> :french
      String.match?(string, ~r/[äöüß]/i) -> :german
      true -> :english
    end
  end
  
  defp calculate_readability(string) do
    sentences = String.split(string, ~r/[.!?]+\s*/)
    words = String.split(string, ~r/\s+/)
    syllables = Enum.sum(Enum.map(words, &estimate_syllables/1))
    
    # Flesch Reading Ease approximation
    if length(sentences) > 0 and length(words) > 0 do
      206.835 - 1.015 * (length(words) / length(sentences)) - 84.6 * (syllables / length(words))
    else
      0.0
    end
  end
  
  defp estimate_syllables(word) do
    # Simple syllable estimation
    word
    |> String.downcase()
    |> String.graphemes()
    |> Enum.count(&String.match?(&1, ~r/[aeiou]/))
    |> max(1)
  end
  
  defp calculate_avg_sentence_length(sentences) do
    if length(sentences) > 0 do
      total_words = sentences
      |> Enum.map(&length(String.split(&1, ~r/\s+/)))
      |> Enum.sum()
      
      total_words / length(sentences)
    else
      0.0
    end
  end
  
  defp analyze_sections(string) do
    # Detect sections by headers or double newlines
    sections = String.split(string, ~r/\n\n+|^#+\s+.+$/m)
    
    %{
      count: length(sections),
      sizes: Enum.map(sections, &String.length/1),
      has_headers: String.match?(string, ~r/^#+\s+/m)
    }
  end
  
  defp detect_formatting(string) do
    %{
      has_markdown: String.match?(string, ~r/[*_`#\[\]]/),
      has_html: String.match?(string, ~r/<[^>]+>/),
      has_code_blocks: String.match?(string, ~r/```/),
      indentation_style: detect_indentation(string)
    }
  end
  
  defp detect_indentation(string) do
    lines = String.split(string, "\n")
    indents = lines
    |> Enum.map(&Regex.run(~r/^(\s+)/, &1))
    |> Enum.filter(& &1)
    |> Enum.map(&List.first/1)
    
    cond do
      Enum.any?(indents, &String.contains?(&1, "\t")) -> :tabs
      Enum.any?(indents, &String.match?(&1, ~r/^ {2,}/)) -> :spaces
      true -> :none
    end
  end
  
  defp extract_dates(string) do
    patterns = [
      ~r/\d{4}-\d{2}-\d{2}/,           # ISO format
      ~r/\d{1,2}\/\d{1,2}\/\d{2,4}/,   # US format
      ~r/\d{1,2}-\d{1,2}-\d{2,4}/,     # European format
      ~r/\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+\d{1,2},?\s+\d{4}/i  # Month name
    ]
    
    Enum.flat_map(patterns, &Regex.scan(&1, string))
    |> List.flatten()
    |> Enum.uniq()
  end
  
  defp extract_times(string) do
    patterns = [
      ~r/\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?/i,  # Time formats
      ~r/\d{1,2}\s*(?:am|pm)/i                      # Simple am/pm
    ]
    
    Enum.flat_map(patterns, &Regex.scan(&1, string))
    |> List.flatten()
    |> Enum.uniq()
  end
  
  defp extract_temporal_expressions(string) do
    expressions = ~r/\b(?:today|tomorrow|yesterday|next\s+\w+|last\s+\w+|this\s+\w+|ago|from\s+now)\b/i
    
    Regex.scan(expressions, string)
    |> List.flatten()
    |> Enum.uniq()
  end
  
  defp extract_urls(string) do
    ~r/https?:\/\/[^\s<>"{}|\\^`\[\]]+/
    |> Regex.scan(string)
    |> List.flatten()
  end
  
  defp extract_emails(string) do
    ~r/[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}/
    |> Regex.scan(string)
    |> List.flatten()
  end
  
  defp extract_references(string) do
    # Extract various reference patterns
    %{
      citations: Regex.scan(~r/\[\d+\]|\(\d{4}\)/, string) |> List.flatten(),
      footnotes: Regex.scan(~r/\[\^[^\]]+\]/, string) |> List.flatten(),
      links: Regex.scan(~r/\[[^\]]+\]\([^)]+\)/, string) |> List.flatten()
    }
  end
  
  defp extract_mentions(string) do
    # Extract @mentions and #hashtags
    %{
      mentions: Regex.scan(~r/@\w+/, string) |> List.flatten(),
      hashtags: Regex.scan(~r/#\w+/, string) |> List.flatten()
    }
  end
  
  defp generate_summary(string) do
    sentences = String.split(string, ~r/[.!?]+\s*/)
    
    %{
      first_sentence: List.first(sentences),
      total_sentences: length(sentences),
      key_phrases: extract_key_phrases(string)
    }
  end
  
  defp extract_key_phrases(string) do
    # Simple key phrase extraction - find repeated multi-word phrases
    words = String.split(string, ~r/\s+/)
    
    # Extract 2-3 word phrases
    phrases = for i <- 0..(length(words) - 2) do
      phrase = Enum.slice(words, i, 2) |> Enum.join(" ")
      if String.length(phrase) > 5, do: phrase, else: nil
    end
    
    phrases
    |> Enum.filter(& &1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_phrase, count} -> count > 1 end)
    |> Enum.sort_by(fn {_phrase, count} -> -count end)
    |> Enum.take(5)
    |> Enum.map(fn {phrase, _count} -> phrase end)
  end
  
  defp calculate_avg_word_length(string) do
    words = String.split(string, ~r/\s+/)
    if length(words) > 0 do
      total_length = Enum.sum(Enum.map(words, &String.length/1))
      total_length / length(words)
    else
      0.0
    end
  end
  
  defp count_punctuation(string) do
    string
    |> String.graphemes()
    |> Enum.count(&String.match?(&1, ~r/[[:punct:]]/))
  end
  
  defp count_digits(string) do
    string
    |> String.graphemes()
    |> Enum.count(&String.match?(&1, ~r/\d/))
  end
  
  defp calculate_uppercase_ratio(string) do
    letters = string
    |> String.graphemes()
    |> Enum.filter(&String.match?(&1, ~r/[[:alpha:]]/))
    
    if length(letters) > 0 do
      uppercase_count = Enum.count(letters, &String.match?(&1, ~r/[[:upper:]]/))
      uppercase_count / length(letters)
    else
      0.0
    end
  end
  
  defp find_cross_references(string) do
    # Find potential cross-references (e.g., "see section X", "refer to Y")
    ~r/(?:see|refer(?:s)?\s+to|reference|cf\.?)\s+([^,.]+)/i
    |> Regex.scan(string)
    |> Enum.map(&List.last/1)
  end
  
  defp find_repeated_phrases(string) do
    words = String.split(String.downcase(string), ~r/\s+/)
    
    # Find 3-word phrases that repeat
    phrases = for i <- 0..(length(words) - 3) do
      Enum.slice(words, i, 3) |> Enum.join(" ")
    end
    
    phrases
    |> Enum.frequencies()
    |> Enum.filter(fn {_phrase, count} -> count > 1 end)
    |> Enum.map(fn {phrase, count} -> %{phrase: phrase, count: count} end)
  end
  
  defp analyze_connections(string) do
    # Analyze how different parts of the text connect
    %{
      transition_words: count_transition_words(string),
      conjunctions: count_conjunctions(string),
      pronoun_references: count_pronouns(string)
    }
  end
  
  defp count_transition_words(string) do
    transitions = ~r/\b(?:however|therefore|moreover|furthermore|thus|hence|consequently|meanwhile|nevertheless)\b/i
    
    Regex.scan(transitions, string) |> length()
  end
  
  defp count_conjunctions(string) do
    conjunctions = ~r/\b(?:and|but|or|nor|for|yet|so)\b/i
    
    Regex.scan(conjunctions, string) |> length()
  end
  
  defp count_pronouns(string) do
    pronouns = ~r/\b(?:he|she|it|they|we|you|this|that|these|those)\b/i
    
    Regex.scan(pronouns, string) |> length()
  end
  
  defp detect_formatting_patterns(string) do
    %{
      list_items: Regex.scan(~r/^\s*[-*+•]\s+/m, string) |> length(),
      numbered_items: Regex.scan(~r/^\s*\d+[\.)]\s+/m, string) |> length(),
      quoted_sections: Regex.scan(~r/"[^"]+"|'[^']+'/, string) |> length(),
      code_snippets: Regex.scan(~r/`[^`]+`/, string) |> length()
    }
  end
  
  defp detect_linguistic_patterns(string) do
    sentences = String.split(string, ~r/[.!?]+\s*/)
    
    %{
      question_count: Enum.count(sentences, &String.ends_with?(&1, "?")),
      exclamation_count: Enum.count(sentences, &String.ends_with?(&1, "!")),
      average_complexity: calculate_avg_sentence_complexity(sentences),
      passive_voice_indicators: count_passive_indicators(string)
    }
  end
  
  defp calculate_avg_sentence_complexity(sentences) do
    if length(sentences) > 0 do
      complexities = Enum.map(sentences, fn sentence ->
        # Count commas, semicolons, and other complexity indicators
        String.graphemes(sentence)
        |> Enum.count(&String.match?(&1, ~r/[,;:()]/))
      end)
      
      Enum.sum(complexities) / length(sentences)
    else
      0.0
    end
  end
  
  defp count_passive_indicators(string) do
    # Simple passive voice detection
    passive_patterns = ~r/\b(?:was|were|been|being|is|are|am)\s+\w+ed\b/i
    
    Regex.scan(passive_patterns, string) |> length()
  end
  
  defp detect_text_patterns(string) do
    %{
      paragraph_structure: analyze_paragraph_structure(string),
      sentence_variety: calculate_sentence_variety(string),
      repetition_score: calculate_repetition_score(string)
    }
  end
  
  defp analyze_paragraph_structure(string) do
    paragraphs = String.split(string, ~r/\n\n+/)
    
    %{
      count: length(paragraphs),
      average_length: if(length(paragraphs) > 0, do: String.length(string) / length(paragraphs), else: 0),
      consistency: calculate_paragraph_consistency(paragraphs)
    }
  end
  
  defp calculate_paragraph_consistency(paragraphs) do
    lengths = Enum.map(paragraphs, &String.length/1)
    
    if length(lengths) > 1 do
      avg = Enum.sum(lengths) / length(lengths)
      variance = Enum.sum(Enum.map(lengths, fn l -> :math.pow(l - avg, 2) end)) / length(lengths)
      std_dev = :math.sqrt(variance)
      
      # Lower score means more consistent
      std_dev / avg
    else
      0.0
    end
  end
  
  defp calculate_sentence_variety(string) do
    sentences = String.split(string, ~r/[.!?]+\s*/)
    lengths = Enum.map(sentences, &length(String.split(&1, ~r/\s+/)))
    
    %{
      min_length: if(Enum.empty?(lengths), do: 0, else: Enum.min(lengths)),
      max_length: if(Enum.empty?(lengths), do: 0, else: Enum.max(lengths)),
      length_variance: calculate_variance(lengths)
    }
  end
  
  defp calculate_variance(numbers) do
    if length(numbers) > 0 do
      avg = Enum.sum(numbers) / length(numbers)
      Enum.sum(Enum.map(numbers, fn n -> :math.pow(n - avg, 2) end)) / length(numbers)
    else
      0.0
    end
  end
  
  defp calculate_repetition_score(string) do
    words = string
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(&(String.length(&1) > 3))
    
    if length(words) > 0 do
      unique_words = Enum.uniq(words)
      1.0 - (length(unique_words) / length(words))
    else
      0.0
    end
  end
end
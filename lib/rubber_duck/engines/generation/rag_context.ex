defmodule RubberDuck.Engines.Generation.RagContext do
  @moduledoc """
  Retrieval Augmented Generation (RAG) context management for code generation.
  
  This module handles semantic search, context retrieval, and ranking of relevant
  code snippets and patterns to improve code generation quality.
  
  ## Features
  
  - Semantic code search using embeddings
  - Project pattern extraction
  - Context ranking and filtering
  - Multi-source context aggregation
  - Caching for performance
  """
  
  require Logger
  
  @type context_item :: %{
    required(:type) => context_type(),
    required(:content) => String.t(),
    required(:source) => String.t(),
    required(:relevance) => float(),
    required(:metadata) => map()
  }
  
  @type context_type :: :code | :pattern | :documentation | :example | :import | :test
  
  @type search_options :: %{
    optional(:max_results) => integer(),
    optional(:min_relevance) => float(),
    optional(:include_tests) => boolean(),
    optional(:project_only) => boolean()
  }
  
  @doc """
  Search for similar code snippets based on a query.
  
  Uses semantic similarity to find relevant code from:
  - Project files
  - Generation history
  - Code pattern database
  - External examples
  """
  @spec search_similar_code(String.t(), atom(), search_options()) :: [context_item()]
  def search_similar_code(query, language, options \\ %{}) do
    max_results = Map.get(options, :max_results, 10)
    min_relevance = Map.get(options, :min_relevance, 0.5)
    
    # Generate embedding for query
    query_embedding = generate_embedding(query)
    
    # Search in different sources
    results = []
    
    # 1. Search project files
    project_results = if Map.get(options, :project_only, false) do
      search_project_files(query_embedding, language, options)
    else
      []
    end
    results = results ++ project_results
    
    # 2. Search pattern database
    pattern_results = search_pattern_database(query_embedding, language)
    results = results ++ pattern_results
    
    # 3. Search generation history
    history_results = search_generation_history(query_embedding, language)
    results = results ++ history_results
    
    # Rank and filter results
    results
    |> Enum.map(&add_relevance_score(&1, query_embedding))
    |> Enum.filter(fn item -> item.relevance >= min_relevance end)
    |> Enum.sort_by(& &1.relevance, :desc)
    |> Enum.take(max_results)
    |> enhance_with_metadata()
  end
  
  @doc """
  Extract patterns from project files for context.
  
  Analyzes project structure to find:
  - Common patterns
  - Coding conventions
  - Module structures
  - Import patterns
  """
  @spec extract_project_patterns(map(), atom()) :: [context_item()]
  def extract_project_patterns(project_info, language) do
    patterns = []
    
    # Extract module patterns
    module_patterns = extract_module_patterns(project_info)
    patterns = patterns ++ module_patterns
    
    # Extract function patterns
    function_patterns = extract_function_patterns(project_info, language)
    patterns = patterns ++ function_patterns
    
    # Extract test patterns if available
    test_patterns = extract_test_patterns(project_info, language)
    patterns = patterns ++ test_patterns
    
    patterns
  end
  
  @doc """
  Build context from multiple sources.
  
  Aggregates context from:
  - Similar code search results
  - Project patterns
  - User examples
  - Language idioms
  """
  @spec build_context(String.t(), atom(), map()) :: map()
  def build_context(query, language, sources) do
    # Aggregate all context items
    all_items = []
    
    # Add similar code
    if Map.has_key?(sources, :similar_code) do
      all_items = all_items ++ sources.similar_code
    end
    
    # Add project patterns
    if Map.has_key?(sources, :project_patterns) do
      all_items = all_items ++ sources.project_patterns
    end
    
    # Add user examples
    if Map.has_key?(sources, :examples) do
      examples = Enum.map(sources.examples, &format_example/1)
      all_items = all_items ++ examples
    end
    
    # Remove duplicates and rank
    unique_items = deduplicate_context_items(all_items)
    ranked_items = rank_context_items(unique_items, query)
    
    %{
      items: ranked_items,
      summary: summarize_context(ranked_items),
      metadata: %{
        total_items: length(all_items),
        unique_items: length(unique_items),
        sources: Map.keys(sources)
      }
    }
  end
  
  @doc """
  Rank context items by relevance to query.
  """
  @spec rank_context_items([context_item()], String.t()) :: [context_item()]
  def rank_context_items(items, query) do
    query_keywords = extract_keywords(query)
    
    items
    |> Enum.map(fn item ->
      score = calculate_item_score(item, query_keywords)
      Map.put(item, :rank_score, score)
    end)
    |> Enum.sort_by(& &1.rank_score, :desc)
  end
  
  # Private functions
  
  defp generate_embedding(text) do
    # In a real implementation, this would use an embedding model
    # For now, we'll use a simple keyword-based representation
    text
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.frequencies()
  end
  
  defp search_project_files(query_embedding, language, options) do
    # In a real implementation, this would search actual project files
    # For now, return mock results
    [
      %{
        type: :code,
        content: "def example_function(params) do\n  # Project code\nend",
        source: "lib/example.ex",
        metadata: %{language: language}
      }
    ]
  end
  
  defp search_pattern_database(query_embedding, language) do
    # Search pre-defined patterns
    patterns = get_language_patterns(language)
    
    patterns
    |> Enum.map(fn pattern ->
      %{
        type: :pattern,
        content: pattern.code,
        source: "pattern_db",
        metadata: %{
          description: pattern.description,
          tags: pattern.tags
        }
      }
    end)
    |> Enum.filter(&pattern_matches?(&1, query_embedding))
  end
  
  defp get_language_patterns(:elixir) do
    [
      %{
        code: """
        def handle_call({:get, key}, _from, state) do
          value = Map.get(state, key)
          {:reply, value, state}
        end
        """,
        description: "GenServer handle_call pattern",
        tags: ["genserver", "handle_call", "get"]
      },
      %{
        code: """
        def create(attrs) do
          %__MODULE__{}
          |> changeset(attrs)
          |> Repo.insert()
        end
        """,
        description: "Ecto create pattern",
        tags: ["ecto", "create", "database"]
      },
      %{
        code: """
        case File.read(path) do
          {:ok, content} -> process_content(content)
          {:error, _reason} -> {:error, "Failed to read file"}
        end
        """,
        description: "File reading with error handling",
        tags: ["file", "error", "handling"]
      }
    ]
  end
  
  defp get_language_patterns(_), do: []
  
  defp pattern_matches?(pattern, query_embedding) do
    # Check if pattern is relevant to query
    pattern_keywords = extract_pattern_keywords(pattern)
    
    Enum.any?(Map.keys(query_embedding), fn keyword ->
      keyword in pattern_keywords
    end)
  end
  
  defp extract_pattern_keywords(pattern) do
    tags = get_in(pattern, [:metadata, :tags]) || []
    
    content_keywords = pattern.content
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(&(String.length(&1) > 3))
    
    tags ++ content_keywords
  end
  
  defp search_generation_history(_query_embedding, _language) do
    # In a real implementation, this would search actual history
    []
  end
  
  defp add_relevance_score(item, query_embedding) do
    # Calculate semantic similarity
    item_embedding = generate_embedding(item.content)
    
    similarity = calculate_similarity(query_embedding, item_embedding)
    
    Map.put(item, :relevance, similarity)
  end
  
  defp calculate_similarity(embedding1, embedding2) do
    # Jaccard similarity for keyword embeddings
    keys1 = MapSet.new(Map.keys(embedding1))
    keys2 = MapSet.new(Map.keys(embedding2))
    
    intersection = MapSet.intersection(keys1, keys2)
    union = MapSet.union(keys1, keys2)
    
    if MapSet.size(union) == 0 do
      0.0
    else
      MapSet.size(intersection) / MapSet.size(union)
    end
  end
  
  defp enhance_with_metadata(items) do
    Enum.map(items, fn item ->
      enhanced_metadata = Map.merge(item.metadata || %{}, %{
        char_count: String.length(item.content),
        line_count: count_lines(item.content),
        has_comments: has_comments?(item.content),
        complexity: estimate_complexity(item.content)
      })
      
      Map.put(item, :metadata, enhanced_metadata)
    end)
  end
  
  defp count_lines(content) do
    content
    |> String.split("\n")
    |> length()
  end
  
  defp has_comments?(content) do
    String.contains?(content, "#") or 
    String.contains?(content, "//") or
    String.contains?(content, "/*")
  end
  
  defp estimate_complexity(content) do
    # Simple complexity estimation based on nesting and conditionals
    nesting_level = estimate_nesting(content)
    conditional_count = count_conditionals(content)
    
    nesting_level + conditional_count
  end
  
  defp estimate_nesting(content) do
    # Count indentation levels
    content
    |> String.split("\n")
    |> Enum.map(&count_leading_spaces/1)
    |> Enum.max(fn -> 0 end)
    |> div(2)  # Assume 2-space indentation
  end
  
  defp count_leading_spaces(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, spaces] -> String.length(spaces)
      _ -> 0
    end
  end
  
  defp count_conditionals(content) do
    conditionals = ~r/\b(if|case|cond|when|else|elif|switch)\b/
    
    Regex.scan(conditionals, content)
    |> length()
  end
  
  defp extract_module_patterns(project_info) do
    # Extract common module structures
    modules = Map.get(project_info, :modules, [])
    
    modules
    |> Enum.map(fn module_info ->
      %{
        type: :pattern,
        content: "defmodule #{module_info[:name]} do\n  # Module structure\nend",
        source: "project_analysis",
        metadata: %{
          module_name: module_info[:name],
          pattern_type: :module_structure
        }
      }
    end)
  end
  
  defp extract_function_patterns(project_info, language) do
    # Extract common function patterns
    functions = Map.get(project_info, :functions, [])
    
    case language do
      :elixir -> extract_elixir_function_patterns(functions)
      _ -> []
    end
  end
  
  defp extract_elixir_function_patterns(functions) do
    functions
    |> Enum.group_by(&function_category/1)
    |> Enum.flat_map(fn {category, funcs} ->
      if length(funcs) >= 2 do
        [generate_function_pattern(category, funcs)]
      else
        []
      end
    end)
  end
  
  defp function_category(func_info) do
    name = func_info[:name] || ""
    
    cond do
      String.starts_with?(name, "get_") -> :getter
      String.starts_with?(name, "set_") -> :setter
      String.starts_with?(name, "create_") -> :creator
      String.starts_with?(name, "update_") -> :updater
      String.starts_with?(name, "delete_") -> :deleter
      String.ends_with?(name, "?") -> :predicate
      true -> :general
    end
  end
  
  defp generate_function_pattern(category, functions) do
    pattern_code = case category do
      :getter ->
        """
        def get_resource(id) do
          # Common getter pattern
          case fetch_resource(id) do
            {:ok, resource} -> {:ok, resource}
            {:error, :not_found} -> {:error, "Resource not found"}
          end
        end
        """
        
      :creator ->
        """
        def create_resource(attrs) do
          # Common creation pattern
          with {:ok, valid_attrs} <- validate(attrs),
               {:ok, resource} <- insert(valid_attrs) do
            {:ok, resource}
          end
        end
        """
        
      _ ->
        "# Pattern for #{category} functions"
    end
    
    %{
      type: :pattern,
      content: pattern_code,
      source: "project_patterns",
      metadata: %{
        category: category,
        example_count: length(functions)
      }
    }
  end
  
  defp extract_test_patterns(project_info, :elixir) do
    # Extract test patterns if test files are analyzed
    test_modules = Map.get(project_info, :test_modules, [])
    
    if length(test_modules) > 0 do
      [
        %{
          type: :test,
          content: """
          describe "function_name/arity" do
            test "successful case" do
              assert function_name(valid_input) == expected_output
            end
            
            test "error case" do
              assert {:error, _} = function_name(invalid_input)
            end
          end
          """,
          source: "test_patterns",
          metadata: %{pattern_type: :test_structure}
        }
      ]
    else
      []
    end
  end
  
  defp extract_test_patterns(_, _), do: []
  
  defp format_example(example) do
    %{
      type: :example,
      content: example[:code] || "",
      source: "user_provided",
      metadata: %{
        description: example[:description],
        tags: example[:tags] || []
      }
    }
  end
  
  defp deduplicate_context_items(items) do
    # Remove duplicate content
    items
    |> Enum.uniq_by(&content_signature/1)
  end
  
  defp content_signature(item) do
    # Create a signature for deduplication
    content_normalized = item.content
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    
    {item.type, content_normalized}
  end
  
  defp extract_keywords(text) do
    text
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.uniq()
  end
  
  defp calculate_item_score(item, query_keywords) do
    # Multi-factor scoring
    base_score = Map.get(item, :relevance, 0.5)
    
    # Keyword overlap
    item_keywords = extract_keywords(item.content)
    overlap = length(Enum.filter(query_keywords, &(&1 in item_keywords)))
    keyword_score = overlap / max(length(query_keywords), 1)
    
    # Type preference
    type_score = case item.type do
      :code -> 1.0
      :pattern -> 0.9
      :example -> 0.8
      :test -> 0.7
      _ -> 0.5
    end
    
    # Recency (if available)
    recency_score = calculate_recency_score(item)
    
    # Weighted average
    (base_score * 0.4) + (keyword_score * 0.3) + (type_score * 0.2) + (recency_score * 0.1)
  end
  
  defp calculate_recency_score(item) do
    case get_in(item, [:metadata, :timestamp]) do
      nil -> 0.5
      timestamp ->
        # Score based on age (newer is better)
        age_hours = DateTime.diff(DateTime.utc_now(), timestamp, :hour)
        max(0.0, 1.0 - (age_hours / 168.0))  # Decay over a week
    end
  end
  
  defp summarize_context(items) do
    type_counts = items
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, items} -> {type, length(items)} end)
    |> Map.new()
    
    %{
      total_items: length(items),
      type_distribution: type_counts,
      average_relevance: calculate_average_relevance(items),
      primary_sources: get_primary_sources(items)
    }
  end
  
  defp calculate_average_relevance(items) do
    if length(items) == 0 do
      0.0
    else
      total = Enum.sum(Enum.map(items, &(&1.relevance || 0.0)))
      total / length(items)
    end
  end
  
  defp get_primary_sources(items) do
    items
    |> Enum.map(& &1.source)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_source, count} -> -count end)
    |> Enum.take(3)
    |> Enum.map(fn {source, _count} -> source end)
  end
end
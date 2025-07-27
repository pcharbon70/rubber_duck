# Keyword-Based Filtering System for RubberDuck Instructions

## Overview

This document describes the implementation of a keyword-based filtering system for the RubberDuck instruction files. The system allows instructions to be conditionally included based on keyword matching against a provided text string, enabling context-aware instruction loading.

## 1. Extended Metadata Structure

The YAML frontmatter now supports keyword filtering configuration:

```yaml
---
# Existing metadata fields...
priority: high
type: auto
tags: [elixir, phoenix, testing]

# New keyword filtering configuration
keyword_filter:
  keywords: ["authentication", "oauth", "jwt", "security", "login"]
  match_type: "any"     # Options: "any", "all", "some"
  match_count: 2        # Only used when match_type is "some"
  case_sensitive: false # Optional, defaults to false
---
```

### Keyword Filter Options

- **keywords**: List of keywords to match against
- **match_type**: 
  - `"any"`: Include if ANY keyword is found
  - `"all"`: Include if ALL keywords are found
  - `"some"`: Include if at least `match_count` keywords are found
- **match_count**: Number of keywords required when using `"some"` match type
- **case_sensitive**: Whether matching should be case-sensitive (default: false)

## 2. Implementation

### 2.1 Update Metadata Validation

Update `lib/rubber_duck/instructions/file_manager.ex`:

```elixir
defmodule RubberDuck.Instructions.FileManager do
  # Add to the existing module

  @doc """
  Validates keyword filter configuration in metadata
  """
  def validate_keyword_filter(nil), do: nil
  
  def validate_keyword_filter(filter) when is_map(filter) do
    %{
      "keywords" => validate_keywords(filter["keywords"]),
      "match_type" => validate_match_type(filter["match_type"]),
      "match_count" => validate_match_count(filter["match_count"], filter["match_type"]),
      "case_sensitive" => validate_boolean(filter["case_sensitive"], false)
    }
  end
  
  def validate_keyword_filter(_), do: nil

  defp validate_keywords(keywords) when is_list(keywords) do
    keywords
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(50) # Limit to 50 keywords
  end
  defp validate_keywords(_), do: []

  defp validate_match_type(type) when type in ["any", "all", "some"], do: type
  defp validate_match_type(_), do: "any"

  defp validate_match_count(count, "some") when is_integer(count) and count > 0, do: count
  defp validate_match_count(_, "some"), do: 1
  defp validate_match_count(_, _), do: nil

  defp validate_boolean(true, _), do: true
  defp validate_boolean(false, _), do: false
  defp validate_boolean(_, default), do: default

  # Update the existing validate_metadata function
  defp validate_metadata(metadata) do
    base_metadata = %{
      "priority" => "normal",
      "type" => "auto", 
      "tags" => [],
      "keyword_filter" => nil
    }
    
    metadata
    |> Map.merge(base_metadata, fn _key, new_val, _default -> new_val end)
    |> Map.update("priority", "normal", &validate_priority/1)
    |> Map.update("type", "auto", &validate_rule_type/1)
    |> Map.update("tags", [], &validate_tags/1)
    |> Map.update("keyword_filter", nil, &validate_keyword_filter/1)
  end
end
```

### 2.2 Create KeywordMatcher Module

Create `lib/rubber_duck/instructions/keyword_matcher.ex`:

```elixir
defmodule RubberDuck.Instructions.KeywordMatcher do
  @moduledoc """
  Handles keyword matching logic for instruction filtering
  """

  @doc """
  Checks if an instruction file should be included based on keyword filtering.
  Returns true if the file should be included, false otherwise.
  """
  @spec matches?(map(), String.t() | nil) :: boolean()
  def matches?(%{"keyword_filter" => nil}, _context_text), do: true
  def matches?(%{"keyword_filter" => filter}, nil), do: false
  def matches?(%{"keyword_filter" => filter}, ""), do: false
  
  def matches?(%{"keyword_filter" => filter}, context_text) when is_binary(context_text) do
    keywords = filter["keywords"] || []
    match_type = filter["match_type"] || "any"
    match_count = filter["match_count"]
    case_sensitive = filter["case_sensitive"] || false
    
    # Prepare text and keywords for matching
    prepared_text = prepare_text(context_text, case_sensitive)
    prepared_keywords = prepare_keywords(keywords, case_sensitive)
    
    # Apply matching logic
    case match_type do
      "any" -> match_any?(prepared_text, prepared_keywords)
      "all" -> match_all?(prepared_text, prepared_keywords)
      "some" -> match_some?(prepared_text, prepared_keywords, match_count || 1)
      _ -> true # Default to including the file
    end
  end
  
  def matches?(_, _), do: true

  @doc """
  Prepares text for matching based on case sensitivity
  """
  defp prepare_text(text, false), do: String.downcase(text)
  defp prepare_text(text, true), do: text

  @doc """
  Prepares keywords for matching based on case sensitivity
  """
  defp prepare_keywords(keywords, false) do
    Enum.map(keywords, &String.downcase/1)
  end
  defp prepare_keywords(keywords, true), do: keywords

  @doc """
  Checks if ANY keyword is found in the text
  """
  defp match_any?(text, keywords) do
    Enum.any?(keywords, &String.contains?(text, &1))
  end

  @doc """
  Checks if ALL keywords are found in the text
  """
  defp match_all?(text, keywords) do
    Enum.all?(keywords, &String.contains?(text, &1))
  end

  @doc """
  Checks if at least `count` keywords are found in the text
  """
  defp match_some?(text, keywords, count) do
    matched_count = 
      keywords
      |> Enum.filter(&String.contains?(text, &1))
      |> Enum.count()
    
    matched_count >= count
  end

  @doc """
  Analyzes keyword matching for debugging purposes
  """
  @spec analyze_matching(map(), String.t()) :: map()
  def analyze_matching(%{"keyword_filter" => filter}, context_text) when is_map(filter) and is_binary(context_text) do
    keywords = filter["keywords"] || []
    case_sensitive = filter["case_sensitive"] || false
    
    prepared_text = prepare_text(context_text, case_sensitive)
    prepared_keywords = prepare_keywords(keywords, case_sensitive)
    
    keyword_matches = 
      keywords
      |> Enum.zip(prepared_keywords)
      |> Enum.map(fn {original, prepared} ->
        {original, String.contains?(prepared_text, prepared)}
      end)
      |> Enum.into(%{})
    
    %{
      total_keywords: length(keywords),
      matched_keywords: Enum.count(keyword_matches, fn {_, matched} -> matched end),
      keyword_matches: keyword_matches,
      match_type: filter["match_type"] || "any",
      match_count: filter["match_count"],
      would_match: matches?(%{"keyword_filter" => filter}, context_text)
    }
  end
  
  def analyze_matching(_, _), do: %{error: "Invalid metadata or context text"}
end
```

### 2.3 Update HierarchicalLoader

Modify `lib/rubber_duck/instructions/hierarchical_loader.ex`:

```elixir
defmodule RubberDuck.Instructions.HierarchicalLoader do
  alias RubberDuck.Instructions.KeywordMatcher
  
  @doc """
  Loads instructions with optional keyword filtering based on context text.
  
  Options:
    - :context_text - Text to match against keyword filters
    - :skip_keyword_filtering - Set to true to disable keyword filtering
    - All existing options...
  """
  def load_instructions(root_path \\ ".", opts \\ []) do
    context_text = Keyword.get(opts, :context_text)
    skip_filtering = Keyword.get(opts, :skip_keyword_filtering, false)
    
    with {:ok, discovered_files} <- discover_all_files(root_path, opts),
         {:ok, parsed_files} <- parse_all_files(discovered_files),
         {:ok, filtered_files} <- apply_keyword_filtering(parsed_files, context_text, skip_filtering),
         {:ok, resolved_files, conflicts} <- resolve_conflicts(filtered_files),
         {:ok, loading_result} <- load_into_registry(resolved_files) do
      
      # Add filtering stats to the result
      result = format_loading_result(loading_result, conflicts)
      result_with_stats = add_filtering_stats(result, parsed_files, filtered_files)
      
      {:ok, result_with_stats}
    end
  end

  @doc """
  Applies keyword filtering to discovered instruction files
  """
  defp apply_keyword_filtering(files, _context_text, true), do: {:ok, files}
  defp apply_keyword_filtering(files, nil, false), do: filter_without_context(files)
  defp apply_keyword_filtering(files, context_text, false) when is_binary(context_text) do
    filtered_files = 
      files
      |> Enum.filter(fn file ->
        KeywordMatcher.matches?(file.metadata, context_text)
      end)
    
    {:ok, filtered_files}
  end

  @doc """
  Filters files when no context is provided - only includes files without keyword filters
  """
  defp filter_without_context(files) do
    filtered_files = 
      files
      |> Enum.filter(fn file ->
        # Include files that don't have keyword filters
        is_nil(file.metadata["keyword_filter"])
      end)
    
    {:ok, filtered_files}
  end

  @doc """
  Adds filtering statistics to the loading result
  """
  defp add_filtering_stats(result, parsed_files, filtered_files) do
    total_with_filters = 
      parsed_files
      |> Enum.count(fn file -> 
        not is_nil(file.metadata["keyword_filter"])
      end)
    
    filtered_out_count = length(parsed_files) - length(filtered_files)
    
    stats = Map.put(result.stats, :keyword_filtering, %{
      total_with_filters: total_with_filters,
      filtered_out: filtered_out_count,
      included: length(filtered_files)
    })
    
    Map.put(result, :stats, stats)
  end

  @doc """
  Analyzes keyword filtering without actually loading instructions.
  Useful for debugging and testing.
  """
  def analyze_keyword_filtering(root_path, context_text, opts \\ []) do
    with {:ok, discovered_files} <- discover_all_files(root_path, opts),
         {:ok, parsed_files} <- parse_all_files(discovered_files) do
      
      analysis = 
        parsed_files
        |> Enum.map(fn file ->
          keyword_filter = file.metadata["keyword_filter"]
          
          if keyword_filter do
            matching_analysis = KeywordMatcher.analyze_matching(file.metadata, context_text)
            
            %{
              file: file.path,
              priority: file.priority,
              keyword_filter: keyword_filter,
              matching_analysis: matching_analysis
            }
          else
            %{
              file: file.path,
              priority: file.priority,
              keyword_filter: nil,
              always_included: true
            }
          end
        end)
      
      {:ok, analysis}
    end
  end
end
```

## 3. Usage Examples

### 3.1 Instruction Files with Keyword Filters

#### Authentication Instructions (`auth_instructions.md`)

```markdown
---
priority: high
type: auto
tags: [authentication, security]
keyword_filter:
  keywords: ["login", "authentication", "oauth", "jwt", "auth", "security"]
  match_type: "any"
  case_sensitive: false
---

# Authentication & Security Instructions

## OAuth Implementation
- Use OAuth 2.0 for third-party authentication
- Implement PKCE for public clients
- Store tokens securely

## JWT Guidelines
- Use short-lived access tokens (15 minutes)
- Implement refresh token rotation
- Include minimal claims in tokens
```

#### Frontend Instructions (`frontend_instructions.md`)

```markdown
---
priority: normal
type: auto
tags: [frontend, react, typescript]
keyword_filter:
  keywords: ["react", "typescript", "frontend", "component", "ui", "jsx"]
  match_type: "all"
  case_sensitive: false
---

# Frontend Development Instructions

## React Component Guidelines
- Use functional components with hooks
- Implement proper TypeScript types
- Follow the component folder structure
```

#### Testing Instructions (`testing_instructions.md`)

```markdown
---
priority: high
type: agent
tags: [testing, quality]
keyword_filter:
  keywords: ["test", "testing", "spec", "unit", "integration", "e2e", "mock", "stub"]
  match_type: "some"
  match_count: 2
  case_sensitive: false
---

# Testing Guidelines

## Unit Testing
- Write tests for all business logic
- Use descriptive test names
- Mock external dependencies

## Integration Testing
- Test API endpoints
- Test database interactions
- Use test database
```

### 3.2 Loading Instructions with Context

```elixir
# Load instructions for authentication-related work
{:ok, result} = HierarchicalLoader.load_instructions("/path/to/project", 
  context_text: "I need to implement user login with OAuth"
)
# Will include: auth_instructions.md
# Will exclude: frontend_instructions.md, testing_instructions.md

# Load instructions for frontend development
{:ok, result} = HierarchicalLoader.load_instructions("/path/to/project",
  context_text: "Create a React TypeScript component for the frontend UI"
)
# Will include: frontend_instructions.md
# Will exclude: auth_instructions.md, testing_instructions.md

# Load instructions for testing
{:ok, result} = HierarchicalLoader.load_instructions("/path/to/project",
  context_text: "Write unit tests with mocks for the service"
)
# Will include: testing_instructions.md (matches "unit" and "mock")
# Will exclude: auth_instructions.md, frontend_instructions.md

# Load all instructions without filtering
{:ok, result} = HierarchicalLoader.load_instructions("/path/to/project",
  skip_keyword_filtering: true
)
# Will include: ALL instruction files
```

### 3.3 Analyzing Keyword Filtering

```elixir
# Analyze what would be loaded without actually loading
{:ok, analysis} = HierarchicalLoader.analyze_keyword_filtering(
  "/path/to/project",
  "implement OAuth login system"
)

Enum.each(analysis, fn item ->
  IO.puts("File: #{item.file}")
  
  if item.keyword_filter do
    IO.puts("  Match Type: #{item.keyword_filter["match_type"]}")
    IO.puts("  Would Match: #{item.matching_analysis.would_match}")
    IO.puts("  Matched Keywords: #{item.matching_analysis.matched_keywords}/#{item.matching_analysis.total_keywords}")
  else
    IO.puts("  Always Included: true")
  end
end)
```

## 4. Integration with Conversation System

### 4.1 Conversation Context Loader

```elixir
defmodule RubberDuck.Conversation.InstructionLoader do
  alias RubberDuck.Instructions.HierarchicalLoader
  
  @doc """
  Loads instructions based on the current conversation context
  """
  def load_contextual_instructions(conversation_id, message_text, opts \\ []) do
    # Build comprehensive context
    context = build_conversation_context(conversation_id, message_text, opts)
    
    # Load instructions filtered by context
    case HierarchicalLoader.load_instructions(".", context_text: context) do
      {:ok, result} ->
        Logger.info("Loaded #{length(result.loaded)} instructions for conversation #{conversation_id}")
        Logger.debug("Keyword filtering stats: #{inspect(result.stats.keyword_filtering)}")
        
        {:ok, result.loaded}
        
      {:error, reason} ->
        Logger.error("Failed to load instructions: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Builds comprehensive context from conversation history and current message
  """
  defp build_conversation_context(conversation_id, current_message, opts) do
    include_history = Keyword.get(opts, :include_history, true)
    history_limit = Keyword.get(opts, :history_limit, 5)
    
    context_parts = [current_message]
    
    # Add recent conversation history if requested
    if include_history do
      recent_messages = get_recent_messages(conversation_id, history_limit)
      context_parts = context_parts ++ recent_messages
    end
    
    # Add file context if available
    if file_context = Keyword.get(opts, :file_context) do
      context_parts = ["Working on file: #{file_context}" | context_parts]
    end
    
    # Join all context parts
    Enum.join(context_parts, " ")
  end
  
  defp get_recent_messages(conversation_id, limit) do
    # Fetch recent messages from conversation
    # This is a placeholder - implement based on your conversation storage
    []
  end
end
```

### 4.2 Engine Integration

```elixir
defmodule RubberDuck.Engines.InstructionAwareEngine do
  @doc """
  Executes engine with context-aware instructions
  """
  def execute_with_instructions(engine, input, conversation_context) do
    # Load relevant instructions based on context
    {:ok, instructions} = RubberDuck.Conversation.InstructionLoader.load_contextual_instructions(
      input.conversation_id,
      input.message,
      file_context: input.current_file
    )
    
    # Add instructions to engine input
    enhanced_input = Map.put(input, :contextual_instructions, instructions)
    
    # Execute engine with enhanced input
    engine.execute(enhanced_input)
  end
end
```

## 5. Testing

### 5.1 KeywordMatcher Tests

```elixir
defmodule RubberDuck.Instructions.KeywordMatcherTest do
  use ExUnit.Case
  alias RubberDuck.Instructions.KeywordMatcher

  describe "matches?/2" do
    test "returns true for files without keyword filters" do
      metadata = %{"priority" => "high", "type" => "auto"}
      assert KeywordMatcher.matches?(metadata, "any text")
      assert KeywordMatcher.matches?(metadata, nil)
    end

    test "returns false when no context text is provided but filter exists" do
      metadata = %{
        "keyword_filter" => %{
          "keywords" => ["test"],
          "match_type" => "any"
        }
      }
      refute KeywordMatcher.matches?(metadata, nil)
      refute KeywordMatcher.matches?(metadata, "")
    end

    test "match_type: any - matches if any keyword is found" do
      metadata = %{
        "keyword_filter" => %{
          "keywords" => ["auth", "login", "security"],
          "match_type" => "any",
          "case_sensitive" => false
        }
      }
      
      assert KeywordMatcher.matches?(metadata, "implement login system")
      assert KeywordMatcher.matches?(metadata, "add security headers")
      assert KeywordMatcher.matches?(metadata, "AUTH system") # case insensitive
      refute KeywordMatcher.matches?(metadata, "database optimization")
    end

    test "match_type: all - matches only if all keywords are found" do
      metadata = %{
        "keyword_filter" => %{
          "keywords" => ["react", "typescript", "component"],
          "match_type" => "all",
          "case_sensitive" => false
        }
      }
      
      assert KeywordMatcher.matches?(metadata, "create react typescript component")
      assert KeywordMatcher.matches?(metadata, "React Component in TypeScript") # case insensitive
      refute KeywordMatcher.matches?(metadata, "react component without typescript")
      refute KeywordMatcher.matches?(metadata, "vue typescript component")
    end

    test "match_type: some - matches if threshold is met" do
      metadata = %{
        "keyword_filter" => %{
          "keywords" => ["test", "spec", "mock", "unit", "integration"],
          "match_type" => "some",
          "match_count" => 2,
          "case_sensitive" => false
        }
      }
      
      assert KeywordMatcher.matches?(metadata, "write unit test") # 2 matches
      assert KeywordMatcher.matches?(metadata, "create test with mock data") # 2 matches
      assert KeywordMatcher.matches?(metadata, "integration test spec") # 3 matches
      refute KeywordMatcher.matches?(metadata, "just a test") # only 1 match
      refute KeywordMatcher.matches?(metadata, "production code") # 0 matches
    end

    test "case sensitive matching" do
      metadata = %{
        "keyword_filter" => %{
          "keywords" => ["OAuth", "JWT"],
          "match_type" => "any",
          "case_sensitive" => true
        }
      }
      
      assert KeywordMatcher.matches?(metadata, "implement OAuth flow")
      assert KeywordMatcher.matches?(metadata, "use JWT tokens")
      refute KeywordMatcher.matches?(metadata, "implement oauth flow")
      refute KeywordMatcher.matches?(metadata, "use jwt tokens")
    end

    test "empty keywords list" do
      metadata = %{
        "keyword_filter" => %{
          "keywords" => [],
          "match_type" => "any"
        }
      }
      
      refute KeywordMatcher.matches?(metadata, "any text")
    end
  end

  describe "analyze_matching/2" do
    test "provides detailed matching analysis" do
      metadata = %{
        "keyword_filter" => %{
          "keywords" => ["auth", "login", "security", "oauth"],
          "match_type" => "any"
        }
      }
      
      analysis = KeywordMatcher.analyze_matching(metadata, "implement login and oauth system")
      
      assert analysis.total_keywords == 4
      assert analysis.matched_keywords == 2
      assert analysis.keyword_matches["login"] == true
      assert analysis.keyword_matches["oauth"] == true
      assert analysis.keyword_matches["auth"] == false
      assert analysis.keyword_matches["security"] == false
      assert analysis.would_match == true
    end

    test "handles invalid input gracefully" do
      analysis = KeywordMatcher.analyze_matching(%{}, "text")
      assert analysis == %{error: "Invalid metadata or context text"}
      
      analysis = KeywordMatcher.analyze_matching(%{"keyword_filter" => %{}}, nil)
      assert analysis == %{error: "Invalid metadata or context text"}
    end
  end
end
```

### 5.2 Integration Tests

```elixir
defmodule RubberDuck.Instructions.KeywordFilteringIntegrationTest do
  use ExUnit.Case
  
  setup do
    # Create temporary test files
    test_dir = Path.join(System.tmp_dir!(), "keyword_test_#{:rand.uniform(10000)}")
    File.mkdir_p!(test_dir)
    
    # Auth instructions with keyword filter
    auth_content = """
    ---
    priority: high
    keyword_filter:
      keywords: ["auth", "login", "oauth"]
      match_type: "any"
    ---
    # Auth Instructions
    """
    File.write!(Path.join(test_dir, "auth.md"), auth_content)
    
    # General instructions without keyword filter
    general_content = """
    ---
    priority: normal
    ---
    # General Instructions
    """
    File.write!(Path.join(test_dir, "general.md"), general_content)
    
    on_exit(fn -> File.rm_rf!(test_dir) end)
    
    {:ok, test_dir: test_dir}
  end
  
  test "loads only matching instructions based on context", %{test_dir: test_dir} do
    # Load with auth context
    {:ok, result} = HierarchicalLoader.load_instructions(test_dir,
      context_text: "implement login system"
    )
    
    loaded_files = Enum.map(result.loaded, & &1.path)
    assert "auth.md" in loaded_files
    assert "general.md" in loaded_files # Always included (no filter)
    
    # Load with non-matching context
    {:ok, result} = HierarchicalLoader.load_instructions(test_dir,
      context_text: "database optimization"
    )
    
    loaded_files = Enum.map(result.loaded, & &1.path)
    refute "auth.md" in loaded_files # Filtered out
    assert "general.md" in loaded_files # Always included
  end
  
  test "skip filtering loads all files", %{test_dir: test_dir} do
    {:ok, result} = HierarchicalLoader.load_instructions(test_dir,
      skip_keyword_filtering: true
    )
    
    assert length(result.loaded) == 2
  end
  
  test "filtering stats are included in result", %{test_dir: test_dir} do
    {:ok, result} = HierarchicalLoader.load_instructions(test_dir,
      context_text: "some text"
    )
    
    assert result.stats.keyword_filtering.total_with_filters == 1
    assert result.stats.keyword_filtering.filtered_out == 1
    assert result.stats.keyword_filtering.included == 1
  end
end
```

## 6. Configuration

Add to your application configuration:

```elixir
# config/config.exs
config :rubber_duck, :instructions,
  # Existing configuration...
  keyword_filtering: [
    enabled: true,
    default_match_type: "any",
    max_keywords_per_filter: 50,
    case_sensitive_default: false
  ]
```

## 7. Performance Considerations

1. **Keyword Matching Performance**: The current implementation uses `String.contains?/2` which is efficient for small to medium text sizes. For very large contexts, consider using more efficient text search algorithms.

2. **Caching**: Consider caching the filtering results when the same context is used multiple times:

```elixir
defmodule RubberDuck.Instructions.FilterCache do
  use GenServer
  
  def get_or_compute(context_text, files, fun) do
    cache_key = :crypto.hash(:sha256, context_text) |> Base.encode16()
    
    case :ets.lookup(@table, cache_key) do
      [{^cache_key, result}] -> result
      [] ->
        result = fun.(files)
        :ets.insert(@table, {cache_key, result})
        result
    end
  end
end
```

3. **Parallel Processing**: For large numbers of files, consider parallel filtering:

```elixir
defp apply_keyword_filtering_parallel(files, context_text, _skip) do
  filtered_files = 
    files
    |> Task.async_stream(fn file ->
      if KeywordMatcher.matches?(file.metadata, context_text) do
        {:include, file}
      else
        {:exclude, file}
      end
    end)
    |> Enum.reduce([], fn
      {:ok, {:include, file}}, acc -> [file | acc]
      _, acc -> acc
    end)
    |> Enum.reverse()
  
  {:ok, filtered_files}
end
```

## 8. Future Enhancements

1. **Regular Expression Support**: Allow regex patterns in addition to simple keywords
2. **Semantic Matching**: Use embeddings for semantic similarity matching
3. **Context History**: Consider multiple messages in conversation history
4. **Machine Learning**: Learn which instructions are most relevant based on usage
5. **Performance Optimization**: Implement trie-based keyword matching for better performance

## Conclusion

This keyword filtering system provides a flexible and powerful way to make instruction loading context-aware. By using metadata-based configuration and supporting multiple matching strategies, it allows for fine-grained control over when instructions are included in the AI assistant's context.

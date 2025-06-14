defmodule RubberDuck.ILP.Semantic.Chunker do
  @moduledoc """
  Hierarchical semantic chunking with code-aware boundaries and sliding window optimization.
  Implements intelligent code segmentation that respects language semantics and provides
  configurable overlap for context preservation.
  """
  use GenServer
  require Logger

  alias RubberDuck.ILP.AST.Node
  alias RubberDuck.ILP.Parser.Abstraction

  defstruct [
    :chunk_strategy,
    :window_size,
    :overlap_ratio,
    :min_chunk_size,
    :max_chunk_size,
    :language_strategies,
    :chunk_cache,
    :metrics
  ]

  @default_window_size 2048
  @default_overlap_ratio 0.1
  @default_min_chunk_size 256
  @default_max_chunk_size 4096

  @chunk_strategies [:semantic, :syntactic, :sliding_window, :hybrid]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Chunks source code into semantically coherent segments.
  """
  def chunk_code(source_code, language, opts \\ []) do
    GenServer.call(__MODULE__, {:chunk_code, source_code, language, opts})
  end

  @doc """
  Chunks an AST into semantic segments.
  """
  def chunk_ast(ast, opts \\ []) do
    GenServer.call(__MODULE__, {:chunk_ast, ast, opts})
  end

  @doc """
  Creates overlapping chunks with sliding window approach.
  """
  def sliding_window_chunk(text, opts \\ []) do
    GenServer.call(__MODULE__, {:sliding_window_chunk, text, opts})
  end

  @doc """
  Gets chunking strategies for a specific language.
  """
  def get_language_strategies(language) do
    GenServer.call(__MODULE__, {:get_language_strategies, language})
  end

  @doc """
  Analyzes chunk quality and overlap efficiency.
  """
  def analyze_chunk_quality(chunks, original_text) do
    GenServer.call(__MODULE__, {:analyze_chunk_quality, chunks, original_text})
  end

  @doc """
  Gets chunking performance metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @impl true
  def init(opts) do
    Logger.info("Starting ILP Semantic Chunker")
    
    state = %__MODULE__{
      chunk_strategy: Keyword.get(opts, :strategy, :hybrid),
      window_size: Keyword.get(opts, :window_size, @default_window_size),
      overlap_ratio: Keyword.get(opts, :overlap_ratio, @default_overlap_ratio),
      min_chunk_size: Keyword.get(opts, :min_chunk_size, @default_min_chunk_size),
      max_chunk_size: Keyword.get(opts, :max_chunk_size, @default_max_chunk_size),
      language_strategies: initialize_language_strategies(),
      chunk_cache: %{},
      metrics: %{
        total_chunks_created: 0,
        avg_chunk_size: 0,
        cache_hits: 0,
        processing_times: []
      }
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:chunk_code, source_code, language, opts}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Check cache first
    cache_key = generate_cache_key(source_code, language, opts)
    
    case Map.get(state.chunk_cache, cache_key) do
      nil ->
        # Parse and chunk
        case Abstraction.parse(source_code, language) do
          {:ok, ast} ->
            chunks = perform_semantic_chunking(ast, source_code, language, opts, state)
            
            end_time = System.monotonic_time(:microsecond)
            processing_time = end_time - start_time
            
            # Update cache and metrics
            new_cache = Map.put(state.chunk_cache, cache_key, chunks)
            new_state = state
            |> Map.put(:chunk_cache, new_cache)
            |> update_chunking_metrics(chunks, processing_time)
            
            {:reply, {:ok, chunks}, new_state}
          
          {:error, reason} ->
            # Fallback to text-based chunking
            chunks = fallback_text_chunking(source_code, opts, state)
            
            end_time = System.monotonic_time(:microsecond)
            processing_time = end_time - start_time
            
            new_state = update_chunking_metrics(state, chunks, processing_time)
            {:reply, {:ok, chunks}, new_state}
        end
      
      cached_chunks ->
        new_metrics = Map.update!(state.metrics, :cache_hits, &(&1 + 1))
        new_state = %{state | metrics: new_metrics}
        {:reply, {:ok, cached_chunks}, new_state}
    end
  end

  @impl true
  def handle_call({:chunk_ast, ast, opts}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    language = ast.language || :unknown
    chunks = perform_ast_chunking(ast, opts, state)
    
    end_time = System.monotonic_time(:microsecond)
    processing_time = end_time - start_time
    
    new_state = update_chunking_metrics(state, chunks, processing_time)
    {:reply, {:ok, chunks}, new_state}
  end

  @impl true
  def handle_call({:sliding_window_chunk, text, opts}, _from, state) do
    window_size = Keyword.get(opts, :window_size, state.window_size)
    overlap_ratio = Keyword.get(opts, :overlap_ratio, state.overlap_ratio)
    
    chunks = create_sliding_window_chunks(text, window_size, overlap_ratio)
    
    new_state = update_chunking_metrics(state, chunks, 0)
    {:reply, {:ok, chunks}, new_state}
  end

  @impl true
  def handle_call({:get_language_strategies, language}, _from, state) do
    strategies = Map.get(state.language_strategies, language, get_default_strategy())
    {:reply, strategies, state}
  end

  @impl true
  def handle_call({:analyze_chunk_quality, chunks, original_text}, _from, state) do
    analysis = perform_chunk_quality_analysis(chunks, original_text)
    {:reply, analysis, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  defp initialize_language_strategies do
    %{
      elixir: %{
        boundaries: [:defmodule, :def, :defp, :defmacro, :defstruct],
        min_size: 200,
        max_size: 3000,
        prefer_complete_functions: true,
        respect_documentation: true
      },
      javascript: %{
        boundaries: [:function_declaration, :class_declaration, :arrow_function],
        min_size: 150,
        max_size: 2500,
        prefer_complete_functions: true,
        respect_comments: true
      },
      python: %{
        boundaries: [:function_def, :class_def, :if_statement, :for_statement],
        min_size: 180,
        max_size: 2800,
        prefer_complete_functions: true,
        respect_docstrings: true
      },
      typescript: %{
        boundaries: [:interface_declaration, :type_alias_declaration, :function_declaration],
        min_size: 160,
        max_size: 2600,
        prefer_complete_functions: true,
        respect_types: true
      },
      rust: %{
        boundaries: [:function_item, :struct_item, :impl_item, :trait_item],
        min_size: 200,
        max_size: 3200,
        prefer_complete_functions: true,
        respect_visibility: true
      },
      java: %{
        boundaries: [:class_declaration, :method_declaration, :constructor_declaration],
        min_size: 220,
        max_size: 3500,
        prefer_complete_methods: true,
        respect_access_modifiers: true
      }
    }
  end

  defp get_default_strategy do
    %{
      boundaries: [:function, :class, :block],
      min_size: @default_min_chunk_size,
      max_size: @default_max_chunk_size,
      prefer_complete_functions: true,
      respect_comments: true
    }
  end

  defp perform_semantic_chunking(ast, source_code, language, opts, state) do
    strategy = Keyword.get(opts, :strategy, state.chunk_strategy)
    language_config = Map.get(state.language_strategies, language, get_default_strategy())
    
    case strategy do
      :semantic ->
        create_semantic_chunks(ast, source_code, language_config)
      
      :syntactic ->
        create_syntactic_chunks(ast, source_code, language_config)
      
      :sliding_window ->
        window_size = Keyword.get(opts, :window_size, state.window_size)
        overlap_ratio = Keyword.get(opts, :overlap_ratio, state.overlap_ratio)
        create_sliding_window_chunks(source_code, window_size, overlap_ratio)
      
      :hybrid ->
        create_hybrid_chunks(ast, source_code, language_config, state)
    end
  end

  defp create_semantic_chunks(ast, source_code, language_config) do
    # Find semantic boundaries based on language-specific constructs
    boundaries = find_semantic_boundaries(ast, language_config.boundaries)
    
    # Create chunks respecting semantic boundaries
    chunks = boundaries
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [start_pos, end_pos] ->
      extract_chunk_between_positions(source_code, start_pos, end_pos)
    end)
    |> filter_by_size(language_config.min_size, language_config.max_size)
    |> enhance_chunks_with_metadata(ast)
    
    chunks
  end

  defp create_syntactic_chunks(ast, source_code, language_config) do
    # Chunk based on syntactic structure (AST depth and node types)
    ast
    |> Node.find_all(&is_chunkable_node?(&1, language_config))
    |> Enum.map(&extract_node_chunk(&1, source_code))
    |> filter_by_size(language_config.min_size, language_config.max_size)
    |> enhance_chunks_with_metadata(ast)
  end

  defp create_sliding_window_chunks(text, window_size, overlap_ratio) do
    text_length = String.length(text)
    step_size = round(window_size * (1 - overlap_ratio))
    
    0..text_length
    |> Enum.take_every(step_size)
    |> Enum.map(fn start_pos ->
      end_pos = min(start_pos + window_size, text_length)
      chunk_text = String.slice(text, start_pos, end_pos - start_pos)
      
      %{
        content: chunk_text,
        start_position: start_pos,
        end_position: end_pos,
        size: String.length(chunk_text),
        type: :sliding_window,
        overlap_with_previous: calculate_overlap(start_pos, step_size, window_size)
      }
    end)
    |> Enum.filter(&(&1.size > 50))  # Filter out tiny chunks
  end

  defp create_hybrid_chunks(ast, source_code, language_config, state) do
    # Combine semantic and sliding window approaches
    semantic_chunks = create_semantic_chunks(ast, source_code, language_config)
    
    # For chunks that are too large, apply sliding window
    improved_chunks = Enum.flat_map(semantic_chunks, fn chunk ->
      if chunk.size > state.max_chunk_size do
        create_sliding_window_chunks(
          chunk.content, 
          state.window_size, 
          state.overlap_ratio
        )
      else
        [chunk]
      end
    end)
    
    improved_chunks
  end

  defp perform_ast_chunking(ast, opts, state) do
    language = ast.language || :unknown
    language_config = Map.get(state.language_strategies, language, get_default_strategy())
    
    # Extract source code from AST if available
    source_code = extract_source_from_ast(ast)
    
    create_semantic_chunks(ast, source_code, language_config)
  end

  defp fallback_text_chunking(source_code, opts, state) do
    window_size = Keyword.get(opts, :window_size, state.window_size)
    overlap_ratio = Keyword.get(opts, :overlap_ratio, state.overlap_ratio)
    
    # Simple line-based chunking with overlap
    lines = String.split(source_code, "\n")
    lines_per_chunk = div(window_size, 80)  # Estimate ~80 chars per line
    overlap_lines = round(lines_per_chunk * overlap_ratio)
    
    lines
    |> Enum.chunk_every(lines_per_chunk, lines_per_chunk - overlap_lines, :discard)
    |> Enum.with_index()
    |> Enum.map(fn {chunk_lines, index} ->
      content = Enum.join(chunk_lines, "\n")
      %{
        content: content,
        start_line: index * (lines_per_chunk - overlap_lines) + 1,
        end_line: index * (lines_per_chunk - overlap_lines) + length(chunk_lines),
        size: String.length(content),
        type: :fallback_text,
        chunk_index: index
      }
    end)
  end

  defp find_semantic_boundaries(ast, boundary_types) do
    ast
    |> Node.find_all(&(&1.type in boundary_types))
    |> Enum.map(&extract_node_position/1)
    |> Enum.sort()
    |> Enum.uniq()
  end

  defp is_chunkable_node?(node, language_config) do
    node.type in language_config.boundaries and
    node_has_sufficient_content?(node, language_config.min_size)
  end

  defp node_has_sufficient_content?(node, min_size) do
    content_size = estimate_node_content_size(node)
    content_size >= min_size
  end

  defp estimate_node_content_size(node) do
    case node.source_range do
      %{start: %{line: start_line, column: start_col}, 
        end: %{line: end_line, column: end_col}} ->
        # Rough estimation based on lines and columns
        line_diff = end_line - start_line
        col_diff = if line_diff == 0, do: end_col - start_col, else: end_col + 80 * line_diff
        max(col_diff, 0)
      
      _ ->
        # Fallback: count child nodes
        Node.count_nodes(node) * 20
    end
  end

  defp extract_node_position(node) do
    case node.position do
      %{line: line, column: column} -> {line, column}
      %{line: line} -> {line, 0}
      _ -> {0, 0}
    end
  end

  defp extract_chunk_between_positions(source_code, start_pos, end_pos) do
    lines = String.split(source_code, "\n")
    {start_line, start_col} = start_pos
    {end_line, end_col} = end_pos
    
    chunk_lines = lines
    |> Enum.slice((start_line - 1)..(end_line - 1))
    |> adjust_chunk_boundaries(start_col, end_col, start_line == end_line)
    
    content = Enum.join(chunk_lines, "\n")
    
    %{
      content: content,
      start_position: start_pos,
      end_position: end_pos,
      size: String.length(content),
      type: :semantic,
      lines: length(chunk_lines)
    }
  end

  defp extract_node_chunk(node, source_code) do
    case node.source_range do
      %{start: start_pos, end: end_pos} ->
        extract_chunk_between_positions(source_code, 
          {start_pos.line, start_pos.column}, 
          {end_pos.line, end_pos.column})
      
      _ ->
        # Fallback: estimate chunk from node content
        %{
          content: node.value || "# Node content",
          start_position: extract_node_position(node),
          end_position: extract_node_position(node),
          size: String.length(node.value || ""),
          type: :syntactic_fallback,
          node_type: node.type
        }
    end
  end

  defp adjust_chunk_boundaries(lines, start_col, end_col, same_line) do
    case {lines, same_line} do
      {[single_line], true} ->
        [String.slice(single_line, start_col..(end_col - 1))]
      
      {[first_line | rest], false} ->
        adjusted_first = String.slice(first_line, start_col..-1)
        adjusted_last = case List.last(rest) do
          nil -> []
          last_line -> [String.slice(last_line, 0..(end_col - 1))]
        end
        
        middle_lines = if length(rest) > 1 do
          Enum.slice(rest, 0..-2)
        else
          []
        end
        
        [adjusted_first] ++ middle_lines ++ adjusted_last
      
      _ ->
        lines
    end
  end

  defp filter_by_size(chunks, min_size, max_size) do
    Enum.filter(chunks, fn chunk ->
      chunk.size >= min_size and chunk.size <= max_size
    end)
  end

  defp enhance_chunks_with_metadata(chunks, ast) do
    Enum.map(chunks, fn chunk ->
      Map.merge(chunk, %{
        language: ast.language,
        semantic_depth: calculate_semantic_depth(chunk, ast),
        complexity_score: estimate_chunk_complexity(chunk),
        contains_definitions: chunk_contains_definitions?(chunk),
        imports_count: count_imports_in_chunk(chunk)
      })
    end)
  end

  defp calculate_overlap(start_pos, step_size, window_size) do
    if start_pos == 0 do
      0
    else
      overlap_size = window_size - step_size
      overlap_size / window_size
    end
  end

  defp extract_source_from_ast(ast) do
    # Try to reconstruct source from AST metadata
    case ast.metadata do
      %{source: source} -> source
      _ -> "# Source code not available"
    end
  end

  defp calculate_semantic_depth(_chunk, _ast) do
    # Simplified implementation
    :rand.uniform(5)
  end

  defp estimate_chunk_complexity(chunk) do
    # Simple complexity estimation based on content patterns
    content = chunk.content
    
    complexity = 0
    complexity = complexity + (String.split(content, ~r/\bif\b/) |> length()) * 2
    complexity = complexity + (String.split(content, ~r/\bfor\b/) |> length()) * 3
    complexity = complexity + (String.split(content, ~r/\bwhile\b/) |> length()) * 3
    complexity = complexity + (String.split(content, ~r/\bcase\b/) |> length()) * 4
    complexity = complexity + (String.split(content, ~r/\btry\b/) |> length()) * 5
    
    complexity
  end

  defp chunk_contains_definitions?(chunk) do
    content = chunk.content
    String.contains?(content, ["def ", "defp ", "defmodule", "class ", "function "])
  end

  defp count_imports_in_chunk(chunk) do
    content = chunk.content
    import_patterns = [~r/^import\s/, ~r/^require\s/, ~r/^alias\s/, ~r/^use\s/]
    
    lines = String.split(content, "\n")
    
    Enum.reduce(import_patterns, 0, fn pattern, acc ->
      acc + Enum.count(lines, &Regex.match?(pattern, String.trim(&1)))
    end)
  end

  defp perform_chunk_quality_analysis(chunks, original_text) do
    total_chunks = length(chunks)
    total_original_length = String.length(original_text)
    total_chunks_length = Enum.sum(Enum.map(chunks, &(&1.size)))
    
    %{
      total_chunks: total_chunks,
      avg_chunk_size: if(total_chunks > 0, do: div(total_chunks_length, total_chunks), else: 0),
      coverage_ratio: total_chunks_length / total_original_length,
      size_distribution: calculate_size_distribution(chunks),
      overlap_analysis: analyze_overlap_patterns(chunks),
      semantic_coherence: estimate_semantic_coherence(chunks)
    }
  end

  defp calculate_size_distribution(chunks) do
    sizes = Enum.map(chunks, &(&1.size))
    
    %{
      min: Enum.min(sizes, fn -> 0 end),
      max: Enum.max(sizes, fn -> 0 end),
      median: calculate_median(sizes),
      std_dev: calculate_standard_deviation(sizes)
    }
  end

  defp analyze_overlap_patterns(chunks) do
    overlaps = chunks
    |> Enum.filter(&Map.has_key?(&1, :overlap_with_previous))
    |> Enum.map(&(&1.overlap_with_previous))
    
    case overlaps do
      [] -> %{avg_overlap: 0, consistent_overlap: true}
      _ -> 
        avg = Enum.sum(overlaps) / length(overlaps)
        variance = Enum.map(overlaps, &((&1 - avg) ** 2)) |> Enum.sum() |> Kernel./(length(overlaps))
        
        %{
          avg_overlap: avg,
          consistent_overlap: variance < 0.01
        }
    end
  end

  defp estimate_semantic_coherence(chunks) do
    # Simplified coherence estimation
    coherence_scores = Enum.map(chunks, fn chunk ->
      if chunk_contains_definitions?(chunk) do
        0.8
      else
        0.6
      end
    end)
    
    Enum.sum(coherence_scores) / length(coherence_scores)
  end

  defp calculate_median([]), do: 0
  defp calculate_median(list) do
    sorted = Enum.sort(list)
    len = length(sorted)
    
    if rem(len, 2) == 0 do
      (Enum.at(sorted, div(len, 2) - 1) + Enum.at(sorted, div(len, 2))) / 2
    else
      Enum.at(sorted, div(len, 2))
    end
  end

  defp calculate_standard_deviation([]), do: 0
  defp calculate_standard_deviation(list) do
    mean = Enum.sum(list) / length(list)
    variance = Enum.map(list, &((&1 - mean) ** 2)) |> Enum.sum() |> Kernel./(length(list))
    :math.sqrt(variance)
  end

  defp generate_cache_key(source_code, language, opts) do
    # Generate a hash-based cache key
    content_hash = :crypto.hash(:sha256, source_code) |> Base.encode16()
    opts_hash = :crypto.hash(:sha256, inspect(opts)) |> Base.encode16()
    
    "chunk:#{language}:#{String.slice(content_hash, 0, 8)}:#{String.slice(opts_hash, 0, 8)}"
  end

  defp update_chunking_metrics(state, chunks, processing_time) do
    current_metrics = state.metrics
    chunk_count = length(chunks)
    total_size = Enum.sum(Enum.map(chunks, &(&1.size)))
    avg_size = if chunk_count > 0, do: div(total_size, chunk_count), else: 0
    
    new_metrics = %{current_metrics |
      total_chunks_created: current_metrics.total_chunks_created + chunk_count,
      avg_chunk_size: (current_metrics.avg_chunk_size + avg_size) / 2,
      processing_times: [processing_time | Enum.take(current_metrics.processing_times, 99)]
    }
    
    %{state | metrics: new_metrics}
  end
end
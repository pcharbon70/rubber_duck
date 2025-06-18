defmodule RubberDuck.CodingAssistant.Engines.StreamingAnalyser do
  @moduledoc """
  Streaming code analysis engine for handling large files efficiently.
  
  This engine provides streaming analysis capabilities for large codebases,
  with configurable file size limits, memory-efficient processing, and
  progressive analysis results.
  """

  @behaviour RubberDuck.CodingAssistant.EngineBehaviour

  require Logger
  alias RubberDuck.CodingAssistant.Engines.CodeAnalyser
  alias RubberDuck.ILP.Parser.TreeSitterWrapper

  # Configuration constants
  @max_file_size 10 * 1024 * 1024      # 10MB default max file size
  @chunk_size 64 * 1024                # 64KB chunks for streaming
  @max_memory_usage 100 * 1024 * 1024  # 100MB max memory usage
  @analysis_timeout 300_000             # 5 minutes timeout for large files

  defstruct [
    :config,
    :statistics,
    :streaming_state,
    :memory_monitor,
    :active_analyses
  ]

  @type analysis_mode :: :streaming | :chunked | :progressive | :memory_mapped
  @type file_analysis_state :: %{
    file_path: String.t(),
    file_size: non_neg_integer(),
    bytes_processed: non_neg_integer(),
    chunks_processed: non_neg_integer(),
    analysis_mode: analysis_mode(),
    results: map(),
    errors: [map()],
    start_time: non_neg_integer(),
    estimated_completion: non_neg_integer() | nil
  }

  ## EngineBehaviour Implementation

  @impl true
  def init(config) do
    state = %__MODULE__{
      config: normalize_config(config),
      statistics: initialize_statistics(),
      streaming_state: %{},
      memory_monitor: initialize_memory_monitor(),
      active_analyses: %{}
    }
    
    Logger.info("StreamingAnalyser engine initialized with max file size: #{format_bytes(get_max_file_size(state.config))}")
    {:ok, state}
  end

  @impl true
  def analyze(request, state) do
    file_path = request[:file_path]
    content = request[:content]
    options = request[:options] || %{}
    
    cond do
      file_path && File.exists?(file_path) ->
        analyze_file_streaming(file_path, options, state)
      
      content ->
        analyze_content_streaming(content, options, state)
      
      true ->
        {:error, :invalid_request, state}
    end
  end

  @impl true
  def capabilities(_state) do
    [
      :code_analysis,
      :streaming_analysis,
      :large_file_support,
      :memory_efficient,
      :progressive_results,
      :size_limits,
      :chunked_processing
    ]
  end

  @impl true
  def health_status(state) do
    memory_usage = get_current_memory_usage()
    max_memory = get_max_memory_usage(state.config)
    active_count = map_size(state.active_analyses)
    
    cond do
      memory_usage > max_memory * 0.9 -> :unhealthy
      memory_usage > max_memory * 0.7 or active_count > 10 -> :degraded
      true -> :healthy
    end
  end

  @impl true
  def statistics(state) do
    %{
      total_files_analyzed: state.statistics.total_files,
      total_bytes_processed: state.statistics.total_bytes,
      average_processing_speed: state.statistics.avg_bytes_per_second,
      memory_usage: get_current_memory_usage(),
      active_analyses: map_size(state.active_analyses),
      streaming_stats: state.statistics.streaming,
      chunked_stats: state.statistics.chunked
    }
  end

  @impl true
  def terminate(_state) do
    Logger.info("StreamingAnalyser engine terminated")
    :ok
  end

  ## File Analysis Functions

  defp analyze_file_streaming(file_path, options, state) do
    case get_file_info(file_path) do
      {:ok, file_info} ->
        case validate_file_size(file_info.size, state.config) do
          :ok ->
            analysis_mode = determine_analysis_mode(file_info, options, state.config)
            perform_file_analysis(file_path, file_info, analysis_mode, options, state)
          
          {:error, reason} ->
            {:error, reason, state}
        end
      
      {:error, reason} ->
        {:error, {:file_error, reason}, state}
    end
  end

  defp analyze_content_streaming(content, options, state) do
    content_size = byte_size(content)
    
    case validate_content_size(content_size, state.config) do
      :ok ->
        file_info = %{size: content_size, type: :content}
        analysis_mode = determine_analysis_mode(file_info, options, state.config)
        perform_content_analysis(content, analysis_mode, options, state)
      
      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp perform_file_analysis(file_path, file_info, analysis_mode, options, state) do
    analysis_id = generate_analysis_id()
    start_time = System.monotonic_time(:millisecond)
    
    analysis_state = %{
      file_path: file_path,
      file_size: file_info.size,
      bytes_processed: 0,
      chunks_processed: 0,
      analysis_mode: analysis_mode,
      results: initialize_analysis_results(),
      errors: [],
      start_time: start_time,
      estimated_completion: nil
    }
    
    # Add to active analyses
    new_active_analyses = Map.put(state.active_analyses, analysis_id, analysis_state)
    updated_state = %{state | active_analyses: new_active_analyses}
    
    # Perform analysis based on mode
    case analysis_mode do
      :streaming ->
        perform_streaming_analysis(file_path, analysis_id, options, updated_state)
      
      :chunked ->
        perform_chunked_analysis(file_path, analysis_id, options, updated_state)
      
      :progressive ->
        perform_progressive_analysis(file_path, analysis_id, options, updated_state)
      
      :memory_mapped ->
        perform_memory_mapped_analysis(file_path, analysis_id, options, updated_state)
    end
  end

  defp perform_content_analysis(content, analysis_mode, options, state) do
    case analysis_mode do
      :streaming ->
        analyze_content_in_chunks(content, options, state)
      
      _ ->
        # For content analysis, fall back to standard analysis for smaller content
        if byte_size(content) < @chunk_size do
          CodeAnalyser.analyze(%{content: content, options: options}, state)
        else
          analyze_content_in_chunks(content, options, state)
        end
    end
  end

  ## Streaming Analysis Implementations

  defp perform_streaming_analysis(file_path, analysis_id, options, state) do
    chunk_size = get_chunk_size(state.config)
    language = detect_language_from_path(file_path)
    
    try do
      stream = File.stream!(file_path, [:read], chunk_size)
      
      {final_results, final_state} = stream
      |> Stream.with_index()
      |> Enum.reduce({initialize_analysis_results(), state}, fn {chunk, index}, {results, acc_state} ->
        # Process chunk
        chunk_results = analyze_chunk(chunk, index, language, options)
        
        # Merge results
        merged_results = merge_chunk_results(results, chunk_results)
        
        # Update analysis state
        updated_analysis_state = update_analysis_progress(
          analysis_id, 
          byte_size(chunk), 
          index + 1, 
          acc_state
        )
        
        # Check memory usage
        if should_pause_for_memory?(acc_state) do
          :timer.sleep(100)  # Brief pause to allow GC
        end
        
        {merged_results, updated_analysis_state}
      end)
      
      # Complete analysis
      completed_state = complete_analysis(analysis_id, final_results, final_state)
      {:ok, final_results, completed_state}
      
    rescue
      error ->
        error_state = handle_analysis_error(analysis_id, error, state)
        {:error, {:streaming_error, error}, error_state}
    end
  end

  defp perform_chunked_analysis(file_path, analysis_id, options, state) do
    chunk_size = get_chunk_size(state.config)
    language = detect_language_from_path(file_path)
    
    case File.read(file_path) do
      {:ok, content} ->
        chunks = chunk_content(content, chunk_size)
        
        results = chunks
        |> Enum.with_index()
        |> Enum.map(fn {chunk, index} ->
          analyze_chunk(chunk, index, language, options)
        end)
        
        final_results = combine_chunk_results(results)
        completed_state = complete_analysis(analysis_id, final_results, state)
        
        {:ok, final_results, completed_state}
      
      {:error, reason} ->
        error_state = handle_analysis_error(analysis_id, reason, state)
        {:error, {:file_read_error, reason}, error_state}
    end
  end

  defp perform_progressive_analysis(file_path, analysis_id, options, state) do
    # Progressive analysis builds results incrementally
    # This is useful for providing early feedback on large files
    
    chunk_size = get_chunk_size(state.config)
    language = detect_language_from_path(file_path)
    total_size = get_file_size(file_path)
    
    # Start with basic file structure analysis
    initial_results = analyze_file_structure(file_path, language)
    
    # Then progressively analyze content
    try do
      stream = File.stream!(file_path, [:read], chunk_size)
      
      {final_results, final_state} = stream
      |> Stream.with_index()
      |> Enum.reduce({initial_results, state}, fn {chunk, index}, {results, acc_state} ->
        # Analyze chunk with context from previous results
        chunk_results = analyze_chunk_with_context(chunk, index, language, results, options)
        
        # Progressively build results
        updated_results = merge_progressive_results(results, chunk_results)
        
        # Update progress
        bytes_processed = (index + 1) * chunk_size
        progress = min(bytes_processed / total_size, 1.0)
        
        updated_state = update_analysis_progress_detailed(
          analysis_id,
          byte_size(chunk),
          index + 1,
          progress,
          acc_state
        )
        
        # Emit intermediate results for long-running analyses
        if index > 0 and rem(index, 10) == 0 do
          emit_intermediate_results(analysis_id, updated_results, progress)
        end
        
        {updated_results, updated_state}
      end)
      
      completed_state = complete_analysis(analysis_id, final_results, final_state)
      {:ok, final_results, completed_state}
      
    rescue
      error ->
        error_state = handle_analysis_error(analysis_id, error, state)
        {:error, {:progressive_error, error}, error_state}
    end
  end

  defp perform_memory_mapped_analysis(file_path, analysis_id, options, state) do
    # Memory-mapped analysis for very large files
    # This uses file mapping to avoid loading entire file into memory
    
    language = detect_language_from_path(file_path)
    
    try do
      # Use Erlang's file:open with raw and read_ahead options
      case :file.open(file_path, [:read, :raw, :binary, {:read_ahead, @chunk_size}]) do
        {:ok, file_handle} ->
          try do
            results = analyze_file_mapped(file_handle, language, options, analysis_id, state)
            completed_state = complete_analysis(analysis_id, results, state)
            {:ok, results, completed_state}
          after
            :file.close(file_handle)
          end
        
        {:error, reason} ->
          error_state = handle_analysis_error(analysis_id, reason, state)
          {:error, {:file_open_error, reason}, error_state}
      end
      
    rescue
      error ->
        error_state = handle_analysis_error(analysis_id, error, state)
        {:error, {:memory_mapped_error, error}, error_state}
    end
  end

  ## Content Analysis Functions

  defp analyze_content_in_chunks(content, options, state) do
    chunk_size = get_chunk_size(state.config)
    chunks = chunk_content(content, chunk_size)
    language = detect_language_from_content(content)
    
    results = chunks
    |> Enum.with_index()
    |> Enum.map(fn {chunk, index} ->
      analyze_chunk(chunk, index, language, options)
    end)
    
    final_results = combine_chunk_results(results)
    {:ok, final_results, state}
  end

  defp analyze_chunk(chunk, index, language, options) do
    # Analyze individual chunk with TreeSitter if possible
    case TreeSitterWrapper.parse(chunk, language) do
      {:ok, ast} ->
        # Perform analysis on the AST
        %{
          chunk_index: index,
          syntax_analysis: analyze_chunk_syntax(ast, chunk, language),
          complexity_analysis: analyze_chunk_complexity(ast, chunk),
          security_analysis: analyze_chunk_security(ast, chunk, language),
          code_smells: analyze_chunk_smells(ast, chunk, language),
          metrics: calculate_chunk_metrics(chunk),
          byte_range: {index * @chunk_size, index * @chunk_size + byte_size(chunk)}
        }
      
      {:error, _reason} ->
        # Fall back to string-based analysis
        %{
          chunk_index: index,
          syntax_analysis: %{errors: ["Parse error - using fallback analysis"]},
          complexity_analysis: basic_complexity_analysis(chunk),
          security_analysis: basic_security_analysis(chunk, language),
          code_smells: basic_smell_analysis(chunk),
          metrics: calculate_chunk_metrics(chunk),
          byte_range: {index * @chunk_size, index * @chunk_size + byte_size(chunk)}
        }
    end
  end

  defp analyze_chunk_with_context(chunk, index, language, previous_results, options) do
    # Enhanced chunk analysis that considers context from previous chunks
    base_analysis = analyze_chunk(chunk, index, language, options)
    
    # Add context-aware analysis
    context_analysis = %{
      cross_chunk_references: find_cross_chunk_references(chunk, previous_results),
      cumulative_complexity: update_cumulative_complexity(base_analysis, previous_results),
      progressive_patterns: detect_progressive_patterns(chunk, previous_results)
    }
    
    Map.merge(base_analysis, %{context_analysis: context_analysis})
  end

  ## Helper Functions

  defp get_file_info(file_path) do
    case File.stat(file_path) do
      {:ok, %File.Stat{size: size, type: type}} ->
        {:ok, %{size: size, type: type, path: file_path}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_file_size(size, config) do
    max_size = get_max_file_size(config)
    
    if size <= max_size do
      :ok
    else
      {:error, {:file_too_large, size, max_size}}
    end
  end

  defp validate_content_size(size, config) do
    max_size = get_max_file_size(config)
    
    if size <= max_size do
      :ok
    else
      {:error, {:content_too_large, size, max_size}}
    end
  end

  defp determine_analysis_mode(file_info, options, config) do
    size = file_info.size
    mode_preference = options[:analysis_mode]
    
    cond do
      mode_preference in [:streaming, :chunked, :progressive, :memory_mapped] ->
        mode_preference
      
      size > 50 * 1024 * 1024 ->  # > 50MB
        :memory_mapped
      
      size > 10 * 1024 * 1024 ->  # > 10MB
        :progressive
      
      size > 1 * 1024 * 1024 ->   # > 1MB
        :chunked
      
      true ->
        :streaming
    end
  end

  defp chunk_content(content, chunk_size) do
    content
    |> :binary.bin_to_list()
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(&:binary.list_to_bin/1)
  end

  defp merge_chunk_results(acc_results, chunk_result) do
    # Merge chunk results into accumulated results
    %{acc_results |
      chunks: [chunk_result | acc_results.chunks],
      total_lines: acc_results.total_lines + Map.get(chunk_result.metrics, :lines, 0),
      total_bytes: acc_results.total_bytes + Map.get(chunk_result.metrics, :bytes, 0),
      syntax_errors: acc_results.syntax_errors ++ Map.get(chunk_result.syntax_analysis, :errors, []),
      security_issues: acc_results.security_issues ++ Map.get(chunk_result.security_analysis, :vulnerabilities, []),
      complexity_score: max(acc_results.complexity_score, Map.get(chunk_result.complexity_analysis, :score, 0))
    }
  end

  defp combine_chunk_results(chunk_results) do
    Enum.reduce(chunk_results, initialize_analysis_results(), &merge_chunk_results(&2, &1))
  end

  defp merge_progressive_results(current_results, chunk_result) do
    # Progressive merging that maintains running totals and updates global metrics
    merge_chunk_results(current_results, chunk_result)
  end

  defp initialize_analysis_results do
    %{
      chunks: [],
      total_lines: 0,
      total_bytes: 0,
      syntax_errors: [],
      security_issues: [],
      code_smells: [],
      complexity_score: 0,
      analysis_start: System.monotonic_time(:millisecond),
      analysis_mode: nil,
      progress: 0.0
    }
  end

  defp calculate_chunk_metrics(chunk) do
    lines = String.split(chunk, "\n") |> length()
    bytes = byte_size(chunk)
    
    %{
      lines: lines,
      bytes: bytes,
      characters: String.length(chunk),
      whitespace_ratio: calculate_whitespace_ratio(chunk)
    }
  end

  defp calculate_whitespace_ratio(content) do
    total_chars = String.length(content)
    whitespace_chars = String.length(String.replace(content, ~r/\S/, ""))
    
    if total_chars > 0 do
      whitespace_chars / total_chars
    else
      0.0
    end
  end

  # Simplified analysis functions for fallback
  defp basic_complexity_analysis(chunk) do
    # Count basic complexity indicators
    complexity_keywords = ~w(if else while for switch case function def class)
    complexity_count = Enum.reduce(complexity_keywords, 0, fn keyword, acc ->
      acc + length(Regex.scan(~r/\b#{keyword}\b/, chunk))
    end)
    
    %{score: complexity_count, method: :keyword_count}
  end

  defp basic_security_analysis(chunk, language) do
    # Basic security pattern matching
    security_patterns = get_security_patterns(language)
    
    vulnerabilities = Enum.flat_map(security_patterns, fn {pattern, issue_type} ->
      case Regex.scan(pattern, chunk, capture: :all_but_first) do
        [] -> []
        matches -> 
          Enum.map(matches, fn _match ->
            %{type: issue_type, severity: :medium, pattern: pattern}
          end)
      end
    end)
    
    %{vulnerabilities: vulnerabilities}
  end

  defp basic_smell_analysis(chunk) do
    # Basic code smell detection
    smells = []
    
    # Long lines
    smells = if String.contains?(chunk, "\n") do
      long_lines = chunk
      |> String.split("\n")
      |> Enum.with_index()
      |> Enum.filter(fn {line, _index} -> String.length(line) > 120 end)
      
      if length(long_lines) > 0 do
        [%{type: :long_lines, count: length(long_lines)} | smells]
      else
        smells
      end
    else
      smells
    end
    
    smells
  end

  # Configuration and utility functions
  defp normalize_config(config) do
    Map.merge(%{
      max_file_size: @max_file_size,
      chunk_size: @chunk_size,
      max_memory_usage: @max_memory_usage,
      analysis_timeout: @analysis_timeout
    }, config)
  end

  defp get_max_file_size(config), do: Map.get(config, :max_file_size, @max_file_size)
  defp get_chunk_size(config), do: Map.get(config, :chunk_size, @chunk_size)
  defp get_max_memory_usage(config), do: Map.get(config, :max_memory_usage, @max_memory_usage)

  defp get_file_size(file_path) do
    case File.stat(file_path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _} -> 0
    end
  end

  defp detect_language_from_path(file_path) do
    case Path.extname(file_path) do
      ".ex" -> :elixir
      ".exs" -> :elixir
      ".py" -> :python
      ".js" -> :javascript
      ".ts" -> :typescript
      ".rb" -> :ruby
      ".go" -> :go
      ".rs" -> :rust
      ".java" -> :java
      ".cpp" -> :cpp
      ".c" -> :c
      _ -> :unknown
    end
  end

  defp detect_language_from_content(content) do
    # Simple content-based language detection
    cond do
      String.contains?(content, "defmodule") -> :elixir
      String.contains?(content, "def ") and String.contains?(content, "end") -> :elixir
      String.contains?(content, "function") and String.contains?(content, "=>") -> :javascript
      String.contains?(content, "def ") and String.contains?(content, ":") -> :python
      true -> :unknown
    end
  end

  defp get_security_patterns(:elixir) do
    [
      {~r/Code\.eval/, :code_injection},
      {~r/System\.cmd/, :command_injection},
      {~r/File\.read!/, :file_access}
    ]
  end

  defp get_security_patterns(:javascript) do
    [
      {~r/eval\(/, :code_injection},
      {~r/document\.write/, :xss},
      {~r/innerHTML/, :xss}
    ]
  end

  defp get_security_patterns(_), do: []

  defp format_bytes(bytes) do
    cond do
      bytes >= 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
      bytes >= 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} bytes"
    end
  end

  defp generate_analysis_id do
    "analysis_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp initialize_statistics do
    %{
      total_files: 0,
      total_bytes: 0,
      avg_bytes_per_second: 0.0,
      streaming: %{files: 0, total_time: 0},
      chunked: %{files: 0, total_time: 0}
    }
  end

  defp initialize_memory_monitor do
    %{
      peak_usage: 0,
      current_usage: 0,
      gc_count: 0
    }
  end

  defp get_current_memory_usage do
    # Get current process memory usage
    {:memory, memory_info} = Process.info(self(), :memory)
    memory_info
  end

  defp should_pause_for_memory?(state) do
    current_memory = get_current_memory_usage()
    max_memory = get_max_memory_usage(state.config)
    current_memory > max_memory * 0.8
  end

  defp update_analysis_progress(analysis_id, bytes_processed, chunks_processed, state) do
    case Map.get(state.active_analyses, analysis_id) do
      nil -> state
      analysis_state ->
        updated_analysis = %{analysis_state |
          bytes_processed: analysis_state.bytes_processed + bytes_processed,
          chunks_processed: chunks_processed
        }
        
        new_active_analyses = Map.put(state.active_analyses, analysis_id, updated_analysis)
        %{state | active_analyses: new_active_analyses}
    end
  end

  defp update_analysis_progress_detailed(analysis_id, bytes_processed, chunks_processed, progress, state) do
    updated_state = update_analysis_progress(analysis_id, bytes_processed, chunks_processed, state)
    
    case Map.get(updated_state.active_analyses, analysis_id) do
      nil -> updated_state
      analysis_state ->
        # Calculate estimated completion time
        elapsed_time = System.monotonic_time(:millisecond) - analysis_state.start_time
        estimated_completion = if progress > 0 do
          analysis_state.start_time + round(elapsed_time / progress)
        else
          nil
        end
        
        updated_analysis = %{analysis_state |
          estimated_completion: estimated_completion
        }
        
        new_active_analyses = Map.put(updated_state.active_analyses, analysis_id, updated_analysis)
        %{updated_state | active_analyses: new_active_analyses}
    end
  end

  defp complete_analysis(analysis_id, results, state) do
    # Remove from active analyses and update statistics
    new_active_analyses = Map.delete(state.active_analyses, analysis_id)
    
    # Update statistics
    new_statistics = update_completion_statistics(state.statistics, results)
    
    %{state |
      active_analyses: new_active_analyses,
      statistics: new_statistics
    }
  end

  defp handle_analysis_error(analysis_id, error, state) do
    Logger.error("Analysis error for #{analysis_id}: #{inspect(error)}")
    
    # Remove from active analyses
    new_active_analyses = Map.delete(state.active_analyses, analysis_id)
    %{state | active_analyses: new_active_analyses}
  end

  defp update_completion_statistics(stats, results) do
    total_bytes = Map.get(results, :total_bytes, 0)
    processing_time = System.monotonic_time(:millisecond) - Map.get(results, :analysis_start, 0)
    
    bytes_per_second = if processing_time > 0 do
      total_bytes / (processing_time / 1000)
    else
      0.0
    end
    
    %{stats |
      total_files: stats.total_files + 1,
      total_bytes: stats.total_bytes + total_bytes,
      avg_bytes_per_second: (stats.avg_bytes_per_second + bytes_per_second) / 2
    }
  end

  # Placeholder functions for advanced analysis features
  defp analyze_file_structure(_file_path, _language), do: %{structure: :basic}
  defp find_cross_chunk_references(_chunk, _previous_results), do: []
  defp update_cumulative_complexity(chunk_analysis, _previous_results), do: Map.get(chunk_analysis, :complexity_analysis, %{})
  defp detect_progressive_patterns(_chunk, _previous_results), do: []
  defp emit_intermediate_results(_analysis_id, _results, _progress), do: :ok
  defp analyze_file_mapped(_file_handle, _language, _options, _analysis_id, _state), do: %{mapped: true}
  defp analyze_chunk_syntax(ast, _chunk, _language), do: %{ast_nodes: map_size(ast)}
  defp analyze_chunk_complexity(ast, _chunk), do: %{score: map_size(ast)}
  defp analyze_chunk_security(ast, _chunk, _language), do: %{vulnerabilities: []}
  defp analyze_chunk_smells(ast, _chunk, _language), do: []
end
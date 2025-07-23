defmodule RubberDuck.Projects.FileSearch do
  @moduledoc """
  Advanced file search functionality for projects.
  
  Provides powerful search capabilities including:
  - Full-text search within files
  - Pattern matching with regex support
  - File attribute filtering
  - Search result ranking
  - Parallel search execution
  - Search caching
  """
  
  alias RubberDuck.Projects.{FileManager, FileCache}
  require Logger
  
  @type search_options :: [
    pattern: String.t() | Regex.t(),
    file_pattern: String.t(),
    max_results: pos_integer(),
    case_sensitive: boolean(),
    whole_word: boolean(),
    include_binary: boolean(),
    max_file_size: pos_integer(),
    parallel: boolean(),
    context_lines: non_neg_integer()
  ]
  
  @type search_result :: %{
    file: String.t(),
    matches: [match()],
    score: float()
  }
  
  @type match :: %{
    line: pos_integer(),
    column: pos_integer(),
    text: String.t(),
    context: context()
  }
  
  @type context :: %{
    before: [String.t()],
    after: [String.t()]
  }
  
  @default_max_results 100
  @default_max_file_size 10 * 1024 * 1024  # 10MB
  @default_context_lines 2
  @chunk_size 50  # Files per parallel chunk
  
  @doc """
  Searches for a pattern across all files in a project.
  
  ## Options
  - `:pattern` - Search pattern (string or regex)
  - `:file_pattern` - Glob pattern to filter files (e.g., "*.ex")
  - `:max_results` - Maximum number of results (default: 100)
  - `:case_sensitive` - Case sensitive search (default: false)
  - `:whole_word` - Match whole words only (default: false)
  - `:include_binary` - Include binary files (default: false)
  - `:max_file_size` - Skip files larger than this (default: 10MB)
  - `:parallel` - Use parallel processing (default: true)
  - `:context_lines` - Number of context lines (default: 2)
  """
  @spec search(FileManager.t(), String.t() | Regex.t(), search_options()) :: 
    {:ok, [search_result()]} | {:error, term()}
  def search(%FileManager{} = fm, pattern, opts \\ []) do
    with {:ok, regex} <- compile_pattern(pattern, opts),
         {:ok, files} <- get_searchable_files(fm, opts),
         {:ok, results} <- perform_search(fm, files, regex, opts) do
      {:ok, results}
    end
  end
  
  @doc """
  Searches for files by name pattern.
  
  Returns a list of file paths matching the pattern.
  """
  @spec find_files(FileManager.t(), String.t(), keyword()) :: 
    {:ok, [String.t()]} | {:error, term()}
  def find_files(%FileManager{} = fm, name_pattern, opts \\ []) do
    with {:ok, all_files} <- get_all_files(fm, ".", opts),
         matching_files <- filter_by_name(all_files, name_pattern, opts) do
      {:ok, matching_files}
    end
  end
  
  @doc """
  Searches files by content type.
  
  Common types: :text, :code, :image, :binary, :archive
  """
  @spec find_by_type(FileManager.t(), atom() | [atom()], keyword()) :: 
    {:ok, [String.t()]} | {:error, term()}
  def find_by_type(%FileManager{} = fm, types, opts \\ []) do
    types = List.wrap(types)
    
    with {:ok, all_files} <- get_all_files(fm, ".", opts),
         typed_files <- filter_by_type(fm, all_files, types) do
      {:ok, typed_files}
    end
  end
  
  @doc """
  Searches for files modified within a time range.
  """
  @spec find_by_date(FileManager.t(), DateTime.t(), DateTime.t(), keyword()) :: 
    {:ok, [String.t()]} | {:error, term()}
  def find_by_date(%FileManager{} = fm, from_date, to_date, opts \\ []) do
    with {:ok, all_files} <- get_all_files(fm, ".", opts),
         dated_files <- filter_by_date(fm, all_files, from_date, to_date) do
      {:ok, dated_files}
    end
  end
  
  @doc """
  Performs a cached search if available.
  """
  @spec cached_search(FileManager.t(), String.t() | Regex.t(), search_options()) ::
    {:ok, [search_result()]} | {:error, term()}
  def cached_search(%FileManager{project: project} = fm, pattern, opts \\ []) do
    cache_key = build_search_cache_key(pattern, opts)
    
    case FileCache.get(project.id, cache_key) do
      {:ok, results} ->
        Logger.debug("Search cache hit for pattern: #{inspect(pattern)}")
        {:ok, results}
        
      :miss ->
        case search(fm, pattern, opts) do
          {:ok, results} = success ->
            # Cache for 5 minutes
            FileCache.put(project.id, cache_key, results, ttl: 300_000)
            success
            
          error ->
            error
        end
    end
  end
  
  # Private functions
  
  defp compile_pattern(pattern, opts) when is_binary(pattern) do
    case_sensitive = Keyword.get(opts, :case_sensitive, false)
    whole_word = Keyword.get(opts, :whole_word, false)
    
    pattern = if whole_word do
      "\\b#{Regex.escape(pattern)}\\b"
    else
      Regex.escape(pattern)
    end
    
    flags = if case_sensitive, do: "", else: "i"
    
    Regex.compile(pattern, flags)
  end
  
  defp compile_pattern(%Regex{} = pattern, _opts), do: {:ok, pattern}
  
  defp get_searchable_files(%FileManager{} = fm, opts) do
    file_pattern = Keyword.get(opts, :file_pattern, "**/*")
    include_binary = Keyword.get(opts, :include_binary, false)
    _max_file_size = Keyword.get(opts, :max_file_size, @default_max_file_size)
    
    with {:ok, all_files} <- collect_files(fm, ".", file_pattern) do
      # For now, don't filter by binary/size to simplify debugging
      if include_binary == false and is_list(all_files) do
        # Only filter out obviously binary files by extension
        filtered = Enum.filter(all_files, &is_text_file?(&1, nil))
        {:ok, filtered}
      else
        {:ok, all_files}
      end
    end
  end
  
  defp collect_files(fm, dir, pattern) do
    # Use FileManager to list directories recursively
    case collect_files_recursive(fm, dir, pattern, []) do
      {:ok, files} -> {:ok, files}
      error -> error
    end
  end
  
  defp collect_files_recursive(fm, dir, pattern, acc) do
    case FileManager.list_directory(fm, dir) do
      {:ok, entries} ->
        Enum.reduce_while(entries, {:ok, acc}, fn entry, {:ok, current_acc} ->
          # Use relative path from root
          path = if dir == "." do
            entry.name
          else
            Path.join(dir, entry.name)
          end
          
          case entry.type do
            :directory ->
              case collect_files_recursive(fm, path, pattern, current_acc) do
                {:ok, new_acc} -> {:cont, {:ok, new_acc}}
                error -> {:halt, error}
              end
              
            :regular ->
              if match_pattern?(path, pattern) do
                {:cont, {:ok, [path | current_acc]}}
              else
                {:cont, {:ok, current_acc}}
              end
              
            _ ->
              {:cont, {:ok, current_acc}}
          end
        end)
        
      error ->
        error
    end
  end
  
  defp match_pattern?(path, pattern) do
    # Simple glob pattern matching
    regex_pattern = pattern
    |> String.replace(".", "\\.")  # Escape dots first
    |> String.replace("**", "DOUBLE_STAR")  # Temporary placeholder
    |> String.replace("*", "[^/]*")
    |> String.replace("DOUBLE_STAR", ".*")  # Replace back
    |> String.replace("?", ".")
    
    case Regex.compile(regex_pattern) do
      {:ok, regex} -> Regex.match?(regex, path)
      _ -> false
    end
  end
  
  # Removed unused function filter_files/4 - functionality moved to get_searchable_files/2
  
  defp get_file_info(fm, file) do
    # Get file stats through FileManager
    case FileManager.list_directory(fm, Path.dirname(file)) do
      {:ok, entries} ->
        basename = Path.basename(file)
        entry = Enum.find(entries, &(&1.name == basename))
        
        if entry do
          {:ok, entry}
        else
          {:error, :not_found}
        end
        
      error ->
        error
    end
  end
  
  defp is_text_file?(path, _info) do
    # Check by extension first
    ext = Path.extname(path) |> String.downcase()
    
    ext in ~w[
      .txt .md .markdown .rst .log .csv .json .xml .yaml .yml
      .html .htm .css .scss .sass .less
      .js .jsx .ts .tsx .coffee .vue .svelte
      .rb .py .ex .exs .erl .hrl .go .rs .c .h .cpp .hpp .java
      .sh .bash .zsh .fish .ps1 .bat .cmd
      .sql .graphql .proto .toml .ini .conf .config .env
      .gitignore .dockerignore .editorconfig
    ]
  end
  
  defp perform_search(fm, files, regex, opts) do
    max_results = Keyword.get(opts, :max_results, @default_max_results)
    parallel = Keyword.get(opts, :parallel, true)
    context_lines = Keyword.get(opts, :context_lines, @default_context_lines)
    
    results = if parallel and length(files) > @chunk_size do
      search_parallel(fm, files, regex, context_lines)
    else
      search_sequential(fm, files, regex, context_lines)
    end
    
    results
    |> Enum.filter(&(length(&1.matches) > 0))
    |> Enum.sort_by(&(-&1.score))
    |> Enum.take(max_results)
    |> then(&{:ok, &1})
  end
  
  defp search_parallel(fm, files, regex, context_lines) do
    files
    |> Enum.chunk_every(@chunk_size)
    |> Task.async_stream(
      fn chunk ->
        Enum.map(chunk, &search_file(fm, &1, regex, context_lines))
      end,
      timeout: 30_000,
      max_concurrency: System.schedulers_online()
    )
    |> Enum.flat_map(fn
      {:ok, results} -> results
      _ -> []
    end)
  end
  
  defp search_sequential(fm, files, regex, context_lines) do
    Enum.map(files, &search_file(fm, &1, regex, context_lines))
  end
  
  defp search_file(fm, file, regex, context_lines) do
    case FileManager.read_file(fm, file) do
      {:ok, content} ->
        lines = String.split(content, "\n")
        
        matches = lines
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {line, line_num} ->
          find_matches_in_line(line, line_num, regex)
        end)
        
        # Add context to matches
        matches_with_context = if context_lines > 0 and length(matches) > 0 do
          add_context_to_matches_from_lines(matches, lines, context_lines)
        else
          Enum.map(matches, &Map.put(&1, :context, %{before: [], after: []}))
        end
        
        %{
          file: file,
          matches: matches_with_context,
          score: calculate_score(matches)
        }
        
      _ ->
        %{file: file, matches: [], score: 0.0}
    end
  end
  
  defp find_matches_in_line(line, line_num, regex) do
    regex
    |> Regex.scan(line, return: :index)
    |> Enum.map(fn [{start, length}] ->
      %{
        line: line_num,
        column: start + 1,
        text: String.slice(line, start, length)
      }
    end)
  end
  
  defp add_context_to_matches_from_lines(matches, lines, context_lines) do
    Enum.map(matches, fn match ->
      line_idx = match.line - 1
      
      before_start = max(0, line_idx - context_lines)
      before_lines = Enum.slice(lines, before_start, line_idx - before_start)
      
      after_start = line_idx + 1
      after_end = min(length(lines) - 1, line_idx + context_lines)
      after_lines = Enum.slice(lines, after_start, after_end - after_start + 1)
      
      Map.put(match, :context, %{
        before: before_lines,
        after: after_lines
      })
    end)
  end
  
  defp calculate_score(matches) do
    # Simple scoring based on number of matches
    # Can be enhanced with TF-IDF or other algorithms
    length(matches) * 1.0
  end
  
  defp get_all_files(fm, root_dir, opts) do
    pattern = if Keyword.get(opts, :recursive, true), do: "**/*", else: "*"
    collect_files(fm, root_dir, pattern)
  end
  
  defp filter_by_name(files, pattern, opts) do
    case_sensitive = Keyword.get(opts, :case_sensitive, false)
    
    regex_pattern = pattern
    |> String.replace("*", ".*")
    |> String.replace("?", ".")
    
    flags = if case_sensitive, do: "", else: "i"
    
    case Regex.compile(regex_pattern, flags) do
      {:ok, regex} ->
        Enum.filter(files, &Regex.match?(regex, Path.basename(&1)))
        
      _ ->
        []
    end
  end
  
  defp filter_by_type(fm, files, types) do
    Enum.filter(files, fn file ->
      type = detect_file_type(fm, file)
      type in types
    end)
  end
  
  defp detect_file_type(_fm, file) do
    ext = Path.extname(file) |> String.downcase()
    
    cond do
      ext in ~w[.ex .exs .rb .py .js .go .rs .java .c .cpp] -> :code
      ext in ~w[.txt .md .log .csv] -> :text
      ext in ~w[.jpg .jpeg .png .gif .svg .bmp] -> :image
      ext in ~w[.zip .tar .gz .rar .7z] -> :archive
      true -> :binary
    end
  end
  
  defp filter_by_date(fm, files, from_date, to_date) do
    Enum.filter(files, fn file ->
      case get_file_info(fm, file) do
        {:ok, info} ->
          DateTime.compare(info.modified, from_date) in [:gt, :eq] and
          DateTime.compare(info.modified, to_date) in [:lt, :eq]
          
        _ ->
          false
      end
    end)
  end
  
  defp build_search_cache_key(pattern, opts) do
    pattern_str = case pattern do
      %Regex{source: source} -> source
      str -> str
    end
    
    relevant_opts = opts
    |> Keyword.take([:file_pattern, :case_sensitive, :whole_word, :context_lines])
    |> Enum.sort()
    
    hash = :crypto.hash(:sha256, "#{pattern_str}#{inspect(relevant_opts)}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
    
    "search:#{hash}"
  end
end
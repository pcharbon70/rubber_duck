defmodule RubberDuck.Tools.TodoExtractor do
  @moduledoc """
  Scans code for TODO, FIXME, and other deferred work comments.
  
  This tool analyzes code to find and categorize comments that indicate
  pending work, technical debt, or issues that need attention.
  """
  
  use RubberDuck.Tool
  
  tool do
    name :todo_extractor
    description "Scans code for TODO, FIXME, and other deferred work comments"
    category :maintenance
    version "1.0.0"
    tags [:maintenance, :debt, :planning, :documentation]
    
    parameter :code do
      type :string
      required false
      description "The code to scan for TODOs"
      default ""
      constraints [
        max_length: 100_000
      ]
    end
    
    parameter :file_path do
      type :string
      required false
      description "Path to file or directory to scan"
      default ""
    end
    
    parameter :patterns do
      type :list
      required false
      description "Custom patterns to search for"
      default ["TODO", "FIXME", "HACK", "BUG", "NOTE", "OPTIMIZE"]
      item_type :string
    end
    
    parameter :include_standard do
      type :boolean
      required false
      description "Include standard TODO patterns"
      default true
    end
    
    parameter :priority_keywords do
      type :list
      required false
      description "Keywords that indicate high priority items"
      default ["URGENT", "CRITICAL", "IMPORTANT", "ASAP"]
      item_type :string
    end
    
    parameter :author_extraction do
      type :boolean
      required false
      description "Try to extract author information from comments"
      default true
    end
    
    parameter :group_by do
      type :string
      required false
      description "How to group the results"
      default "type"
      constraints [
        enum: ["type", "file", "priority", "author", "none"]
      ]
    end
    
    parameter :include_context do
      type :boolean
      required false
      description "Include surrounding code context"
      default true
    end
    
    parameter :context_lines do
      type :integer
      required false
      description "Number of context lines to include"
      default 2
      constraints [
        min: 0,
        max: 10
      ]
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 15_000
      async true
      retries 1
    end
    
    security do
      sandbox :restricted
      capabilities [:file_read]
      rate_limit 100
    end
  end
  
  @doc """
  Executes TODO extraction based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, files_to_scan} <- get_files_to_scan(params, context),
         {:ok, patterns} <- build_search_patterns(params),
         {:ok, extracted} <- extract_todos(files_to_scan, patterns, params),
         {:ok, analyzed} <- analyze_todos(extracted, params),
         {:ok, grouped} <- group_todos(analyzed, params) do
      
      {:ok, %{
        todos: grouped,
        summary: %{
          total_count: length(extracted),
          by_type: count_by_type(extracted),
          by_priority: count_by_priority(analyzed),
          files_scanned: length(files_to_scan)
        },
        statistics: calculate_statistics(analyzed),
        recommendations: generate_recommendations(analyzed)
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp get_files_to_scan(params, context) do
    cond do
      params.code != "" ->
        {:ok, [{"inline_code", params.code}]}
      
      params.file_path != "" ->
        scan_file_path(params.file_path, context)
      
      true ->
        {:error, "Either 'code' or 'file_path' parameter must be provided"}
    end
  end
  
  defp scan_file_path(path, context) do
    full_path = if Path.type(path) == :absolute do
      path
    else
      Path.join(context[:project_root] || File.cwd!(), path)
    end
    
    cond do
      File.regular?(full_path) ->
        case File.read(full_path) do
          {:ok, content} -> {:ok, [{full_path, content}]}
          {:error, reason} -> {:error, "Failed to read file: #{reason}"}
        end
      
      File.dir?(full_path) ->
        scan_directory(full_path)
      
      true ->
        {:error, "Path does not exist: #{full_path}"}
    end
  end
  
  defp scan_directory(dir_path) do
    # Scan for Elixir files
    patterns = ["**/*.ex", "**/*.exs"]
    
    files = patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(dir_path, pattern))
    end)
    |> Enum.uniq()
    
    file_contents = files
    |> Enum.map(fn file ->
      case File.read(file) do
        {:ok, content} -> {file, content}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    
    {:ok, file_contents}
  end
  
  defp build_search_patterns(params) do
    base_patterns = if params.include_standard do
      ["TODO", "FIXME", "HACK", "BUG", "NOTE", "OPTIMIZE", "DEPRECATED", "WARNING"]
    else
      []
    end
    
    all_patterns = (base_patterns ++ params.patterns)
    |> Enum.uniq()
    |> Enum.map(&String.upcase/1)
    
    # Build regex patterns
    comment_patterns = all_patterns
    |> Enum.map(fn pattern ->
      # Match various comment styles
      {
        pattern,
        Regex.compile!("(?:#|//|/\\*|\")\\s*(#{pattern})\\b(.*)$", "mi")
      }
    end)
    
    {:ok, comment_patterns}
  end
  
  defp extract_todos(files, patterns, params) do
    files
    |> Enum.flat_map(fn {file_path, content} ->
      extract_from_content(file_path, content, patterns, params)
    end)
    |> Enum.sort_by(& &1.line_number)
    |> then(&{:ok, &1})
  end
  
  defp extract_from_content(file_path, content, patterns, params) do
    lines = String.split(content, "\n")
    
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      extract_from_line(file_path, line, line_num, patterns, lines, params)
    end)
  end
  
  defp extract_from_line(file_path, line, line_num, patterns, all_lines, params) do
    patterns
    |> Enum.flat_map(fn {pattern_name, regex} ->
      case Regex.run(regex, line) do
        nil -> []
        [full_match, pattern_match, description] ->
          context = if params.include_context do
            extract_context(all_lines, line_num - 1, params.context_lines)
          else
            nil
          end
          
          todo = %{
            type: String.downcase(pattern_name),
            file: file_path,
            line_number: line_num,
            line_content: String.trim(line),
            description: String.trim(description),
            full_match: full_match,
            context: context,
            raw_line: line
          }
          
          [todo]
        
        [full_match, pattern_match] ->
          # Handle case where there's no description
          todo = %{
            type: String.downcase(pattern_name),
            file: file_path,
            line_number: line_num,
            line_content: String.trim(line),
            description: "",
            full_match: full_match,
            context: if(params.include_context, do: extract_context(all_lines, line_num - 1, params.context_lines), else: nil),
            raw_line: line
          }
          
          [todo]
      end
    end)
  end
  
  defp extract_context(lines, current_index, context_lines) do
    start_idx = max(0, current_index - context_lines)
    end_idx = min(length(lines) - 1, current_index + context_lines)
    
    lines
    |> Enum.slice(start_idx..end_idx)
    |> Enum.with_index(start_idx + 1)
    |> Enum.map(fn {line, line_num} ->
      %{
        line_number: line_num,
        content: line,
        is_todo_line: line_num == current_index + 1
      }
    end)
  end
  
  defp analyze_todos(todos, params) do
    todos
    |> Enum.map(fn todo ->
      todo
      |> add_priority_analysis(params)
      |> add_author_analysis(params)
      |> add_complexity_analysis()
      |> add_age_estimation()
    end)
    |> then(&{:ok, &1})
  end
  
  defp add_priority_analysis(todo, params) do
    priority = cond do
      # Check for explicit priority keywords
      Enum.any?(params.priority_keywords, fn keyword ->
        String.contains?(String.upcase(todo.description), String.upcase(keyword))
      end) ->
        :high
      
      # High priority types
      todo.type in ["fixme", "bug", "critical"] ->
        :high
      
      # Medium priority types
      todo.type in ["hack", "optimize", "warning"] ->
        :medium
      
      # Low priority types
      todo.type in ["todo", "note"] ->
        :low
      
      true ->
        :medium
    end
    
    Map.put(todo, :priority, priority)
  end
  
  defp add_author_analysis(todo, params) do
    if params.author_extraction do
      author = extract_author_from_comment(todo.description)
      Map.put(todo, :author, author)
    else
      Map.put(todo, :author, nil)
    end
  end
  
  defp extract_author_from_comment(description) do
    # Look for common author patterns
    patterns = [
      ~r/\@(\w+)/,           # @username
      ~r/\[(\w+)\]/,         # [username]
      ~r/\((\w+)\)/,         # (username)
      ~r/by\s+(\w+)/i,       # by username
      ~r/from\s+(\w+)/i      # from username
    ]
    
    patterns
    |> Enum.find_value(fn pattern ->
      case Regex.run(pattern, description) do
        [_, author] -> author
        _ -> nil
      end
    end)
  end
  
  defp add_complexity_analysis(todo) do
    # Analyze the complexity of the TODO based on description
    complexity = cond do
      # Long descriptions often indicate complex issues
      String.length(todo.description) > 100 -> :complex
      
      # Multiple sentences suggest complexity
      String.contains?(todo.description, [".", ";", "and", "but", "however"]) -> :moderate
      
      # Short, simple descriptions
      String.length(todo.description) < 20 -> :simple
      
      true -> :moderate
    end
    
    Map.put(todo, :complexity, complexity)
  end
  
  defp add_age_estimation(todo) do
    # Simple heuristics for estimating how old a TODO might be
    age_indicators = [
      {"old", ["legacy", "deprecated", "remove", "delete"]},
      {"recent", ["new", "added", "implement", "create"]},
      {"ongoing", ["refactor", "improve", "optimize", "update"]}
    ]
    
    estimated_age = age_indicators
    |> Enum.find_value(fn {age, keywords} ->
      if Enum.any?(keywords, &String.contains?(String.downcase(todo.description), &1)) do
        age
      end
    end) || "unknown"
    
    Map.put(todo, :estimated_age, estimated_age)
  end
  
  defp group_todos(todos, params) do
    grouped = case params.group_by do
      "type" -> Enum.group_by(todos, & &1.type)
      "file" -> Enum.group_by(todos, & &1.file)
      "priority" -> Enum.group_by(todos, & &1.priority)
      "author" -> Enum.group_by(todos, & &1.author)
      "none" -> %{"all" => todos}
    end
    
    {:ok, grouped}
  end
  
  defp count_by_type(todos) do
    todos
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, list} -> {type, length(list)} end)
    |> Enum.into(%{})
  end
  
  defp count_by_priority(todos) do
    todos
    |> Enum.group_by(& &1.priority)
    |> Enum.map(fn {priority, list} -> {priority, length(list)} end)
    |> Enum.into(%{})
  end
  
  defp calculate_statistics(todos) do
    total = length(todos)
    
    complexity_distribution = todos
    |> Enum.group_by(& &1.complexity)
    |> Enum.map(fn {complexity, list} -> {complexity, length(list)} end)
    |> Enum.into(%{})
    
    files_with_todos = todos
    |> Enum.map(& &1.file)
    |> Enum.uniq()
    |> length()
    
    avg_description_length = if total > 0 do
      todos
      |> Enum.map(&String.length(&1.description))
      |> Enum.sum()
      |> div(total)
    else
      0
    end
    
    %{
      total_todos: total,
      complexity_distribution: complexity_distribution,
      files_with_todos: files_with_todos,
      avg_description_length: avg_description_length,
      has_high_priority: Enum.any?(todos, &(&1.priority == :high)),
      authors_found: todos |> Enum.map(& &1.author) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length()
    }
  end
  
  defp generate_recommendations(todos) do
    recommendations = []
    
    high_priority_count = Enum.count(todos, &(&1.priority == :high))
    recommendations = if high_priority_count > 0 do
      ["Address #{high_priority_count} high-priority items first" | recommendations]
    else
      recommendations
    end
    
    # Check for old TODOs
    old_todos = Enum.filter(todos, &(&1.estimated_age == "old"))
    recommendations = if length(old_todos) > 5 do
      ["Consider cleaning up #{length(old_todos)} potentially outdated TODOs" | recommendations]
    else
      recommendations
    end
    
    # Check for files with many TODOs
    file_counts = todos
    |> Enum.group_by(& &1.file)
    |> Enum.map(fn {file, list} -> {file, length(list)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    
    case file_counts do
      [{file, count} | _] when count > 10 ->
        filename = Path.basename(file)
        ["File #{filename} has #{count} TODOs - consider refactoring" | recommendations]
      _ ->
        recommendations
    end
    
    # Check for complex TODOs
    complex_todos = Enum.filter(todos, &(&1.complexity == :complex))
    recommendations = if length(complex_todos) > 0 do
      ["Break down #{length(complex_todos)} complex TODOs into smaller tasks" | recommendations]
    else
      recommendations
    end
    
    Enum.reverse(recommendations)
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
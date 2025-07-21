defmodule RubberDuck.Analysis.CodeAnalyzer do
  @moduledoc """
  Analyzes code files to extract metrics, symbols, and other insights.
  
  Provides:
  - Symbol extraction (functions, modules, types)
  - Complexity calculations
  - Dependency analysis
  - Documentation extraction
  """
  
  require Logger
  
  @doc """
  Analyzes a file and returns comprehensive analysis data.
  """
  def analyze_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        extension = Path.extname(file_path)
        
        analysis = %{
          lines: count_lines(content),
          function_count: 0,
          complexity: 0,
          symbols: [],
          dependencies: [],
          issues: []
        }
        
        # Language-specific analysis
        case extension do
          ext when ext in [".ex", ".exs"] ->
            analyze_elixir(content, analysis)
          ext when ext in [".js", ".jsx", ".ts", ".tsx"] ->
            analyze_javascript(content, analysis)
          ext when ext in [".py"] ->
            analyze_python(content, analysis)
          _ ->
            {:ok, analysis}
        end
        
      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end
  
  @doc """
  Extracts symbols from a file for outline display.
  """
  def extract_symbols(file_path) do
    case analyze_file(file_path) do
      {:ok, analysis} ->
        {:ok, analysis.symbols}
      error ->
        error
    end
  end
  
  @doc """
  Finds files related to the given file.
  """
  def find_related_files(file_path, project_path) do
    basename = Path.basename(file_path, Path.extname(file_path))
    dirname = Path.dirname(file_path)
    
    # Test files
    test_patterns = [
      "test/**/#{basename}_test.exs",
      "test/**/#{basename}_test.ex",
      "spec/**/#{basename}_spec.js",
      "**/__tests__/#{basename}.test.js"
    ]
    
    test_related = 
      Enum.reduce(test_patterns, [], fn pattern, acc ->
        case Path.wildcard(Path.join(project_path, pattern)) do
          [] -> acc
          files -> 
            Enum.map(files, fn f -> 
              %{path: Path.relative_to(f, project_path), relationship: :test}
            end) ++ acc
        end
      end)
    
    # Implementation/interface files
    impl_related = 
      if String.ends_with?(basename, "_test") || String.ends_with?(basename, "_spec") do
        impl_name = String.replace(basename, ~r/_(test|spec)$/, "")
        impl_patterns = [
          "lib/**/#{impl_name}.ex",
          "lib/**/#{impl_name}.exs",
          "src/**/#{impl_name}.js"
        ]
        
        Enum.reduce(impl_patterns, [], fn pattern, acc ->
          case Path.wildcard(Path.join(project_path, pattern)) do
            [] -> acc
            files -> 
              Enum.map(files, fn f -> 
                %{path: Path.relative_to(f, project_path), relationship: :implementation}
              end) ++ acc
          end
        end)
      else
        []
      end
    
    # Similar named files in same directory
    similar_related =
      case File.ls(dirname) do
        {:ok, files} ->
          files
          |> Enum.filter(fn f -> 
            f != Path.basename(file_path) && String.contains?(f, basename)
          end)
          |> Enum.map(fn f -> 
            %{path: Path.join(Path.relative_to(dirname, project_path), f), relationship: :similar}
          end)
        _ ->
          []
      end
    
    (test_related ++ impl_related ++ similar_related)
    |> Enum.take(10)
  end
  
  @doc """
  Calculates code complexity metrics.
  """
  def calculate_complexity(content, language \\ :elixir) do
    lines = String.split(content, "\n")
    
    # Basic cyclomatic complexity calculation
    cyclomatic = calculate_cyclomatic_complexity(lines, language)
    
    # Cognitive complexity (simplified)
    cognitive = calculate_cognitive_complexity(lines, language)
    
    %{
      cyclomatic: cyclomatic,
      cognitive: cognitive,
      lines_of_code: count_code_lines(lines),
      comment_ratio: calculate_comment_ratio(lines)
    }
  end
  
  # Private Functions
  
  defp count_lines(content) do
    content
    |> String.split("\n")
    |> length()
  end
  
  defp count_code_lines(lines) do
    lines
    |> Enum.reject(&empty_or_comment?/1)
    |> length()
  end
  
  defp empty_or_comment?(line) do
    trimmed = String.trim(line)
    trimmed == "" || String.starts_with?(trimmed, "#") || String.starts_with?(trimmed, "//")
  end
  
  defp calculate_comment_ratio(lines) do
    comment_lines = Enum.count(lines, fn line ->
      trimmed = String.trim(line)
      String.starts_with?(trimmed, "#") || String.starts_with?(trimmed, "//")
    end)
    
    total_lines = length(lines)
    
    if total_lines > 0 do
      Float.round(comment_lines / total_lines * 100, 1)
    else
      0.0
    end
  end
  
  defp calculate_cyclomatic_complexity(lines, :elixir) do
    # Count decision points
    Enum.reduce(lines, 1, fn line, acc ->
      cond do
        String.contains?(line, ["if ", "unless ", "cond do"]) -> acc + 1
        String.contains?(line, "case ") && String.contains?(line, " do") -> acc + 1
        String.contains?(line, "->") -> acc + 1
        true -> acc
      end
    end)
  end
  
  defp calculate_cyclomatic_complexity(lines, _) do
    # Generic complexity for other languages
    Enum.reduce(lines, 1, fn line, acc ->
      cond do
        String.contains?(line, ["if ", "else if", "elif"]) -> acc + 1
        String.contains?(line, ["for ", "while ", "switch "]) -> acc + 1
        String.contains?(line, "catch ") -> acc + 1
        true -> acc
      end
    end)
  end
  
  defp calculate_cognitive_complexity(lines, _language) do
    # Simplified cognitive complexity
    nesting_level = 0
    
    Enum.reduce(lines, 0, fn line, acc ->
      # Track nesting
      opens = length(Regex.scan(~r/\bdo\b|\{/, line))
      closes = length(Regex.scan(~r/\bend\b|\}/, line))
      nesting_level = nesting_level + opens - closes
      
      # Add complexity for nested structures
      if String.contains?(line, ["if ", "case ", "for ", "while "]) do
        acc + 1 + nesting_level
      else
        acc
      end
    end)
  end
  
  defp analyze_elixir(content, analysis) do
    lines = String.split(content, "\n")
    
    # Extract symbols
    symbols = extract_elixir_symbols(lines)
    
    # Count functions
    function_count = Enum.count(symbols, &(&1.type == :function))
    
    # Calculate complexity
    complexity_metrics = calculate_complexity(content, :elixir)
    
    # Extract dependencies
    dependencies = extract_elixir_dependencies(lines)
    
    {:ok, %{analysis | 
      symbols: symbols,
      function_count: function_count,
      complexity: complexity_metrics.cyclomatic,
      dependencies: dependencies
    }}
  end
  
  defp extract_elixir_symbols(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      cond do
        # Module definitions
        match = Regex.run(~r/^\s*defmodule\s+([A-Z]\w+(?:\.\w+)*)\s+do/, line) ->
          [%{type: :module, name: Enum.at(match, 1), line: line_num}]
          
        # Function definitions
        match = Regex.run(~r/^\s*def(?:p)?\s+(\w+)/, line) ->
          [%{type: :function, name: Enum.at(match, 1), line: line_num}]
          
        # Macro definitions
        match = Regex.run(~r/^\s*defmacro(?:p)?\s+(\w+)/, line) ->
          [%{type: :macro, name: Enum.at(match, 1), line: line_num}]
          
        # Type definitions
        match = Regex.run(~r/^\s*@type\s+(\w+)/, line) ->
          [%{type: :type, name: Enum.at(match, 1), line: line_num}]
          
        # Struct definitions
        String.contains?(line, "defstruct") ->
          [%{type: :struct, name: "struct", line: line_num}]
          
        true ->
          []
      end
    end)
  end
  
  defp extract_elixir_dependencies(lines) do
    lines
    |> Enum.flat_map(fn line ->
      cond do
        # Alias statements
        match = Regex.run(~r/^\s*alias\s+([A-Z]\w+(?:\.\w+)*)/, line) ->
          [%{type: :alias, module: Enum.at(match, 1)}]
          
        # Import statements
        match = Regex.run(~r/^\s*import\s+([A-Z]\w+(?:\.\w+)*)/, line) ->
          [%{type: :import, module: Enum.at(match, 1)}]
          
        # Use statements
        match = Regex.run(~r/^\s*use\s+([A-Z]\w+(?:\.\w+)*)/, line) ->
          [%{type: :use, module: Enum.at(match, 1)}]
          
        true ->
          []
      end
    end)
    |> Enum.uniq()
  end
  
  defp analyze_javascript(content, analysis) do
    lines = String.split(content, "\n")
    
    # Extract symbols (simplified)
    symbols = extract_javascript_symbols(lines)
    
    # Count functions
    function_count = Enum.count(symbols, &(&1.type == :function))
    
    # Calculate complexity
    complexity_metrics = calculate_complexity(content, :javascript)
    
    {:ok, %{analysis | 
      symbols: symbols,
      function_count: function_count,
      complexity: complexity_metrics.cyclomatic
    }}
  end
  
  defp extract_javascript_symbols(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      cond do
        # Function declarations
        match = Regex.run(~r/^\s*(?:async\s+)?function\s+(\w+)/, line) ->
          [%{type: :function, name: Enum.at(match, 1), line: line_num}]
          
        # Arrow functions assigned to const/let/var
        match = Regex.run(~r/^\s*(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\(/, line) ->
          [%{type: :function, name: Enum.at(match, 1), line: line_num}]
          
        # Class declarations
        match = Regex.run(~r/^\s*class\s+(\w+)/, line) ->
          [%{type: :class, name: Enum.at(match, 1), line: line_num}]
          
        # Method definitions
        match = Regex.run(~r/^\s*(?:async\s+)?(\w+)\s*\(/, line) ->
          if !String.contains?(line, ["if", "for", "while", "switch"]) do
            [%{type: :method, name: Enum.at(match, 1), line: line_num}]
          else
            []
          end
          
        true ->
          []
      end
    end)
  end
  
  defp analyze_python(content, analysis) do
    lines = String.split(content, "\n")
    
    # Extract symbols (simplified)
    symbols = extract_python_symbols(lines)
    
    # Count functions
    function_count = Enum.count(symbols, &(&1.type in [:function, :method]))
    
    # Calculate complexity
    complexity_metrics = calculate_complexity(content, :python)
    
    {:ok, %{analysis | 
      symbols: symbols,
      function_count: function_count,
      complexity: complexity_metrics.cyclomatic
    }}
  end
  
  defp extract_python_symbols(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      cond do
        # Class definitions
        match = Regex.run(~r/^\s*class\s+(\w+)/, line) ->
          [%{type: :class, name: Enum.at(match, 1), line: line_num}]
          
        # Function/method definitions
        match = Regex.run(~r/^\s*def\s+(\w+)/, line) ->
          type = if String.starts_with?(String.trim(line), "def"), do: :function, else: :method
          [%{type: type, name: Enum.at(match, 1), line: line_num}]
          
        true ->
          []
      end
    end)
  end
end
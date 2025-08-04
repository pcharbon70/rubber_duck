#!/usr/bin/env elixir

# Script to analyze and categorize all Actions by risk level

defmodule ActionAnalyzer do
  @moduledoc """
  Analyzes all Action modules and categorizes them by risk level based on
  the operations they perform.
  """
  
  def run do
    IO.puts("Analyzing Actions for error handling requirements...\n")
    
    # Find all Action files
    action_files = find_action_files()
    IO.puts("Found #{length(action_files)} Action files\n")
    
    # Categorize actions
    categorized = categorize_actions(action_files)
    
    # Print results
    print_categories(categorized)
    
    # Generate summary
    generate_summary(categorized)
  end
  
  defp find_action_files do
    paths = [
      "lib/rubber_duck/agents/**/*_agent.ex",
      "lib/rubber_duck/tools/agents/**/*_agent.ex",
      "lib/rubber_duck/jido/actions/**/*_action.ex"
    ]
    
    paths
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(fn path ->
      content = File.read!(path)
      String.contains?(content, "defmodule") && 
      (String.contains?(content, "Action do") || String.contains?(content, "use Jido.Action"))
    end)
    |> Enum.sort()
  end
  
  defp categorize_actions(files) do
    files
    |> Enum.map(&analyze_file/1)
    |> Enum.group_by(& &1.risk_level)
  end
  
  defp analyze_file(path) do
    content = File.read!(path)
    module_name = extract_module_name(content)
    
    # Determine risk level based on operations
    risk_level = determine_risk_level(path, content)
    
    # Check for existing error handling
    has_error_handling = check_error_handling(content)
    
    %{
      path: path,
      module: module_name,
      risk_level: risk_level,
      has_error_handling: has_error_handling,
      operations: detect_operations(content)
    }
  end
  
  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([\w\.]+)/, content) do
      [_, module] -> module
      _ -> "Unknown"
    end
  end
  
  defp determine_risk_level(path, content) do
    cond do
      # Critical - External service interactions, financial operations
      String.contains?(path, ["provider", "token", "payment", "billing"]) ->
        :critical
      
      # Critical - Database/storage operations
      String.contains?(content, ["Memory.", "Database.", "Repo.", "storage"]) ->
        :critical
      
      # High - Analysis and generation with LLM calls
      String.contains?(path, ["analysis", "generation", "llm", "ai"]) ->
        :high
      
      # High - Network operations
      String.contains?(content, ["HTTPoison", "HTTP.", "API.", "request"]) ->
        :high
      
      # High - File system operations
      String.contains?(content, ["File.", "Path.", "IO."]) ->
        :high
      
      # Medium - Context and response processing
      String.contains?(path, ["context", "response", "conversation", "prompt"]) ->
        :medium
      
      # Medium - Async operations
      String.contains?(content, ["Task.", "async", "spawn"]) ->
        :medium
      
      # Low - Simple state updates and metrics
      String.contains?(path, ["metric", "stats", "update", "get"]) ->
        :low
      
      # Default to medium
      true ->
        :medium
    end
  end
  
  defp check_error_handling(content) do
    error_patterns = [
      "rescue",
      "try do",
      "with ",
      "{:error,",
      "ErrorHandling",
      "safe_execute"
    ]
    
    Enum.any?(error_patterns, &String.contains?(content, &1))
  end
  
  defp detect_operations(content) do
    operations = []
    
    operations = if String.contains?(content, ["File.", "Path."]), 
      do: ["file_io" | operations], else: operations
    
    operations = if String.contains?(content, ["HTTPoison", "HTTP."]), 
      do: ["http" | operations], else: operations
    
    operations = if String.contains?(content, ["Repo.", "Database."]), 
      do: ["database" | operations], else: operations
    
    operations = if String.contains?(content, ["Task.", "async"]), 
      do: ["async" | operations], else: operations
    
    operations = if String.contains?(content, ["GenServer.call"]), 
      do: ["genserver" | operations], else: operations
    
    operations = if String.contains?(content, ["JSON.", "Jason."]), 
      do: ["json" | operations], else: operations
    
    operations
  end
  
  defp print_categories(categorized) do
    [:critical, :high, :medium, :low]
    |> Enum.each(fn level ->
      actions = Map.get(categorized, level, [])
      
      IO.puts("\n#{String.upcase(to_string(level))} RISK (#{length(actions)} actions)")
      IO.puts(String.duplicate("=", 60))
      
      actions
      |> Enum.sort_by(& &1.path)
      |> Enum.each(fn action ->
        status = if action.has_error_handling, do: "✓", else: "✗"
        ops = if action.operations != [], 
          do: " [#{Enum.join(action.operations, ", ")}]", 
          else: ""
        
        # Extract relative path
        rel_path = String.replace(action.path, ~r/^lib\/rubber_duck\//, "")
        IO.puts("  #{status} #{rel_path}#{ops}")
      end)
    end)
  end
  
  defp generate_summary(categorized) do
    total = categorized |> Map.values() |> List.flatten() |> length()
    
    with_error_handling = categorized
    |> Map.values()
    |> List.flatten()
    |> Enum.count(& &1.has_error_handling)
    
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("SUMMARY")
    IO.puts(String.duplicate("=", 60))
    
    [:critical, :high, :medium, :low]
    |> Enum.each(fn level ->
      actions = Map.get(categorized, level, [])
      with_handling = Enum.count(actions, & &1.has_error_handling)
      percentage = if length(actions) > 0, 
        do: Float.round(with_handling / length(actions) * 100, 1),
        else: 0.0
      
      IO.puts("#{String.capitalize(to_string(level))}: #{length(actions)} actions (#{with_handling}/#{length(actions)} with error handling - #{percentage}%)")
    end)
    
    IO.puts("\nTotal: #{total} actions")
    IO.puts("With error handling: #{with_error_handling}/#{total} (#{Float.round(with_error_handling / total * 100, 1)}%)")
    IO.puts("Need error handling: #{total - with_error_handling} actions")
  end
end

# Run the analyzer
ActionAnalyzer.run()
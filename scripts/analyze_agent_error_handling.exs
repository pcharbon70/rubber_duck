#!/usr/bin/env elixir

# Script to analyze how agents currently handle Action errors

defmodule AgentErrorAnalyzer do
  @moduledoc """
  Analyzes all Agent modules to determine their current error handling patterns
  when calling Actions.
  """
  
  def run do
    IO.puts("Analyzing Agent error handling patterns...\n")
    
    # Find all Agent files
    agent_files = find_agent_files()
    IO.puts("Found #{length(agent_files)} Agent files\n")
    
    # Analyze error handling patterns
    analysis = analyze_agents(agent_files)
    
    # Print results
    print_analysis(analysis)
    
    # Generate recommendations
    generate_recommendations(analysis)
  end
  
  defp find_agent_files do
    paths = [
      "lib/rubber_duck/agents/**/*_agent.ex",
      "lib/rubber_duck/tools/agents/**/*_agent.ex"
    ]
    
    paths
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(fn path ->
      content = File.read!(path)
      String.contains?(content, "defmodule") && 
      (String.contains?(content, "Agent") || String.contains?(content, "use Jido.Agent"))
    end)
    |> Enum.sort()
  end
  
  defp analyze_agents(files) do
    files
    |> Enum.map(&analyze_agent_file/1)
    |> Enum.group_by(& &1.error_handling_level)
  end
  
  defp analyze_agent_file(path) do
    content = File.read!(path)
    module_name = extract_module_name(content)
    
    # Analyze different error handling patterns
    patterns = detect_error_patterns(content)
    level = determine_error_level(patterns)
    
    %{
      path: path,
      module: module_name,
      error_handling_level: level,
      patterns: patterns,
      action_calls: count_action_calls(content),
      signal_handling: has_signal_handling(content),
      base_agent_type: determine_base_type(content)
    }
  end
  
  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([\w\.]+)/, content) do
      [_, module] -> module
      _ -> "Unknown"
    end
  end
  
  defp detect_error_patterns(content) do
    patterns = []
    
    # Check for ErrorHandling usage
    patterns = if String.contains?(content, "ErrorHandling"), 
      do: ["error_handling_module" | patterns], else: patterns
    
    # Check for try/rescue blocks
    patterns = if String.contains?(content, "rescue"), 
      do: ["try_rescue" | patterns], else: patterns
    
    # Check for with statements
    patterns = if String.contains?(content, "with "), 
      do: ["with_statements" | patterns], else: patterns
    
    # Check for case statements on Action results
    patterns = if Regex.match?(~r/case\s+\w+Action\.run/, content), 
      do: ["case_action_results" | patterns], else: patterns
    
    # Check for direct Action.run calls without error handling
    direct_calls = Regex.scan(~r/\w+Action\.run\([^)]+\)/, content)
    patterns = if length(direct_calls) > 0, 
      do: ["direct_action_calls" | patterns], else: patterns
    
    # Check for {:error, _} pattern matching
    patterns = if String.contains?(content, "{:error,"), 
      do: ["error_tuple_handling" | patterns], else: patterns
    
    # Check for Logger usage
    patterns = if String.contains?(content, "Logger."), 
      do: ["logging" | patterns], else: patterns
    
    patterns
  end
  
  defp determine_error_level(patterns) do
    cond do
      "error_handling_module" in patterns -> :comprehensive
      length(patterns) >= 4 -> :good
      length(patterns) >= 2 -> :basic
      length(patterns) >= 1 -> :minimal
      true -> :none
    end
  end
  
  defp count_action_calls(content) do
    # Count Action.run calls
    direct_calls = Regex.scan(~r/\w+Action\.run\([^)]+\)/, content) |> length()
    
    # Count handle_signal patterns that likely call Actions
    signal_patterns = Regex.scan(~r/def handle_signal.*Action/, content) |> length()
    
    %{
      direct_calls: direct_calls,
      signal_patterns: signal_patterns,
      total_estimated: direct_calls + signal_patterns
    }
  end
  
  defp has_signal_handling(content) do
    String.contains?(content, "handle_signal") || String.contains?(content, "@impl")
  end
  
  defp determine_base_type(content) do
    cond do
      String.contains?(content, "use RubberDuck.Agents.BaseAgent") -> :base_agent
      String.contains?(content, "use RubberDuck.Tools.Agents.BaseToolAgent") -> :base_tool_agent
      String.contains?(content, "use Jido.Agent") -> :jido_agent
      true -> :unknown
    end
  end
  
  defp print_analysis(analysis) do
    [:comprehensive, :good, :basic, :minimal, :none]
    |> Enum.each(fn level ->
      agents = Map.get(analysis, level, [])
      
      IO.puts("\n#{String.upcase(to_string(level))} ERROR HANDLING (#{length(agents)} agents)")
      IO.puts(String.duplicate("=", 60))
      
      agents
      |> Enum.sort_by(& &1.path)
      |> Enum.each(fn agent ->
        rel_path = String.replace(agent.path, ~r/^lib\/rubber_duck\//, "")
        action_info = if agent.action_calls.total_estimated > 0, 
          do: " [#{agent.action_calls.total_estimated} action calls]", 
          else: ""
        patterns_info = if agent.patterns != [], 
          do: " (#{Enum.join(agent.patterns, ", ")})", 
          else: ""
        
        IO.puts("  #{agent.base_agent_type} #{rel_path}#{action_info}#{patterns_info}")
      end)
    end)
  end
  
  defp generate_recommendations(analysis) do
    total = analysis |> Map.values() |> List.flatten() |> length()
    
    comprehensive = length(Map.get(analysis, :comprehensive, []))
    good = length(Map.get(analysis, :good, []))
    basic = length(Map.get(analysis, :basic, []))
    minimal = length(Map.get(analysis, :minimal, []))
    none = length(Map.get(analysis, :none, []))
    
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("ANALYSIS SUMMARY")
    IO.puts(String.duplicate("=", 60))
    
    IO.puts("Comprehensive: #{comprehensive}/#{total} (#{Float.round(comprehensive / total * 100, 1)}%)")
    IO.puts("Good: #{good}/#{total} (#{Float.round(good / total * 100, 1)}%)")
    IO.puts("Basic: #{basic}/#{total} (#{Float.round(basic / total * 100, 1)}%)")
    IO.puts("Minimal: #{minimal}/#{total} (#{Float.round(minimal / total * 100, 1)}%)")
    IO.puts("None: #{none}/#{total} (#{Float.round(none / total * 100, 1)}%)")
    
    need_improvement = total - comprehensive
    IO.puts("\nAgents needing error handling improvements: #{need_improvement}/#{total}")
    
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("RECOMMENDATIONS")
    IO.puts(String.duplicate("=", 60))
    
    if none > 0 do
      IO.puts("🔴 CRITICAL: #{none} agents have no error handling - implement basic patterns")
    end
    
    if minimal > 0 do
      IO.puts("🟡 HIGH: #{minimal} agents have minimal error handling - add structured error handling")
    end
    
    if basic > 0 do
      IO.puts("🟡 MEDIUM: #{basic} agents have basic error handling - enhance with ErrorHandling module")
    end
    
    if good > 0 do
      IO.puts("🟢 LOW: #{good} agents have good error handling - migrate to ErrorHandling module")
    end
    
    IO.puts("\nImplementation Priority:")
    IO.puts("1. Agents with no error handling (#{none} agents)")
    IO.puts("2. Agents with high action call counts")
    IO.puts("3. Critical system agents (memory, token, provider)")
    IO.puts("4. Tool agents with external dependencies")
  end
end

# Run the analyzer
AgentErrorAnalyzer.run()
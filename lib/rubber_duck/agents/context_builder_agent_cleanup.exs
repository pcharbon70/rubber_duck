#!/usr/bin/env elixir
# Script to comment out unused functions in context_builder_agent.ex

defmodule ContextBuilderCleanup do
  def run do
    file_path = "lib/rubber_duck/agents/context_builder_agent.ex"
    content = File.read!(file_path)
    
    # List of functions that should be kept (they are used)
    keep_functions = [
      "initialize_default_sources",
      "schedule_cache_cleanup",
      "string_to_atom",
      "extract_"  # All extract_ functions are used for parameter extraction
    ]
    
    # List of definitely unused functions to comment out
    comment_functions = [
      "build_context_request",
      "build_new_context",
      "gather_source_contexts",
      "fetch_from_source",
      "fetch_memory_context",
      "fetch_code_context",
      "fetch_doc_context",
      "fetch_conversation_context",
      "fetch_planning_context",
      "fetch_custom_context",
      "prioritize_context_entries",
      "calculate_entry_score",
      "calculate_recency_score",
      "calculate_importance_score",
      "matches_preferences?",
      "optimize_context",
      "deduplicate_entries",
      "similar_entry_exists?",
      "similarity_score",
      "apply_compression",
      "apply_summarization",
      "truncate_to_limit",
      "get_cached_context",
      "cache_context",
      "context_still_valid?",
      "evict_oldest_cache_entry",
      "invalidate_cache_entries",
      "invalidate_source_cache",
      "start_streaming_build",
      "determine_sources",
      "build_code_entries",
      "apply_context_updates",
      "build_context_metadata",
      "calculate_total_tokens",
      "find_oldest_timestamp",
      "find_newest_timestamp",
      "content_to_string",
      "update_build_metrics",
      "calculate_cache_hit_rate"
    ]
    
    # Process the content
    lines = String.split(content, "\n")
    inside_function = false
    current_function = nil
    indent_level = 0
    
    processed_lines = Enum.map(lines, fn line ->
      cond do
        # Check if we're starting a function definition
        String.match?(line, ~r/^\s*defp\s+(\w+)/) ->
          func_match = Regex.run(~r/defp\s+(\w+)/, line)
          if func_match do
            func_name = Enum.at(func_match, 1)
            should_comment = Enum.any?(comment_functions, &String.starts_with?(func_name, &1))
            
            if should_comment do
              inside_function = true
              current_function = func_name
              indent_level = String.length(line) - String.length(String.trim_leading(line))
              "  # " <> String.trim_leading(line)
            else
              inside_function = false
              line
            end
          else
            line
          end
        
        # Check if we're ending a function
        inside_function && String.trim(line) == "end" && 
          String.length(line) - String.length(String.trim_leading(line)) == indent_level ->
          inside_function = false
          current_function = nil
          "  # " <> String.trim_leading(line)
        
        # Comment out lines inside unused functions
        inside_function ->
          "  # " <> String.trim_leading(line)
        
        true ->
          line
      end
    end)
    
    new_content = Enum.join(processed_lines, "\n")
    File.write!(file_path <> ".new", new_content)
    
    IO.puts("Created #{file_path}.new with unused functions commented out")
    IO.puts("Review the file and rename it to replace the original")
  end
end

ContextBuilderCleanup.run()
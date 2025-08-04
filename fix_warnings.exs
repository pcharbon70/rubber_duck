#!/usr/bin/env elixir

# Script to fix warnings across the codebase

defmodule WarningFixer do
  def fix_all do
    IO.puts("Fixing warnings in multiple files...")
    
    # Fix context_builder_agent.ex - remove unused functions section
    fix_context_builder_agent()
    
    # Fix unused variables by prefixing with underscore
    fix_unused_variables()
    
    # Fix unused aliases
    fix_unused_aliases()
    
    IO.puts("Done fixing warnings!")
  end
  
  def fix_context_builder_agent do
    IO.puts("Fixing context_builder_agent.ex...")
    
    file = "lib/rubber_duck/agents/context_builder_agent.ex"
    content = File.read!(file)
    
    # Remove the entire legacy functions section (lines 279-867 approximately)
    # These are all unused after the Action migration
    lines = String.split(content, "\n")
    
    # Find the start and end of the unused section
    start_idx = Enum.find_index(lines, &String.contains?(&1, "## Private Functions - Context Building"))
    end_idx = Enum.find_index(lines, &String.contains?(&1, "defp schedule_cache_cleanup"))
    
    if start_idx && end_idx do
      # Keep lines before the unused section and after schedule_cache_cleanup
      new_lines = Enum.slice(lines, 0, start_idx) ++ 
                  ["  ## Private Functions", ""] ++
                  Enum.slice(lines, end_idx - 1, length(lines))
      
      new_content = Enum.join(new_lines, "\n")
      File.write!(file, new_content)
      IO.puts("  Removed unused legacy functions from context_builder_agent.ex")
    end
  end
  
  def fix_unused_variables do
    IO.puts("Fixing unused variables...")
    
    files_and_fixes = [
      {"lib/rubber_duck/agents/migration/action_generator.ex", 
       [{"agent_module,", "_agent_module,"}]},
      {"lib/rubber_duck/agents/migration/scripts.ex",
       [{"agent_code =", "_agent_code ="}]},
      {"lib/rubber_duck/jido/actions/analysis/code_analysis_action.ex",
       [{"defp update_cache(agent,", "defp update_cache(_agent,"},
        {"result) do", "_result) do"}]},
      {"lib/rubber_duck/jido/actions/analysis/security_review_action.ex",
       [{"defp scan_dependencies(agent)", "defp scan_dependencies(_agent)"}]},
      {"lib/rubber_duck/jido/actions/generation/post_processing_action.ex",
       [{"optimizations = []", "_optimizations = []"},
        {"optimized_code = code", "_optimized_code = code"},
        {"defp extract_public_functions(ast)", "defp extract_public_functions(_ast)"}]},
      {"lib/rubber_duck/jido/actions/generation/template_render_action.ex",
       [{"def run(params, context)", "def run(params, _context)"}]},
      {"lib/rubber_duck/jido/actions/provider/provider_failover_action.ex",
       [{"defp analyze_failure_patterns(agent, params)", "defp analyze_failure_patterns(agent, _params)"}]},
      {"lib/rubber_duck/jido/actions/provider/provider_health_check_action.ex",
       [{"defp calculate_health_score(basic_health, provider_metrics, connectivity)",
         "defp calculate_health_score(basic_health, _provider_metrics, connectivity)"},
        {"defp generate_recommendations(basic_health, provider_metrics, connectivity)",
         "defp generate_recommendations(basic_health, _provider_metrics, connectivity)"}]},
      {"lib/rubber_duck/jido/actions/provider/provider_rate_limit_action.ex",
       [{"updated_agent =", "_updated_agent ="},
        {"defp calculate_performance_metrics(rate_limiter, metrics, now)",
         "defp calculate_performance_metrics(rate_limiter, metrics, _now)"},
        {"defp generate_rate_limit_recommendations(performance_metrics, rate_limiter)",
         "defp generate_rate_limit_recommendations(performance_metrics, _rate_limiter)"},
        {"defp should_auto_adjust?(performance_metrics, rate_limiter)",
         "defp should_auto_adjust?(performance_metrics, _rate_limiter)"},
        {"defp calculate_requests_per_second(metrics, rate_limiter)",
         "defp calculate_requests_per_second(_metrics, rate_limiter)"}]}
    ]
    
    Enum.each(files_and_fixes, fn {file, fixes} ->
      if File.exists?(file) do
        content = File.read!(file)
        new_content = Enum.reduce(fixes, content, fn {from, to}, acc ->
          String.replace(acc, from, to)
        end)
        File.write!(file, new_content)
        IO.puts("  Fixed unused variables in #{file}")
      end
    end)
  end
  
  def fix_unused_aliases do
    IO.puts("Fixing unused aliases...")
    
    files_and_fixes = [
      {"lib/rubber_duck/jido/actions/code_analysis/code_analysis_request_action.ex",
       [{"alias RubberDuck.CoT.Chains.AnalysisChain", "# alias RubberDuck.CoT.Chains.AnalysisChain"},
        {"alias RubberDuck.CoT.Manager, as: ConversationManager", "# alias RubberDuck.CoT.Manager, as: ConversationManager"}]},
      {"lib/rubber_duck/jido/actions/provider/provider_config_update_action.ex",
       [{"alias RubberDuck.LLM.{ProviderConfig, ConfigLoader}", "# alias RubberDuck.LLM.{ProviderConfig, ConfigLoader}"},
        {"alias RubberDuck.Jido.Actions.Base.UpdateStateAction", "# alias RubberDuck.Jido.Actions.Base.UpdateStateAction"}]},
      {"lib/rubber_duck/jido/actions/provider/provider_health_check_action.ex",
       [{"alias RubberDuck.LLM.{ProviderConfig, ConfigLoader}", "# alias RubberDuck.LLM.{ProviderConfig, ConfigLoader}"}]},
      {"lib/rubber_duck/jido/actions/provider/provider_request_action.ex",
       [{"alias RubberDuck.LLM.{Request, Response}", "alias RubberDuck.LLM.Request"}]}
    ]
    
    Enum.each(files_and_fixes, fn {file, fixes} ->
      if File.exists?(file) do
        content = File.read!(file)
        new_content = Enum.reduce(fixes, content, fn {from, to}, acc ->
          String.replace(acc, from, to)
        end)
        File.write!(file, new_content)
        IO.puts("  Fixed unused aliases in #{file}")
      end
    end)
  end
end

WarningFixer.fix_all()
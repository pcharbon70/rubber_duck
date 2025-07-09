defmodule RubberDuck.Engines do
  @moduledoc """
  Engine configuration for RubberDuck using the EngineSystem DSL.

  This module defines all available engines and their configurations,
  including capabilities, resource limits, and metadata.
  """

  use RubberDuck.EngineSystem

  engines do
    engine :generation do
      module RubberDuck.Engines.Generation
      description "Generates code from natural language descriptions using LLMs"
      priority(100)
      timeout 30_000

      config(
        max_tokens: 4096,
        temperature: 0.7,
        capabilities: [:code_generation, :natural_language_processing, :multi_language_support],
        tags: [:llm, :generation, :rag_enabled]
      )
    end

    engine :completion do
      module RubberDuck.Engines.Completion
      description "Provides intelligent code completions based on context"
      priority(90)
      timeout 10_000

      config(
        max_tokens: 1024,
        temperature: 0.3,
        streaming: true,
        capabilities: [:code_completion, :context_aware, :multi_language_support],
        tags: [:llm, :completion, :streaming]
      )
    end

    engine :analysis do
      module RubberDuck.Engines.Analysis
      description "Analyzes code for issues, patterns, and improvements"
      priority(80)
      timeout 20_000

      config(
        max_tokens: 2048,
        temperature: 0.2,
        capabilities: [:code_analysis, :security_scanning, :style_checking, :complexity_analysis],
        tags: [:analysis, :static_analysis, :llm_enhanced]
      )
    end

    engine :refactoring do
      module RubberDuck.Engines.Refactoring
      description "Suggests and applies code refactoring based on best practices"
      priority(70)
      timeout 25_000

      config(
        max_tokens: 4096,
        temperature: 0.4,
        capabilities: [:code_refactoring, :pattern_detection, :automated_fixes],
        tags: [:refactoring, :llm, :code_transformation]
      )
    end

    engine :test_generation do
      module RubberDuck.Engines.TestGeneration
      description "Generates comprehensive test suites for code modules"
      priority(60)
      timeout 30_000

      config(
        max_tokens: 4096,
        temperature: 0.5,
        capabilities: [:test_generation, :test_framework_support, :edge_case_detection, :property_testing],
        tags: [:testing, :llm, :test_generation]
      )
    end
  end
end

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

    # Conversation Engines
    engine :simple_conversation do
      module RubberDuck.Engines.Conversation.SimpleConversation
      description "Handles simple, straightforward conversational queries"
      priority(95)
      timeout 15_000

      config(
        max_tokens: 1000,
        temperature: 0.7,
        capabilities: [:simple_questions, :factual_queries, :basic_code, :quick_reference],
        tags: [:conversation, :simple, :direct_response]
      )
    end

    engine :complex_conversation do
      module RubberDuck.Engines.Conversation.ComplexConversation
      description "Handles complex queries requiring chain-of-thought reasoning"
      priority(85)
      timeout RubberDuck.Config.Timeouts.get([:engines, :complex_conversation], 240_000)

      config(
        max_tokens: 2000,
        temperature: 0.5,
        capabilities: [:complex_reasoning, :multi_step_analysis, :deep_understanding, :cot_reasoning],
        tags: [:conversation, :complex, :cot_enabled]
      )
    end

    engine :conversation_router do
      module RubberDuck.Engines.Conversation.ConversationRouter
      description "Routes conversation queries to appropriate specialized engines"
      priority(100)
      # Increase timeout to accommodate long-running engines it routes to
      timeout 600_000  # 10 minutes

      config(
        max_tokens: 500,
        temperature: 0.0,
        capabilities: [:query_classification, :routing, :engine_selection],
        tags: [:conversation, :router, :dispatcher]
      )
    end

    engine :multi_step_conversation do
      module RubberDuck.Engines.Conversation.MultiStepConversation
      description "Manages multi-step conversational processes with context"
      priority(75)
      timeout 30_000

      config(
        max_tokens: 1500,
        temperature: 0.5,
        max_context_messages: 10,
        capabilities: [:multi_step_conversation, :context_aware, :follow_up_questions, :iterative_solving],
        tags: [:conversation, :multi_step, :contextual]
      )
    end

    engine :analysis_conversation do
      module RubberDuck.Engines.Conversation.AnalysisConversation
      description "Specialized in code analysis discussions and reviews"
      priority(80)
      timeout RubberDuck.Config.Timeouts.get([:engines, :analysis_conversation], 120_000)

      config(
        max_tokens: 2000,
        temperature: 0.3,
        capabilities: [:code_review, :architecture_analysis, :performance_analysis, :security_review, :best_practices],
        tags: [:conversation, :analysis, :code_review]
      )
    end

    engine :generation_conversation do
      module RubberDuck.Engines.Conversation.GenerationConversation
      description "Handles code generation conversations and planning"
      priority(85)
      timeout RubberDuck.Config.Timeouts.get([:engines, :generation_conversation], 180_000)

      config(
        max_tokens: 3000,
        temperature: 0.6,
        capabilities: [:code_generation, :implementation_planning, :api_design, :feature_development, :scaffolding],
        tags: [:conversation, :generation, :planning]
      )
    end

    engine :problem_solver do
      module RubberDuck.Engines.Conversation.ProblemSolver
      description "Specialized for debugging and problem-solving conversations"
      priority(90)
      timeout RubberDuck.Config.Timeouts.get([:engines, :problem_solver], 300_000)

      config(
        max_tokens: 2500,
        temperature: 0.4,
        capabilities: [:debugging, :troubleshooting, :error_analysis, :root_cause_analysis, :solution_generation],
        tags: [:conversation, :problem_solving, :debugging]
      )
    end
  end
end

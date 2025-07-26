import Config

# Centralized timeout configuration for RubberDuck
# All timeouts are in milliseconds unless otherwise specified

config :rubber_duck, :timeouts, %{
  # Channel timeouts
  channels: %{
    conversation: 120_000,
    mcp_heartbeat: 30_000,
    mcp_message_queue_cleanup: 600_000
  },

  # Engine and processing timeouts
  engines: %{
    default: 10_000,
    external_router: 600_000,
    task_registry_cleanup: 120_000,
    # Conversation engines
    generation_conversation: 360_000,  # 6 minutes for code generation
    analysis_conversation: 240_000,    # 4 minutes for analysis
    complex_conversation: 480_000,     # 8 minutes for complex tasks
    problem_solver: 600_000           # 10 minutes for problem solving
  },

  # Tool execution timeouts
  tools: %{
    default: 60_000,
    sandbox: %{
      minimal: 10_000,
      standard: 30_000,
      enhanced: 60_000,
      maximum: 120_000
    },
    external_registry_scan: 10_000,
    telemetry_polling: 20_000
  },

  # LLM provider timeouts
  llm_providers: %{
    default: 60_000,
    default_streaming: 600_000,
    health_check: 10_000,
    
    # Provider-specific timeouts
    ollama: %{
      request: 120_000,
      streaming: 600_000
    },
    tgi: %{
      request: 240_000,
      streaming: 600_000,
      health_check: 20_000
    },
    anthropic: %{
      request: 60_000
    },
    openai: %{
      request: 60_000
    }
  },

  # Chain of Thought timeouts
  chains: %{
    analysis: %{
      total: 90_000,
      steps: %{
        understanding: 20_000,
        context_gathering: 16_000,
        pattern_identification: 20_000,
        relationship_mapping: 20_000,
        synthesis: 14_000
      }
    },
    generation: %{
      total: 300_000,  # 5 minutes for full generation chain
      steps: %{
        understand_requirements: 20_000,
        review_context: 120_000,
        plan_structure: 20_000,
        identify_dependencies: 14_000,
        generate_implementation: 30_000,
        add_documentation: 120_000,
        generate_tests: 24_000,
        validate_output: 120_000,
        provide_alternatives: 20_000
      }
    },
    completion: %{
      total: 40_000,
      steps: %{
        parse_context: 10_000,
        retrieve_patterns: 8_000,
        generate_initial: 8_000,
        refine_output: 12_000,
        validate_syntax: 6_000,
        optimize_result: 8_000,
        format_output: 6_000
      }
    },
    lightweight_conversation: %{
      default: 40_000
    },
    multi_turn_conversation: %{
      default: 60_000
    },
    refinement: %{
      total: 60_000,
      steps: %{
        initial_assessment: 10_000,
        improvement_planning: 10_000,
        implementation: 20_000,
        validation: 20_000
      }
    },
    reusable_blocks: %{
      block_timeout: 30_000
    },
    single_prompt: %{
      default: 40_000
    }
  },

  # Workflow timeouts
  workflows: %{
    default_step: 60_000,
    dynamic_workflow: %{
      planning: 20_000,
      execution: 360_000
    }
  },

  # Agent coordination timeouts
  agents: %{
    coordinator: 120_000,
    communication: 20_000,
    task_routing: 10_000
  },

  # MCP (Model Context Protocol) timeouts
  mcp: %{
    request: 60_000,
    session: %{
      default: 7_200_000,  # 2 hours
      cleanup_interval: 600_000  # 10 minutes
    }
  },

  # Infrastructure timeouts
  infrastructure: %{
    circuit_breaker: %{
      call_timeout: 60_000,
      reset_timeout: 120_000
    },
    status_broadcaster: %{
      flush_interval: 100,  # milliseconds
      queue_limit: 10_000,
      batch_size: 100
    },
    error_boundary: %{
      default: 10_000
    }
  },

  # Testing and development timeouts
  test: %{
    default: 10_000,
    integration: 20_000,
    slow_operations: 60_000
  }
}
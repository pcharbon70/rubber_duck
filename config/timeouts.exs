import Config

# Centralized timeout configuration for RubberDuck
# All timeouts are in milliseconds unless otherwise specified

config :rubber_duck, :timeouts, %{
  # Channel timeouts
  channels: %{
    conversation: 60_000,
    mcp_heartbeat: 15_000,
    mcp_message_queue_cleanup: 300_000
  },

  # Engine and processing timeouts
  engines: %{
    default: 5_000,
    external_router: 300_000,
    task_registry_cleanup: 60_000
  },

  # Tool execution timeouts
  tools: %{
    default: 30_000,
    sandbox: %{
      minimal: 5_000,
      standard: 15_000,
      enhanced: 30_000,
      maximum: 60_000
    },
    external_registry_scan: 5_000,
    telemetry_polling: 10_000
  },

  # LLM provider timeouts
  llm_providers: %{
    default: 30_000,
    default_streaming: 300_000,
    health_check: 5_000,
    
    # Provider-specific timeouts
    ollama: %{
      request: 60_000,
      streaming: 300_000
    },
    tgi: %{
      request: 120_000,
      streaming: 300_000,
      health_check: 10_000
    },
    anthropic: %{
      request: 30_000
    },
    openai: %{
      request: 30_000
    }
  },

  # Chain of Thought timeouts
  chains: %{
    analysis: %{
      total: 45_000,
      steps: %{
        understanding: 10_000,
        context_gathering: 8_000,
        pattern_identification: 10_000,
        relationship_mapping: 10_000,
        synthesis: 7_000
      }
    },
    completion: %{
      total: 20_000,
      steps: %{
        parse_context: 5_000,
        retrieve_patterns: 4_000,
        generate_initial: 4_000,
        refine_output: 6_000,
        validate_syntax: 3_000,
        optimize_result: 4_000,
        format_output: 3_000
      }
    },
    lightweight_conversation: %{
      default: 20_000
    },
    multi_turn_conversation: %{
      default: 30_000
    },
    refinement: %{
      total: 30_000,
      steps: %{
        initial_assessment: 5_000,
        improvement_planning: 5_000,
        implementation: 10_000,
        validation: 10_000
      }
    },
    reusable_blocks: %{
      block_timeout: 15_000
    },
    single_prompt: %{
      default: 20_000
    }
  },

  # Workflow timeouts
  workflows: %{
    default_step: 30_000,
    dynamic_workflow: %{
      planning: 10_000,
      execution: 180_000
    }
  },

  # Agent coordination timeouts
  agents: %{
    coordinator: 60_000,
    communication: 10_000,
    task_routing: 5_000
  },

  # MCP (Model Context Protocol) timeouts
  mcp: %{
    request: 30_000,
    session: %{
      default: 3_600_000,  # 1 hour
      cleanup_interval: 300_000  # 5 minutes
    }
  },

  # Infrastructure timeouts
  infrastructure: %{
    circuit_breaker: %{
      call_timeout: 30_000,
      reset_timeout: 60_000
    },
    status_broadcaster: %{
      flush_interval: 50,  # milliseconds
      queue_limit: 10_000,
      batch_size: 100
    },
    error_boundary: %{
      default: 5_000
    }
  },

  # Testing and development timeouts
  test: %{
    default: 5_000,
    integration: 10_000,
    slow_operations: 30_000
  }
}
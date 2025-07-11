import Config

# LLM Service Configuration
config :rubber_duck, :llm,
  providers: [
    %{
      name: :openai,
      adapter: RubberDuck.LLM.Providers.OpenAI,
      api_key: System.get_env("OPENAI_API_KEY"),
      models: ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"],
      priority: 1,
      rate_limit: {100, :minute},
      max_retries: 3,
      timeout: 30_000
    },
    %{
      name: :anthropic,
      adapter: RubberDuck.LLM.Providers.Anthropic,
      api_key: System.get_env("ANTHROPIC_API_KEY"),
      models: ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"],
      priority: 2,
      rate_limit: {50, :minute},
      max_retries: 3,
      timeout: 30_000
    },
    %{
      name: :ollama,
      adapter: RubberDuck.LLM.Providers.Ollama,
      base_url: System.get_env("OLLAMA_BASE_URL", "http://localhost:11434"),
      models: ["llama2", "llama2:7b", "llama2:13b", "mistral", "codellama", "mixtral"],
      priority: 3,
      # No rate limiting for local models
      rate_limit: nil,
      max_retries: 3,
      timeout: 60_000,
      options: []
    },
    %{
      name: :tgi,
      adapter: RubberDuck.LLM.Providers.TGI,
      base_url: System.get_env("TGI_BASE_URL", "http://localhost:8080"),
      models: ["llama-3.1-8b", "llama-3.1-70b", "mistral-7b", "codellama-13b"],
      priority: 4,
      # No rate limiting for self-hosted TGI
      rate_limit: nil,
      max_retries: 3,
      timeout: 120_000,
      options: [
        supports_function_calling: true,
        supports_guided_generation: true,
        supports_json_mode: true
      ]
    },
    %{
      name: :mock,
      adapter: RubberDuck.LLM.Providers.Mock,
      models: ["mock-fast", "mock-smart", "mock-vision"],
      # Low priority, only used as last resort
      priority: 99,
      max_retries: 1,
      timeout: 5_000,
      options: [
        simulate_delay: false,
        response_template: nil
      ]
    }
  ],
  # Global settings
  queue_check_interval: 100,
  health_check_interval: 30_000,
  default_timeout: 30_000

# Development overrides
if config_env() == :dev do
  config :rubber_duck, :llm,
    providers: [
      %{
        name: :mock,
        adapter: RubberDuck.LLM.Providers.Mock,
        models: ["mock-fast", "mock-smart", "mock-vision"],
        priority: 1,
        max_retries: 1,
        timeout: 1_000,
        options: [
          simulate_delay: true
        ]
      },
      %{
        name: :ollama,
        adapter: RubberDuck.LLM.Providers.Ollama,
        base_url: System.get_env("OLLAMA_BASE_URL", "http://localhost:11434"),
        models: ["llama2", "llama2:7b", "llama2:13b", "mistral", "codellama", "mixtral"],
        priority: 2,
        rate_limit: nil,
        max_retries: 3,
        timeout: 300_000,  # 5 minutes for LLM operations
        options: []
      },
      %{
        name: :openai,
        adapter: RubberDuck.LLM.Providers.OpenAI,
        api_key: System.get_env("OPENAI_API_KEY"),
        models: ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"],
        priority: 3,
        rate_limit: {100, :minute},
        max_retries: 3,
        timeout: 30_000
      },
      %{
        name: :anthropic,
        adapter: RubberDuck.LLM.Providers.Anthropic,
        api_key: System.get_env("ANTHROPIC_API_KEY"),
        models: ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"],
        priority: 4,
        rate_limit: {50, :minute},
        max_retries: 3,
        timeout: 30_000
      }
    ]
end

# Test overrides
if config_env() == :test do
  config :rubber_duck, :llm,
    providers: [
      %{
        name: :mock,
        adapter: RubberDuck.LLM.Providers.Mock,
        models: ["mock-fast", "mock-smart"],
        priority: 1,
        max_retries: 1,
        timeout: 100,
        options: [
          simulate_delay: false
        ]
      }
    ],
    queue_check_interval: 10,
    health_check_interval: 60_000
end

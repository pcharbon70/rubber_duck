defmodule RubberDuck.Agents.GenerationAgent do
  @moduledoc """
  Generation Agent specialized in code generation using Jido-compliant actions.

  The Generation Agent is responsible for:
  - Generating code from natural language descriptions using RAG
  - Refactoring existing code for improvements
  - Fixing broken or incomplete code
  - Providing intelligent code completions
  - Generating documentation and tests
  - Supporting streaming generation with real-time feedback
  - Template-based code generation with versioning

  ## Jido Compliance
  This agent has been fully migrated to use BaseAgent patterns with action-based
  architecture. All business logic is extracted into reusable Actions.

  ## Capabilities

  - `:code_generation` - Generate new code from descriptions
  - `:code_refactoring` - Improve existing code structure  
  - `:code_fixing` - Fix syntax and logic errors
  - `:code_completion` - Complete partial code snippets
  - `:documentation_generation` - Generate docs and comments
  - `:template_rendering` - Render code from templates
  - `:streaming_generation` - Real-time streaming generation
  - `:quality_validation` - Validate generated code quality

  ## Signals

  The agent responds to the following signals:
  - `generation.code.request` - Triggers code generation
  - `generation.refactor.request` - Triggers code refactoring
  - `generation.fix.request` - Triggers code fixing
  - `generation.complete.request` - Triggers code completion
  - `generation.docs.request` - Triggers documentation generation
  - `generation.template.request` - Triggers template rendering
  - `generation.streaming.request` - Triggers streaming generation
  - `generation.validate.request` - Triggers quality validation

  ## Example Usage

      # Via signal
      signal = %{
        "type" => "generation.code.request",
        "data" => %{
          "prompt" => "Create a GenServer that manages user sessions",
          "language" => "elixir",
          "context" => %{"relevant_files" => ["lib/user.ex"]}
        }
      }

      Jido.Signal.Bus.publish(signal)

      # Via direct action
      {:ok, agent} = GenerationAgent.start_link(id: "gen_agent")
      {:ok, result} = GenerationAgent.cmd(agent, CodeGenerationAction, params)
  """

  use RubberDuck.Agents.BaseAgent,
    name: "generation_agent",
    description: "Code generation and quality improvement agent",
    schema: [
      generation_cache: [
        type: :map,
        default: %{},
        doc: "Cache for generation results"
      ],
      user_preferences: [
        type: :map,
        default: %{
          code_style: :balanced,
          comments: :helpful,
          error_handling: :comprehensive,
          naming_convention: :snake_case
        },
        doc: "User preferences for code generation"
      ],
      generation_history: [
        type: :list,
        default: [],
        doc: "History of generation requests and results"
      ],
      metrics: [
        type: :map,
        default: %{
          tasks_completed: 0,
          generate_code: 0,
          refactor_code: 0,
          fix_code: 0,
          complete_code: 0,
          generate_docs: 0,
          template_renders: 0,
          streaming_sessions: 0,
          total_tokens_used: 0,
          cache_hits: 0,
          cache_misses: 0
        },
        doc: "Agent performance metrics"
      ],
      llm_config: [
        type: :map,
        default: %{
          provider: :openai,
          model: "gpt-4",
          temperature: 0.7,
          max_tokens: 2048
        },
        doc: "LLM configuration for generation"
      ],
      last_activity: [
        type: {:or, [:datetime, :nil]},
        default: nil,
        doc: "Last activity timestamp"
      ],
      streaming_sessions: [
        type: :map,
        default: %{},
        doc: "Active streaming sessions"
      ],
      template_cache: [
        type: :map,
        default: %{},
        doc: "Cache for rendered templates"
      ],
      enable_self_correction: [
        type: :boolean,
        default: true,
        doc: "Enable self-correction for generation results"
      ],
      cache_ttl_seconds: [
        type: :integer,
        default: 3600,
        doc: "Cache time-to-live in seconds"
      ],
      capabilities: [
        type: {:list, :atom},
        default: [
          :code_generation,
          :code_refactoring,
          :code_fixing,
          :code_completion,
          :documentation_generation,
          :template_rendering,
          :streaming_generation,
          :quality_validation
        ],
        doc: "Agent capabilities"
      ]
    ],
    actions: [
      RubberDuck.Jido.Actions.Generation.CodeGenerationAction,
      RubberDuck.Jido.Actions.Generation.TemplateRenderAction,
      RubberDuck.Jido.Actions.Generation.QualityValidationAction,
      RubberDuck.Jido.Actions.Generation.StreamingGenerationAction,
      RubberDuck.Jido.Actions.Generation.PostProcessingAction
    ]

  require Logger

  alias RubberDuck.Jido.Actions.Generation.{
    CodeGenerationAction,
    TemplateRenderAction,
    QualityValidationAction,
    StreamingGenerationAction,
    PostProcessingAction
  }

  # Signal mappings for generation workflows
  @impl true
  def signal_mappings do
    %{
      "generation.code.request" => {CodeGenerationAction, &extract_generation_params/1},
      "generation.refactor.request" => {CodeGenerationAction, &extract_refactor_params/1},
      "generation.fix.request" => {CodeGenerationAction, &extract_fix_params/1},
      "generation.complete.request" => {CodeGenerationAction, &extract_completion_params/1},
      "generation.docs.request" => {CodeGenerationAction, &extract_docs_params/1},
      "generation.template.request" => {TemplateRenderAction, &extract_template_params/1},
      "generation.streaming.request" => {StreamingGenerationAction, &extract_streaming_params/1},
      "generation.validate.request" => {QualityValidationAction, &extract_validation_params/1},
      "generation.process.request" => {PostProcessingAction, &extract_processing_params/1}
    }
  end

  # Lifecycle hooks

  @impl true
  def on_before_validate_state(state) do
    # Ensure metrics are properly initialized
    if is_map(state.metrics) and Map.has_key?(state.metrics, :tasks_completed) do
      {:ok, state}
    else
      {:error, :invalid_metrics_structure}
    end
  end

  @impl true
  def on_after_validate_state(state) do
    # Update last activity timestamp
    {:ok, %{state | last_activity: DateTime.utc_now()}}
  end

  @impl true
  def on_before_run(agent) do
    # Log generation activity
    Logger.info("Generation Agent #{agent.id} starting task execution")
    {:ok, agent}
  end

  @impl true
  def on_after_run(agent, _action, result) do
    # Update metrics based on successful execution
    case result do
      {:ok, _} ->
        new_metrics = update_task_metrics(agent.state.metrics, :tasks_completed)
        new_state = %{agent.state | metrics: new_metrics, last_activity: DateTime.utc_now()}
        {:ok, %{agent | state: new_state}}
      
      {:error, _} ->
        # Don't update success metrics on error
        new_state = %{agent.state | last_activity: DateTime.utc_now()}
        {:ok, %{agent | state: new_state}}
    end
  end

  @impl true
  def on_error(agent, error) do
    Logger.error("Generation Agent #{agent.id} encountered error: #{inspect(error)}")
    
    # Reset to safe state if needed
    case error do
      %{type: :cache_corruption} ->
        safe_state = %{agent.state | generation_cache: %{}, template_cache: %{}}
        {:ok, %{agent | state: safe_state}}
      
      _ ->
        # Let supervisor handle other errors
        {:error, error}
    end
  end

  # Health check implementation
  @impl true
  def health_check(agent) do
    health_status = %{
      healthy: true,
      cache_size: map_size(agent.state.generation_cache),
      history_size: length(agent.state.generation_history),
      active_streaming_sessions: map_size(agent.state.streaming_sessions),
      llm_config: agent.state.llm_config,
      metrics: agent.state.metrics,
      last_activity: agent.state.last_activity
    }

    # Check for potential issues
    issues = []
    
    issues = if map_size(agent.state.generation_cache) > 1000 do
      ["Large cache size may impact memory" | issues]
    else
      issues
    end
    
    issues = if length(agent.state.generation_history) > 500 do
      ["Large history may impact performance" | issues]
    else
      issues
    end

    final_status = if Enum.empty?(issues) do
      health_status
    else
      Map.put(health_status, :warnings, issues)
    end

    {:ok, final_status}
  end

  # Parameter extraction functions for signal handling

  defp extract_generation_params(%{"data" => data}) do
    %{
      prompt: Map.get(data, "prompt", ""),
      language: String.to_atom(Map.get(data, "language", "elixir")),
      context: Map.get(data, "context", %{}),
      user_preferences: Map.get(data, "user_preferences", %{}),
      enable_self_correction: Map.get(data, "enable_self_correction", true),
      max_iterations: Map.get(data, "max_iterations", 3)
    }
  end

  defp extract_refactor_params(%{"data" => data}) do
    %{
      prompt: build_refactor_prompt(data),
      language: String.to_atom(Map.get(data, "language", "elixir")),
      context: Map.merge(Map.get(data, "context", %{}), %{
        original_code: Map.get(data, "code", ""),
        refactoring_type: Map.get(data, "refactoring_type", "general"),
        preserve_behavior: Map.get(data, "preserve_behavior", true)
      })
    }
  end

  defp extract_fix_params(%{"data" => data}) do
    %{
      prompt: build_fix_prompt(data),
      language: String.to_atom(Map.get(data, "language", "elixir")),
      context: Map.merge(Map.get(data, "context", %{}), %{
        broken_code: Map.get(data, "code", ""),
        error_message: Map.get(data, "error_message", ""),
        file_path: Map.get(data, "file_path")
      })
    }
  end

  defp extract_completion_params(%{"data" => data}) do
    %{
      prompt: build_completion_prompt(data),
      language: String.to_atom(Map.get(data, "language", "elixir")),
      context: Map.merge(Map.get(data, "context", %{}), %{
        prefix: Map.get(data, "prefix", ""),
        suffix: Map.get(data, "suffix", ""),
        cursor_position: Map.get(data, "cursor_position", {0, 0})
      })
    }
  end

  defp extract_docs_params(%{"data" => data}) do
    %{
      prompt: build_docs_prompt(data),
      language: String.to_atom(Map.get(data, "language", "elixir")),
      context: Map.merge(Map.get(data, "context", %{}), %{
        code: Map.get(data, "code", ""),
        doc_type: String.to_atom(Map.get(data, "doc_type", "moduledoc"))
      })
    }
  end

  defp extract_template_params(%{"data" => data}) do
    %{
      template_name: Map.get(data, "template_name", ""),
      template_data: Map.get(data, "template_data", %{}),
      template_version: Map.get(data, "template_version", :latest),
      language: String.to_atom(Map.get(data, "language", "elixir")),
      output_format: String.to_atom(Map.get(data, "output_format", "code"))
    }
  end

  defp extract_streaming_params(%{"data" => data}) do
    %{
      prompt: Map.get(data, "prompt", ""),
      language: String.to_atom(Map.get(data, "language", "elixir")),
      streaming_id: Map.get(data, "streaming_id"),
      context: Map.get(data, "context", %{}),
      chunk_size: Map.get(data, "chunk_size", 100),
      max_chunks: Map.get(data, "max_chunks", 50)
    }
  end

  defp extract_validation_params(%{"data" => data}) do
    %{
      code: Map.get(data, "code", ""),
      language: String.to_atom(Map.get(data, "language", "elixir")),
      validation_types: Enum.map(Map.get(data, "validation_types", ["syntax", "style"]), &String.to_atom/1),
      quality_standards: String.to_atom(Map.get(data, "quality_standards", "standard")),
      context: Map.get(data, "context", %{})
    }
  end

  defp extract_processing_params(%{"data" => data}) do
    %{
      code: Map.get(data, "code", ""),
      language: String.to_atom(Map.get(data, "language", "elixir")),
      processing_types: Enum.map(Map.get(data, "processing_types", ["format", "optimize"]), &String.to_atom/1),
      formatting_options: Map.get(data, "formatting_options", %{}),
      optimization_level: String.to_atom(Map.get(data, "optimization_level", "standard")),
      add_documentation: Map.get(data, "add_documentation", true),
      add_tests: Map.get(data, "add_tests", false)
    }
  end

  # Prompt building helpers

  defp build_refactor_prompt(data) do
    code = Map.get(data, "code", "")
    refactoring_type = Map.get(data, "refactoring_type", "general")
    preserve_behavior = Map.get(data, "preserve_behavior", true)

    behavior_instruction = if preserve_behavior do
      "IMPORTANT: The refactored code must preserve the exact same behavior and API."
    else
      "You may change the behavior if it improves the code quality."
    end

    """
    Refactor the following code with focus on #{refactoring_type}.
    #{behavior_instruction}

    Original code:
    ```
    #{code}
    ```

    Provide the refactored code with explanations for the changes made.
    """
  end

  defp build_fix_prompt(data) do
    code = Map.get(data, "code", "")
    error_message = Map.get(data, "error_message", "")
    file_path = Map.get(data, "file_path")

    file_context = if file_path do
      "File: #{file_path}"
    else
      ""
    end

    """
    Fix the following code that has an error.
    #{file_context}

    Error message: #{error_message}

    Broken code:
    ```
    #{code}
    ```

    Provide the fixed code and explain what was wrong and how you fixed it.
    """
  end

  defp build_completion_prompt(data) do
    prefix = Map.get(data, "prefix", "")
    suffix = Map.get(data, "suffix", "")

    """
    Complete the following code at the cursor position.

    Code before cursor:
    ```
    #{prefix}
    ```

    Code after cursor:
    ```
    #{suffix}
    ```

    Provide appropriate code completion for the cursor position.
    """
  end

  defp build_docs_prompt(data) do
    code = Map.get(data, "code", "")
    doc_type = Map.get(data, "doc_type", "moduledoc")
    language = Map.get(data, "language", "elixir")

    doc_instruction = case doc_type do
      "moduledoc" -> "Generate comprehensive module documentation"
      "fundoc" -> "Generate function documentation with examples"  
      "typedoc" -> "Generate type documentation"
      _ -> "Generate appropriate documentation"
    end

    """
    #{doc_instruction} for the following #{language} code:

    ```#{language}
    #{code}
    ```

    Include:
    - Clear description of purpose and functionality
    - Parameters and return values (where applicable)
    - Usage examples
    - Any important notes or warnings
    """
  end

  # Metrics helpers

  defp update_task_metrics(metrics, task_type) do
    metrics
    |> Map.update(:tasks_completed, 1, &(&1 + 1))
    |> Map.update(task_type, 1, &(&1 + 1))
  end
end
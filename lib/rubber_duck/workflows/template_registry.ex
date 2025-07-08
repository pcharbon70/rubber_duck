defmodule RubberDuck.Workflows.TemplateRegistry do
  @moduledoc """
  Registry of pre-defined workflow templates for common scenarios.

  Templates provide reusable workflow patterns that can be customized
  with parameters and composed together for complex operations.
  """

  @type template_name :: atom()
  @type task_type :: atom()
  @type complexity :: :simple | :medium | :complex
  @type template :: %{
          name: atom(),
          description: String.t(),
          steps: list(step()),
          parallel_execution: boolean(),
          metadata: map()
        }
  @type step :: %{
          type: atom(),
          agent: atom(),
          config: map(),
          depends_on: list(atom())
        }

  # Built-in templates
  @templates %{
    simple_analysis: %{
      name: :simple_analysis,
      description: "Basic code analysis workflow",
      steps: [
        %{
          name: :analyze,
          type: :analysis,
          agent: :analysis,
          config: %{
            engines: [:semantic, :style],
            depth: :shallow
          },
          depends_on: []
        }
      ],
      parallel_execution: false,
      metadata: %{
        estimated_time: 30_000,
        required_agents: [:analysis]
      }
    },
    deep_analysis: %{
      name: :deep_analysis,
      description: "Comprehensive multi-engine analysis",
      steps: [
        %{
          name: :research_context,
          type: :research,
          agent: :research,
          config: %{
            scope: :codebase,
            include_dependencies: true
          },
          depends_on: []
        },
        %{
          name: :semantic_analysis,
          type: :analysis,
          agent: :analysis,
          config: %{
            engine: :semantic,
            depth: :deep
          },
          depends_on: []
        },
        %{
          name: :security_analysis,
          type: :analysis,
          agent: :analysis,
          config: %{
            engine: :security,
            check_dependencies: true
          },
          depends_on: []
        },
        %{
          name: :style_analysis,
          type: :analysis,
          agent: :analysis,
          config: %{
            engine: :style,
            strict: true
          },
          depends_on: []
        },
        %{
          name: :aggregate_results,
          type: :aggregation,
          agent: :analysis,
          config: %{
            merge_strategy: :union
          },
          depends_on: [:semantic_analysis, :security_analysis, :style_analysis]
        }
      ],
      parallel_execution: true,
      metadata: %{
        estimated_time: 120_000,
        required_agents: [:research, :analysis]
      }
    },
    generation_pipeline: %{
      name: :generation_pipeline,
      description: "Code generation with research and review",
      steps: [
        %{
          name: :research,
          type: :research,
          agent: :research,
          config: %{
            search_patterns: true,
            search_examples: true
          },
          depends_on: []
        },
        %{
          name: :analysis,
          type: :analysis,
          agent: :analysis,
          config: %{
            analyze_requirements: true,
            identify_patterns: true
          },
          depends_on: [:research]
        },
        %{
          name: :generation,
          type: :generation,
          agent: :generation,
          config: %{
            use_rag: true,
            validate_syntax: true
          },
          depends_on: [:analysis]
        },
        %{
          name: :review,
          type: :review,
          agent: :review,
          config: %{
            check_correctness: true,
            suggest_improvements: true
          },
          depends_on: [:generation]
        }
      ],
      parallel_execution: false,
      metadata: %{
        estimated_time: 180_000,
        required_agents: [:research, :analysis, :generation, :review]
      }
    },
    simple_refactoring: %{
      name: :simple_refactoring,
      description: "Basic refactoring workflow",
      steps: [
        %{
          name: :analyze_current,
          type: :analysis,
          agent: :analysis,
          config: %{
            focus: :refactoring_opportunities
          },
          depends_on: []
        },
        %{
          name: :generate_refactored,
          type: :generation,
          agent: :generation,
          config: %{
            refactoring_mode: true,
            preserve_behavior: true
          },
          depends_on: [:analyze_current]
        },
        %{
          name: :verify_refactoring,
          type: :review,
          agent: :review,
          config: %{
            compare_behavior: true,
            check_improvements: true
          },
          depends_on: [:generate_refactored]
        }
      ],
      parallel_execution: false,
      metadata: %{
        estimated_time: 90_000,
        required_agents: [:analysis, :generation, :review]
      }
    },
    complex_refactoring: %{
      name: :complex_refactoring,
      description: "Advanced refactoring with performance optimization",
      steps: [
        %{
          name: :research_patterns,
          type: :research,
          agent: :research,
          config: %{
            search_patterns: true,
            performance_patterns: true
          },
          depends_on: []
        },
        %{
          name: :analyze_performance,
          type: :analysis,
          agent: :analysis,
          config: %{
            engine: :performance,
            profile: true
          },
          depends_on: []
        },
        %{
          name: :analyze_complexity,
          type: :analysis,
          agent: :analysis,
          config: %{
            engine: :complexity,
            identify_hotspots: true
          },
          depends_on: []
        },
        %{
          name: :analyze_dependencies,
          type: :analysis,
          agent: :analysis,
          config: %{
            engine: :dependency,
            find_cycles: true
          },
          depends_on: []
        },
        %{
          name: :plan_refactoring,
          type: :planning,
          agent: :analysis,
          config: %{
            merge_analyses: true,
            prioritize_changes: true
          },
          depends_on: [:analyze_performance, :analyze_complexity, :analyze_dependencies]
        },
        %{
          name: :generate_refactored,
          type: :generation,
          agent: :generation,
          config: %{
            apply_optimizations: true,
            incremental: true
          },
          depends_on: [:plan_refactoring, :research_patterns]
        },
        %{
          name: :review_changes,
          type: :review,
          agent: :review,
          config: %{
            verify_correctness: true,
            measure_improvements: true
          },
          depends_on: [:generate_refactored]
        }
      ],
      parallel_execution: true,
      metadata: %{
        estimated_time: 300_000,
        required_agents: [:research, :analysis, :generation, :review]
      }
    },
    review_pipeline: %{
      name: :review_pipeline,
      description: "Code review workflow",
      steps: [
        %{
          name: :analyze_changes,
          type: :analysis,
          agent: :analysis,
          config: %{
            diff_mode: true,
            context_lines: 5
          },
          depends_on: []
        },
        %{
          name: :review_quality,
          type: :review,
          agent: :review,
          config: %{
            check_standards: true,
            suggest_improvements: true
          },
          depends_on: [:analyze_changes]
        }
      ],
      parallel_execution: false,
      metadata: %{
        estimated_time: 60_000,
        required_agents: [:analysis, :review]
      }
    }
  }

  # Custom templates storage
  @custom_templates_table :workflow_templates

  @doc """
  Initializes the template registry.
  """
  def init do
    if :ets.whereis(@custom_templates_table) == :undefined do
      :ets.new(@custom_templates_table, [:set, :public, :named_table])
    end

    :ok
  end

  @doc """
  Gets a template based on task type and complexity.
  """
  @spec get_template(task_type(), complexity()) :: template() | nil
  def get_template(task_type, complexity) do
    case {task_type, complexity} do
      {:analysis, :simple} -> @templates.simple_analysis
      {:analysis, :complex} -> @templates.deep_analysis
      {:generation, _} -> @templates.generation_pipeline
      {:refactoring, :simple} -> @templates.simple_refactoring
      {:refactoring, :complex} -> @templates.complex_refactoring
      {:review, _} -> @templates.review_pipeline
      {:analysis, :custom} -> get_custom_template(:custom_analysis)
      _ -> nil
    end
  end

  @doc """
  Lists all available templates.
  """
  @spec list_templates() :: list(template())
  def list_templates do
    built_in = Map.values(@templates)
    custom = list_custom_templates()
    built_in ++ custom
  end

  @doc """
  Registers a custom template.
  """
  @spec register_template(template_name(), template()) :: :ok
  def register_template(name, template) do
    init()
    :ets.insert(@custom_templates_table, {name, template})
    :ok
  end

  @doc """
  Gets a template by exact name.
  """
  @spec get_by_name(template_name()) :: template() | nil
  def get_by_name(name) do
    # Check built-in templates first
    case Map.get(@templates, name) do
      nil -> get_custom_template(name)
      template -> template
    end
  end

  @doc """
  Composes two templates into a single workflow.
  """
  @spec compose_templates(template(), template()) :: template()
  def compose_templates(template1, template2) do
    # Adjust dependencies in second template to avoid conflicts
    adjusted_steps =
      Enum.map(template2.steps, fn step ->
        adjusted_deps =
          Enum.map(Map.get(step, :depends_on, []), fn dep ->
            if is_atom(dep) do
              String.to_atom("#{dep}_2")
            else
              dep
            end
          end)

        # Also adjust step names to avoid conflicts
        adjusted_name =
          if Map.has_key?(step, :name) do
            String.to_atom("#{step.name}_2")
          else
            nil
          end

        step
        |> Map.put(:depends_on, adjusted_deps)
        |> then(fn s -> if adjusted_name, do: Map.put(s, :name, adjusted_name), else: s end)
      end)

    %{
      name: :composed_workflow,
      description: "Composed from #{template1.name} and #{template2.name}",
      steps: template1.steps ++ adjusted_steps,
      parallel_execution: template1.parallel_execution || template2.parallel_execution,
      metadata: %{
        source_templates: [template1.name, template2.name],
        estimated_time:
          (get_in(template1, [:metadata, :estimated_time]) || 0) +
            (get_in(template2, [:metadata, :estimated_time]) || 0)
      }
    }
  end

  @doc """
  Applies parameters to customize a template.
  """
  @spec apply_parameters(template(), map()) :: template()
  def apply_parameters(template, params) do
    customized_steps =
      Enum.map(template.steps, fn step ->
        updated_config = Map.merge(step.config, params)
        Map.put(step, :config, updated_config)
      end)

    %{template | steps: customized_steps}
  end

  # Private functions

  defp get_custom_template(name) do
    init()

    case :ets.lookup(@custom_templates_table, name) do
      [{^name, template}] -> template
      [] -> nil
    end
  end

  defp list_custom_templates do
    init()

    :ets.tab2list(@custom_templates_table)
    |> Enum.map(fn {_name, template} -> template end)
  end
end

defmodule RubberDuck.Planning.PatternLibrary do
  @moduledoc """
  Library of common task decomposition patterns.

  Provides reusable patterns for common software development tasks,
  including task structures, dependencies, and success criteria.
  """

  @patterns %{
    "feature_implementation" => %{
      name: "Feature Implementation",
      description: "Standard pattern for implementing new features",
      applicable_when: [
        "Adding new functionality",
        "User-facing features",
        "API endpoints"
      ],
      strategy: :hierarchical,
      phases: [
        %{
          name: "Design",
          tasks: [
            %{
              name: "Gather requirements",
              complexity: :simple,
              success_criteria: ["Requirements documented", "Stakeholder approval obtained"]
            },
            %{
              name: "Create technical design",
              complexity: :medium,
              success_criteria: ["Design document created", "Architecture reviewed"]
            },
            %{
              name: "Design UI/UX mockups",
              complexity: :medium,
              success_criteria: ["Mockups created", "UX approved"],
              optional: true
            }
          ]
        },
        %{
          name: "Implementation",
          tasks: [
            %{
              name: "Set up data models",
              complexity: :medium,
              success_criteria: ["Models created", "Migrations written"]
            },
            %{
              name: "Implement business logic",
              complexity: :complex,
              success_criteria: ["Core functionality working", "Edge cases handled"]
            },
            %{
              name: "Create API endpoints",
              complexity: :medium,
              success_criteria: ["Endpoints functional", "Input validation complete"]
            },
            %{
              name: "Build UI components",
              complexity: :medium,
              success_criteria: ["UI renders correctly", "Interactions work"],
              optional: true
            }
          ]
        },
        %{
          name: "Testing",
          tasks: [
            %{
              name: "Write unit tests",
              complexity: :medium,
              success_criteria: ["Coverage > 80%", "All tests passing"]
            },
            %{
              name: "Write integration tests",
              complexity: :medium,
              success_criteria: ["Key workflows tested", "Tests passing"]
            },
            %{
              name: "Perform manual testing",
              complexity: :simple,
              success_criteria: ["Feature works as expected", "No critical bugs"]
            }
          ]
        },
        %{
          name: "Documentation",
          tasks: [
            %{
              name: "Write user documentation",
              complexity: :simple,
              success_criteria: ["Docs complete", "Examples provided"]
            },
            %{
              name: "Update API documentation",
              complexity: :simple,
              success_criteria: ["API docs current", "Examples work"]
            }
          ]
        }
      ],
      typical_dependencies: "linear_within_phases"
    },
    "bug_fix" => %{
      name: "Bug Fix",
      description: "Pattern for fixing bugs systematically",
      applicable_when: [
        "Fixing reported issues",
        "Addressing defects",
        "Correcting behavior"
      ],
      strategy: :linear,
      phases: [
        %{
          name: "Investigation",
          tasks: [
            %{
              name: "Reproduce the bug",
              complexity: :simple,
              success_criteria: ["Bug reproduced consistently", "Steps documented"]
            },
            %{
              name: "Identify root cause",
              complexity: :medium,
              success_criteria: ["Root cause found", "Analysis documented"]
            }
          ]
        },
        %{
          name: "Fix",
          tasks: [
            %{
              name: "Implement fix",
              complexity: :variable,
              success_criteria: ["Bug no longer occurs", "No regressions"]
            },
            %{
              name: "Add regression test",
              complexity: :simple,
              success_criteria: ["Test prevents regression", "Test is reliable"]
            }
          ]
        },
        %{
          name: "Verification",
          tasks: [
            %{
              name: "Test fix thoroughly",
              complexity: :simple,
              success_criteria: ["Fix verified", "Related features still work"]
            },
            %{
              name: "Update documentation",
              complexity: :trivial,
              success_criteria: ["Changelog updated", "Known issues updated"],
              optional: true
            }
          ]
        }
      ],
      typical_dependencies: "strictly_linear"
    },
    "refactoring" => %{
      name: "Code Refactoring",
      description: "Pattern for refactoring existing code",
      applicable_when: [
        "Improving code structure",
        "Reducing technical debt",
        "Optimizing performance"
      ],
      strategy: :hierarchical,
      phases: [
        %{
          name: "Analysis",
          tasks: [
            %{
              name: "Analyze current implementation",
              complexity: :medium,
              success_criteria: ["Issues identified", "Metrics collected"]
            },
            %{
              name: "Define refactoring goals",
              complexity: :simple,
              success_criteria: ["Goals documented", "Success metrics defined"]
            }
          ]
        },
        %{
          name: "Preparation",
          tasks: [
            %{
              name: "Add comprehensive tests",
              complexity: :medium,
              success_criteria: ["Current behavior captured", "Tests passing"]
            },
            %{
              name: "Create refactoring plan",
              complexity: :simple,
              success_criteria: ["Step-by-step plan created", "Risks identified"]
            }
          ]
        },
        %{
          name: "Refactoring",
          tasks: [
            %{
              name: "Refactor in small steps",
              complexity: :complex,
              success_criteria: ["Code improved", "Tests still passing"]
            },
            %{
              name: "Optimize performance",
              complexity: :medium,
              success_criteria: ["Performance improved", "Benchmarks show gains"],
              optional: true
            }
          ]
        },
        %{
          name: "Validation",
          tasks: [
            %{
              name: "Run all tests",
              complexity: :trivial,
              success_criteria: ["All tests pass", "No regressions"]
            },
            %{
              name: "Code review",
              complexity: :simple,
              success_criteria: ["Code reviewed", "Feedback addressed"]
            },
            %{
              name: "Update documentation",
              complexity: :simple,
              success_criteria: ["Docs reflect changes", "Examples updated"]
            }
          ]
        }
      ],
      typical_dependencies: "linear_within_phases"
    },
    "api_integration" => %{
      name: "API Integration",
      description: "Pattern for integrating with external APIs",
      applicable_when: [
        "Connecting to third-party services",
        "Adding external data sources",
        "Implementing webhooks"
      ],
      strategy: :linear,
      phases: [
        %{
          name: "Research",
          tasks: [
            %{
              name: "Study API documentation",
              complexity: :simple,
              success_criteria: ["API understood", "Endpoints identified"]
            },
            %{
              name: "Set up API credentials",
              complexity: :trivial,
              success_criteria: ["Credentials obtained", "Access verified"]
            }
          ]
        },
        %{
          name: "Implementation",
          tasks: [
            %{
              name: "Create API client",
              complexity: :medium,
              success_criteria: ["Client implemented", "Basic calls work"]
            },
            %{
              name: "Implement error handling",
              complexity: :medium,
              success_criteria: ["Errors handled gracefully", "Retries implemented"]
            },
            %{
              name: "Add rate limiting",
              complexity: :simple,
              success_criteria: ["Rate limits respected", "No API violations"]
            }
          ]
        },
        %{
          name: "Integration",
          tasks: [
            %{
              name: "Integrate with application",
              complexity: :medium,
              success_criteria: ["Integration complete", "Data flows correctly"]
            },
            %{
              name: "Add monitoring",
              complexity: :simple,
              success_criteria: ["API calls tracked", "Errors logged"]
            }
          ]
        },
        %{
          name: "Testing",
          tasks: [
            %{
              name: "Mock API for tests",
              complexity: :medium,
              success_criteria: ["Mocks created", "Tests don't hit real API"]
            },
            %{
              name: "Test error scenarios",
              complexity: :simple,
              success_criteria: ["Error cases tested", "Graceful degradation"]
            }
          ]
        }
      ],
      typical_dependencies: "strictly_linear"
    },
    "database_migration" => %{
      name: "Database Migration",
      description: "Pattern for database schema changes",
      applicable_when: [
        "Changing database schema",
        "Adding new tables",
        "Modifying columns"
      ],
      strategy: :linear,
      phases: [
        %{
          name: "Planning",
          tasks: [
            %{
              name: "Design schema changes",
              complexity: :medium,
              success_criteria: ["Schema designed", "Impacts assessed"]
            },
            %{
              name: "Plan migration strategy",
              complexity: :medium,
              success_criteria: ["Strategy documented", "Rollback plan created"]
            }
          ]
        },
        %{
          name: "Implementation",
          tasks: [
            %{
              name: "Write migration scripts",
              complexity: :medium,
              success_criteria: ["Up migration written", "Down migration written"]
            },
            %{
              name: "Test migrations locally",
              complexity: :simple,
              success_criteria: ["Migrations run cleanly", "Rollback works"]
            }
          ]
        },
        %{
          name: "Deployment",
          tasks: [
            %{
              name: "Backup production data",
              complexity: :simple,
              success_criteria: ["Backup completed", "Restore tested"]
            },
            %{
              name: "Run migration in staging",
              complexity: :simple,
              success_criteria: ["Migration successful", "App still works"]
            },
            %{
              name: "Deploy to production",
              complexity: :medium,
              success_criteria: ["Migration complete", "No data loss"]
            }
          ]
        }
      ],
      typical_dependencies: "strictly_linear"
    },
    "performance_optimization" => %{
      name: "Performance Optimization",
      description: "Pattern for improving system performance",
      applicable_when: [
        "Addressing slow performance",
        "Optimizing bottlenecks",
        "Improving response times"
      ],
      strategy: :hierarchical,
      phases: [
        %{
          name: "Profiling",
          tasks: [
            %{
              name: "Set up profiling tools",
              complexity: :simple,
              success_criteria: ["Tools configured", "Baseline captured"]
            },
            %{
              name: "Identify bottlenecks",
              complexity: :medium,
              success_criteria: ["Bottlenecks found", "Impact quantified"]
            }
          ]
        },
        %{
          name: "Optimization",
          tasks: [
            %{
              name: "Optimize database queries",
              complexity: :medium,
              success_criteria: ["Queries optimized", "Indexes added"]
            },
            %{
              name: "Implement caching",
              complexity: :medium,
              success_criteria: ["Cache implemented", "Hit rate good"]
            },
            %{
              name: "Optimize algorithms",
              complexity: :complex,
              success_criteria: ["Algorithms improved", "Complexity reduced"]
            }
          ]
        },
        %{
          name: "Validation",
          tasks: [
            %{
              name: "Benchmark improvements",
              complexity: :simple,
              success_criteria: ["Performance improved", "Targets met"]
            },
            %{
              name: "Load test",
              complexity: :medium,
              success_criteria: ["System handles load", "No regressions"]
            }
          ]
        }
      ],
      typical_dependencies: "mixed"
    }
  }

  @doc """
  Get all available patterns.
  """
  def list_patterns do
    Map.keys(@patterns)
  end

  @doc """
  Get a specific pattern by name.
  """
  def get_pattern(name) do
    case Map.get(@patterns, name) do
      nil -> {:error, :pattern_not_found}
      pattern -> {:ok, pattern}
    end
  end

  @doc """
  Find patterns that match given characteristics.
  """
  def find_matching_patterns(characteristics) do
    matches =
      @patterns
      |> Enum.filter(fn {_name, pattern} ->
        Enum.any?(pattern.applicable_when, fn condition ->
          String.contains?(
            String.downcase(characteristics),
            String.downcase(condition)
          )
        end)
      end)
      |> Enum.map(fn {name, pattern} -> {name, pattern} end)

    {:ok, matches}
  end

  @doc """
  Apply a pattern to create a task decomposition.
  """
  def apply_pattern(pattern_name, _context \\ %{}) do
    with {:ok, pattern} <- get_pattern(pattern_name) do
      tasks =
        pattern.phases
        |> Enum.with_index()
        |> Enum.flat_map(fn {phase, phase_idx} ->
          phase.tasks
          |> Enum.with_index()
          |> Enum.map(fn {task, task_idx} ->
            %{
              "id" => "#{pattern_name}_#{phase_idx}_#{task_idx}",
              "name" => task.name,
              "phase" => phase.name,
              "complexity" => to_string(task.complexity),
              "success_criteria" => %{"criteria" => task.success_criteria},
              "optional" => Map.get(task, :optional, false),
              "position" => phase_idx * 100 + task_idx
            }
          end)
        end)

      dependencies = generate_dependencies(tasks, pattern.typical_dependencies)

      {:ok,
       %{
         tasks: tasks,
         dependencies: dependencies,
         pattern: pattern_name,
         strategy: pattern.strategy
       }}
    end
  end

  @doc """
  Adapt a pattern with custom modifications.
  """
  def adapt_pattern(pattern_name, modifications) do
    with {:ok, pattern} <- get_pattern(pattern_name) do
      adapted = deep_merge(pattern, modifications)
      {:ok, adapted}
    end
  end

  @doc """
  Learn a new pattern from a decomposition.
  """
  def learn_pattern(name, decomposition, metadata \\ %{}) do
    pattern = %{
      name: name,
      description: metadata[:description] || "Learned pattern",
      applicable_when: metadata[:applicable_when] || [],
      strategy: decomposition[:strategy] || :hierarchical,
      phases: extract_phases(decomposition[:tasks]),
      typical_dependencies: analyze_dependencies(decomposition[:dependencies])
    }

    {:ok, pattern}
  end

  # Private functions

  defp deep_merge(map1, map2) do
    Map.merge(map1, map2, fn
      _k, v1, v2 when is_map(v1) and is_map(v2) -> deep_merge(v1, v2)
      _k, _v1, v2 -> v2
    end)
  end

  defp generate_dependencies(tasks, "strictly_linear") do
    tasks
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] ->
      %{
        "from" => from["id"],
        "to" => to["id"],
        "type" => "finish_to_start"
      }
    end)
  end

  defp generate_dependencies(tasks, "linear_within_phases") do
    tasks
    |> Enum.group_by(& &1["phase"])
    |> Enum.flat_map(fn {_phase, phase_tasks} ->
      generate_dependencies(phase_tasks, "strictly_linear")
    end)
  end

  defp generate_dependencies(_tasks, _) do
    []
  end

  defp extract_phases(tasks) do
    tasks
    |> Enum.group_by(& &1["phase"])
    |> Enum.map(fn {phase_name, phase_tasks} ->
      %{
        name: phase_name,
        tasks:
          Enum.map(phase_tasks, fn task ->
            %{
              name: task["name"],
              complexity: String.to_atom(task["complexity"]),
              success_criteria: task["success_criteria"]["criteria"]
            }
          end)
      }
    end)
  end

  defp analyze_dependencies(dependencies) when length(dependencies) == 0 do
    "none"
  end

  defp analyze_dependencies(dependencies) do
    # Simple analysis - could be made more sophisticated
    if Enum.all?(dependencies, &(&1["type"] == "finish_to_start")) do
      "strictly_linear"
    else
      "mixed"
    end
  end
end

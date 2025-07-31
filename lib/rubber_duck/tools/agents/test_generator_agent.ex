defmodule RubberDuck.Tools.Agents.TestGeneratorAgent do
  @moduledoc """
  Agent that orchestrates the TestGenerator tool for automated test creation.
  
  This agent manages test generation requests, maintains test suites,
  handles coverage tracking, and provides intelligent test generation workflows.
  
  ## Signals
  
  ### Input Signals
  - `generate_tests` - Generate tests for given code
  - `generate_test_suite` - Generate complete test suite for module
  - `update_tests` - Update existing tests with new cases
  - `analyze_coverage` - Analyze test coverage
  - `generate_property_tests` - Generate property-based tests
  - `suggest_test_improvements` - Suggest improvements to existing tests
  
  ### Output Signals
  - `tests_generated` - Successfully generated tests
  - `test_suite_generated` - Complete test suite generated
  - `coverage_analyzed` - Coverage analysis complete
  - `test_suggestions` - Test improvement suggestions
  - `generation_error` - Error during test generation
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :test_generator,
    name: "test_generator_agent",
    description: "Manages automated test generation workflows",
    category: :testing,
    tags: [:testing, :quality, :automation, :tdd],
    schema: [
      # Test suite management
      test_suites: [type: :map, default: %{}],
      active_suite: [type: {:nullable, :string}, default: nil],
      
      # Coverage tracking
      coverage_data: [type: :map, default: %{}],
      coverage_goals: [type: :map, default: %{"default" => 90}],
      
      # Test patterns
      custom_patterns: [type: :map, default: %{}],
      preferred_frameworks: [type: {:list, :string}, default: ["exunit"]],
      
      # Generation history
      generation_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 50],
      
      # Statistics
      test_stats: [type: :map, default: %{
        total_tests_generated: 0,
        by_type: %{},
        average_coverage: 0,
        modules_tested: 0
      }]
    ]
  
  require Logger
  
  # Tool-specific signal handlers
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "generate_tests"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters
    params = %{
      code: data["code"],
      test_type: data["test_type"] || "comprehensive",
      test_framework: data["framework"] || hd(agent.state.preferred_frameworks),
      coverage_target: data["coverage_target"] || agent.state.coverage_goals["default"],
      include_mocks: data["include_mocks"] || true,
      include_performance: data["include_performance"] || false,
      existing_tests: data["existing_tests"] || ""
    }
    
    # Create tool request
    tool_request = %{
      "type" => "tool_request",
      "data" => %{
        "params" => params,
        "request_id" => data["request_id"] || generate_request_id(),
        "metadata" => %{
          "module" => data["module"],
          "suite_id" => data["suite_id"],
          "user_id" => data["user_id"]
        }
      }
    }
    
    # Emit progress
    signal = Jido.Signal.new!(%{
      type: "test.generation.progress",
      source: "agent:#{agent.id}",
      data: %{
        request_id: tool_request["data"]["request_id"],
        status: "analyzing_code",
        module: data["module"]
      }
    })
    emit_signal(agent, signal)
    
    # Forward to base handler
    {:ok, agent} = handle_signal(agent, tool_request)
    
    # Store generation metadata
    agent = put_in(
      agent.state.active_requests[tool_request["data"]["request_id"]][:generation_metadata],
      %{
        module: data["module"],
        test_type: params.test_type,
        framework: params.test_framework
      }
    )
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "generate_test_suite"} = signal) do
    %{"data" => data} = signal
    suite_id = data["suite_id"] || "suite_#{System.unique_integer([:positive])}"
    modules = data["modules"] || []
    
    # Initialize suite
    agent = put_in(agent.state.test_suites[suite_id], %{
      id: suite_id,
      name: data["name"] || "Test Suite",
      modules: modules,
      created_at: DateTime.utc_now(),
      tests: %{},
      coverage: %{},
      status: "generating"
    })
    
    # Set as active suite
    agent = put_in(agent.state.active_suite, suite_id)
    
    # Generate tests for each module
    agent = Enum.reduce(modules, agent, fn module_info, acc ->
      test_signal = %{
        "type" => "generate_tests",
        "data" => Map.merge(module_info, %{
          "suite_id" => suite_id,
          "test_type" => data["test_type"] || "comprehensive",
          "coverage_target" => data["coverage_target"] || 90
        })
      }
      
      case handle_tool_signal(acc, test_signal) do
        {:ok, updated_agent} -> updated_agent
        _ -> acc
      end
    end)
    
    signal = Jido.Signal.new!(%{
      type: "test.suite.started",
      source: "agent:#{agent.id}",
      data: %{
        suite_id: suite_id,
        module_count: length(modules)
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "update_tests"} = signal) do
    %{"data" => data} = signal
    
    # Build update parameters
    params = %{
      code: data["code"],
      test_type: "unit",  # Focus on unit tests for updates
      test_framework: data["framework"] || hd(agent.state.preferred_frameworks),
      coverage_target: data["coverage_target"] || 95,
      include_mocks: data["include_mocks"] || true,
      include_performance: false,
      existing_tests: data["existing_tests"]
    }
    
    # Check what's missing in existing tests
    missing_coverage = analyze_missing_coverage(data["code"], data["existing_tests"])
    
    # Add context about what to focus on
    enhanced_params = Map.put(params, :code, """
    #{data["code"]}
    
    # Focus on testing these aspects that lack coverage:
    #{format_missing_coverage(missing_coverage)}
    """)
    
    # Create tool request
    tool_request = %{
      "type" => "tool_request",
      "data" => %{
        "params" => enhanced_params,
        "request_id" => data["request_id"] || generate_request_id(),
        "metadata" => %{
          "update_type" => "coverage_improvement",
          "missing_coverage" => missing_coverage
        }
      }
    }
    
    {:ok, agent} = handle_signal(agent, tool_request)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "analyze_coverage"} = signal) do
    %{"data" => data} = signal
    module = data["module"]
    
    # Get coverage data for module
    coverage = get_module_coverage(agent, module)
    
    # Analyze gaps
    gaps = analyze_coverage_gaps(coverage, data["code"])
    
    # Generate report
    report = %{
      "module" => module,
      "current_coverage" => coverage.percentage || 0,
      "target_coverage" => agent.state.coverage_goals[module] || agent.state.coverage_goals["default"],
      "gaps" => gaps,
      "suggestions" => generate_coverage_suggestions(gaps),
      "metrics" => %{
        "tested_functions" => coverage.tested_functions || 0,
        "total_functions" => coverage.total_functions || 0,
        "test_count" => coverage.test_count || 0
      }
    }
    
    signal = Jido.Signal.new!(%{
      type: "test.coverage.analyzed",
      source: "agent:#{agent.id}",
      data: report
    })
    emit_signal(agent, signal)
    
    # Update coverage data
    agent = put_in(agent.state.coverage_data[module], report)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "generate_property_tests"} = signal) do
    %{"data" => data} = signal
    
    # Force property test generation
    params = %{
      code: data["code"],
      test_type: "property",
      test_framework: "exunit_with_stream_data",
      coverage_target: 100,
      include_mocks: false,
      include_performance: false,
      existing_tests: data["existing_tests"] || ""
    }
    
    # Create specialized request
    tool_request = %{
      "type" => "tool_request",
      "data" => %{
        "params" => params,
        "request_id" => data["request_id"] || generate_request_id(),
        "metadata" => %{
          "property_focus" => data["properties"] || ["idempotence", "invariants"],
          "generators" => data["generators"] || "auto"
        }
      }
    }
    
    signal = Jido.Signal.new!(%{
      type: "test.property.generation.started",
      source: "agent:#{agent.id}",
      data: %{
        request_id: tool_request["data"]["request_id"],
        properties: data["properties"]
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent} = handle_signal(agent, tool_request)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "suggest_test_improvements"} = signal) do
    %{"data" => data} = signal
    
    # Analyze existing tests
    analysis = analyze_test_quality(data["tests"], data["code"])
    
    # Generate suggestions
    suggestions = %{
      "missing_assertions" => find_missing_assertions(analysis),
      "untested_edge_cases" => find_untested_edge_cases(analysis),
      "refactoring_opportunities" => find_test_refactoring_opportunities(analysis),
      "performance_tests_needed" => identify_performance_test_candidates(analysis),
      "property_test_candidates" => identify_property_test_candidates(analysis)
    }
    
    signal = Jido.Signal.new!(%{
      type: "test.suggestions",
      source: "agent:#{agent.id}",
      data: %{
        module: data["module"],
        suggestions: suggestions,
        quality_score: calculate_test_quality_score(analysis)
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  # Override process_result to handle test-specific processing
  
  @impl true
  def process_result(result, request) do
    # Add generation metadata
    generation_metadata = request[:generation_metadata] || %{}
    
    result
    |> Map.put(:generated_at, DateTime.utc_now())
    |> Map.put(:request_id, request.id)
    |> Map.merge(generation_metadata)
  end
  
  # Override handle_signal to intercept tool results
  
  @impl true
  def handle_signal(agent, %{"type" => "tool_result"} = signal) do
    # Let base handle the signal first
    {:ok, agent} = super(agent, signal)
    
    %{"data" => data} = signal
    
    if data["result"] && not data["from_cache"] do
      # Update test suite if applicable
      agent = if suite_id = get_in(data, ["result", :suite_id]) do
        update_test_suite(agent, suite_id, data["result"])
      else
        agent
      end
      
      # Update generation history
      agent = add_to_generation_history(agent, data["result"])
      
      # Update statistics
      agent = update_test_stats(agent, data["result"])
      
      # Check if suite is complete
      agent = check_suite_completion(agent, data["result"])
      
      # Emit specialized signal
      signal = Jido.Signal.new!(%{
        type: "test.generated",
        source: "agent:#{agent.id}",
        data: %{
          request_id: data["request_id"],
          tests: data["result"]["tests"],
          test_count: data["result"]["test_count"],
          coverage_estimate: data["result"]["coverage_estimate"],
          module: data["result"][:module],
          suggestions: data["result"]["suggestions"]
        }
      })
      emit_signal(agent, signal)
    end
    
    {:ok, agent}
  end
  
  def handle_signal(agent, signal) do
    # Delegate to parent for standard handling
    super(agent, signal)
  end
  
  # Private helpers
  
  defp generate_request_id do
    "test_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp analyze_missing_coverage(code, existing_tests) do
    # Parse code to find functions
    case Code.string_to_quoted(code) do
      {:ok, ast} ->
        functions = extract_functions(ast)
        tested = extract_tested_functions(existing_tests)
        
        functions
        |> Enum.reject(fn f -> f.name in tested end)
        |> Enum.map(fn f ->
          %{
            function: f.name,
            arity: f.arity,
            type: categorize_function(f)
          }
        end)
        
      _ -> []
    end
  end
  
  defp extract_functions(ast) do
    {_, functions} = Macro.postwalk(ast, [], fn
      {:def, _, [{name, _, args} | _]} = node, acc ->
        {node, [%{name: name, arity: length(args || []), public: true} | acc]}
      {:defp, _, [{name, _, args} | _]} = node, acc ->
        {node, [%{name: name, arity: length(args || []), public: false} | acc]}
      node, acc ->
        {node, acc}
    end)
    
    Enum.reverse(functions)
  end
  
  defp extract_tested_functions(test_code) do
    Regex.scan(~r/test.*".*\b(\w+)\/\d+/, test_code)
    |> Enum.map(fn [_, func] -> String.to_atom(func) end)
    |> Enum.uniq()
  end
  
  defp categorize_function(%{name: name}) do
    cond do
      String.starts_with?(to_string(name), "handle_") -> :callback
      String.ends_with?(to_string(name), "?") -> :predicate
      String.ends_with?(to_string(name), "!") -> :bang_function
      true -> :regular
    end
  end
  
  defp format_missing_coverage(missing) do
    missing
    |> Enum.map(fn %{function: f, arity: a, type: t} ->
      "- #{f}/#{a} (#{t})"
    end)
    |> Enum.join("\n")
  end
  
  defp get_module_coverage(agent, module) do
    Map.get(agent.state.coverage_data, module, %{percentage: 0})
  end
  
  defp analyze_coverage_gaps(_coverage, code) do
    # Simplified gap analysis
    case Code.string_to_quoted(code) do
      {:ok, ast} ->
        functions = extract_functions(ast)
        
        %{
          "untested_functions" => Enum.filter(functions, & &1.public),
          "missing_edge_cases" => identify_edge_case_gaps(ast),
          "missing_error_cases" => identify_error_case_gaps(ast)
        }
        
      _ -> %{}
    end
  end
  
  defp identify_edge_case_gaps(ast) do
    {_, gaps} = Macro.postwalk(ast, [], fn
      {:def, _, [{_name, _, args} | _]} = node, acc when is_list(args) ->
        edge_cases = Enum.flat_map(args, fn
          {name, _, _} ->
            cond do
              String.contains?(to_string(name), "list") -> [:empty_list, :nil]
              String.contains?(to_string(name), "number") -> [:zero, :negative]
              true -> []
            end
          _ -> []
        end)
        {node, edge_cases ++ acc}
      node, acc ->
        {node, acc}
    end)
    
    Enum.uniq(gaps)
  end
  
  defp identify_error_case_gaps(ast) do
    {_, has_error_handling} = Macro.postwalk(ast, false, fn
      {:try, _, _}, _ -> {nil, true}
      {:rescue, _, _}, _ -> {nil, true}
      node, acc -> {node, acc}
    end)
    
    if has_error_handling, do: [:exception_cases], else: []
  end
  
  defp generate_coverage_suggestions(gaps) do
    suggestions = []
    
    suggestions = if length(gaps["untested_functions"] || []) > 0 do
      ["Add tests for #{length(gaps["untested_functions"])} untested functions" | suggestions]
    else
      suggestions
    end
    
    suggestions = if length(gaps["missing_edge_cases"] || []) > 0 do
      ["Add edge case tests for: #{Enum.join(gaps["missing_edge_cases"], ", ")}" | suggestions]
    else
      suggestions
    end
    
    suggestions = if length(gaps["missing_error_cases"] || []) > 0 do
      ["Add error handling tests" | suggestions]
    else
      suggestions
    end
    
    Enum.reverse(suggestions)
  end
  
  defp update_test_suite(agent, suite_id, result) do
    update_in(agent.state.test_suites[suite_id], fn suite ->
      if suite do
        suite
        |> Map.update!(:tests, &Map.put(&1, result[:module], result["tests"]))
        |> Map.update!(:coverage, &Map.put(&1, result[:module], result["coverage_estimate"]))
      else
        suite
      end
    end)
  end
  
  defp add_to_generation_history(agent, result) do
    history_entry = %{
      id: result[:request_id],
      module: result[:module],
      test_type: result["test_type"],
      test_count: result["test_count"],
      coverage_estimate: result["coverage_estimate"],
      generated_at: result[:generated_at] || DateTime.utc_now()
    }
    
    new_history = [history_entry | agent.state.generation_history]
    |> Enum.take(agent.state.max_history_size)
    
    put_in(agent.state.generation_history, new_history)
  end
  
  defp update_test_stats(agent, result) do
    update_in(agent.state.test_stats, fn stats ->
      test_type = result["test_type"] || "unit"
      
      stats
      |> Map.update!(:total_tests_generated, &(&1 + (result["test_count"] || 0)))
      |> Map.update!(:by_type, fn by_type ->
        Map.update(by_type, test_type, result["test_count"] || 0, &(&1 + (result["test_count"] || 0)))
      end)
      |> Map.update!(:modules_tested, fn count ->
        if result[:module], do: count + 1, else: count
      end)
      |> Map.update!(:average_coverage, fn avg ->
        if result["coverage_estimate"] do
          total = stats.modules_tested
          if total > 0 do
            ((avg * total) + result["coverage_estimate"]) / (total + 1)
          else
            result["coverage_estimate"]
          end
        else
          avg
        end
      end)
    end)
  end
  
  defp check_suite_completion(agent, result) do
    if suite_id = result[:suite_id] do
      suite = agent.state.test_suites[suite_id]
      
      if suite && map_size(suite.tests) >= length(suite.modules) do
        # Suite is complete
        signal = Jido.Signal.new!(%{
          type: "test.suite.generated",
          source: "agent:#{agent.id}",
          data: %{
            suite_id: suite_id,
            module_count: length(suite.modules),
            total_tests: Enum.sum(Enum.map(suite.tests, fn {_, tests} -> 
              count_tests_in_code(tests) 
            end)),
            average_coverage: calculate_average_coverage(suite.coverage)
          }
        })
        emit_signal(agent, signal)
        
        # Update suite status
        put_in(agent.state.test_suites[suite_id][:status], "complete")
      else
        agent
      end
    else
      agent
    end
  end
  
  defp count_tests_in_code(test_code) do
    Regex.scan(~r/test\s+"[^"]+"\s+do/, test_code || "")
    |> length()
  end
  
  defp calculate_average_coverage(coverage_map) do
    values = Map.values(coverage_map)
    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      0
    end
  end
  
  defp analyze_test_quality(tests, _code) do
    %{
      assertion_count: count_assertions(tests),
      test_count: count_tests_in_code(tests),
      has_setup: String.contains?(tests || "", "setup"),
      has_describe_blocks: String.contains?(tests || "", "describe"),
      has_async: String.contains?(tests || "", "async: true")
    }
  end
  
  defp count_assertions(test_code) do
    Regex.scan(~r/assert(?:_raise|_receive|_received)?/, test_code || "")
    |> length()
  end
  
  defp find_missing_assertions(analysis) do
    if analysis.test_count > 0 && analysis.assertion_count / analysis.test_count < 1.5 do
      ["Consider adding more assertions per test"]
    else
      []
    end
  end
  
  defp find_untested_edge_cases(_analysis) do
    # Simplified - would need code analysis
    ["nil inputs", "empty collections", "boundary values"]
  end
  
  defp find_test_refactoring_opportunities(analysis) do
    opportunities = []
    
    opportunities = if analysis.test_count > 10 && not analysis.has_describe_blocks do
      ["Group related tests with describe blocks" | opportunities]
    else
      opportunities
    end
    
    opportunities = if analysis.test_count > 5 && not analysis.has_setup do
      ["Consider using setup blocks for common test data" | opportunities]
    else
      opportunities
    end
    
    Enum.reverse(opportunities)
  end
  
  defp identify_performance_test_candidates(_analysis) do
    # Simplified - would analyze function complexity
    ["Functions with loops", "Recursive functions", "Data processing functions"]
  end
  
  defp identify_property_test_candidates(_analysis) do
    # Simplified - would analyze function signatures
    ["Pure functions", "Functions with numeric inputs", "Collection transformations"]
  end
  
  defp calculate_test_quality_score(analysis) do
    score = 50  # Base score
    
    score = if analysis.assertion_count / max(analysis.test_count, 1) >= 2, do: score + 20, else: score
    score = if analysis.has_setup, do: score + 10, else: score
    score = if analysis.has_describe_blocks, do: score + 10, else: score
    score = if analysis.has_async, do: score + 10, else: score
    
    min(100, score)
  end
end
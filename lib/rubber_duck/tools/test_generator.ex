defmodule RubberDuck.Tools.TestGenerator do
  @moduledoc """
  Generates unit or property-based tests for a given function or behavior.
  
  This tool analyzes code and creates comprehensive test suites including
  edge cases, error handling, and property-based tests where appropriate.
  """
  
  use RubberDuck.Tool
  
  alias RubberDuck.LLM.Service
  
  tool do
    name :test_generator
    description "Generates unit or property-based tests for a given function or behavior"
    category :testing
    version "1.0.0"
    tags [:testing, :quality, :automation, :tdd]
    
    parameter :code do
      type :string
      required true
      description "The code to generate tests for (module, function, or behavior)"
      constraints [
        min_length: 1,
        max_length: 10000
      ]
    end
    
    parameter :test_type do
      type :string
      required false
      description "Type of tests to generate"
      default "comprehensive"
      constraints [
        enum: [
          "comprehensive",  # All test types
          "unit",          # Traditional unit tests
          "property",      # Property-based tests
          "edge_cases",    # Focus on edge cases
          "integration",   # Integration tests
          "doctest"        # Doctests for @doc examples
        ]
      ]
    end
    
    parameter :test_framework do
      type :string
      required false
      description "Testing framework to use"
      default "exunit"
      constraints [
        enum: ["exunit", "exunit_with_stream_data"]
      ]
    end
    
    parameter :coverage_target do
      type :integer
      required false
      description "Target test coverage percentage"
      default 90
      constraints [
        min: 50,
        max: 100
      ]
    end
    
    parameter :include_mocks do
      type :boolean
      required false
      description "Whether to include mock implementations for dependencies"
      default true
    end
    
    parameter :include_performance do
      type :boolean
      required false
      description "Whether to include performance/benchmark tests"
      default false
    end
    
    parameter :existing_tests do
      type :string
      required false
      description "Existing tests to avoid duplication"
      default ""
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 2
    end
    
    security do
      sandbox :strict
      capabilities [:llm_access, :code_analysis]
      rate_limit [max_requests: 100, window_seconds: 60]
    end
  end
  
  @doc """
  Executes test generation based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, ast} <- parse_code(params.code),
         {:ok, analysis} <- analyze_code_for_testing(ast, params.code),
         {:ok, test_plan} <- create_test_plan(analysis, params),
         {:ok, tests} <- generate_tests(test_plan, params, context),
         {:ok, formatted} <- format_tests(tests, params) do
      
      {:ok, %{
        tests: formatted,
        test_count: count_tests(formatted),
        coverage_estimate: estimate_coverage(analysis, formatted),
        test_type: params.test_type,
        suggestions: generate_suggestions(analysis, formatted)
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp parse_code(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} -> {:ok, ast}
      {:error, {line, error, _}} -> 
        {:error, "Parse error on line #{line}: #{error}"}
    end
  end
  
  defp analyze_code_for_testing(ast, _code) do
    analysis = %{
      modules: extract_modules(ast),
      functions: extract_testable_functions(ast),
      type_specs: extract_specs(ast),
      behaviours: extract_behaviours(ast),
      dependencies: extract_dependencies(ast),
      complexity: analyze_complexity(ast),
      patterns: identify_test_patterns(ast),
      side_effects: identify_side_effects(ast)
    }
    
    {:ok, analysis}
  end
  
  defp create_test_plan(analysis, params) do
    plan = %{
      modules_to_test: analysis.modules,
      functions_to_test: filter_testable_functions(analysis.functions, params),
      test_categories: determine_test_categories(analysis, params),
      mock_requirements: identify_mock_requirements(analysis, params),
      property_opportunities: identify_property_opportunities(analysis),
      edge_cases: identify_edge_cases(analysis),
      existing_coverage: parse_existing_tests(params.existing_tests)
    }
    
    {:ok, plan}
  end
  
  defp generate_tests(test_plan, params, context) do
    prompt = build_test_generation_prompt(test_plan, params)
    
    case Service.generate(%{
      prompt: prompt,
      max_tokens: 4000,
      temperature: 0.4,  # Lower temperature for more consistent test generation
      model: context[:llm_model] || "gpt-4"
    }) do
      {:ok, response} -> extract_generated_tests(response)
      error -> error
    end
  end
  
  defp build_test_generation_prompt(plan, params) do
    base_prompt = """
    Generate #{params.test_type} tests for the following Elixir code:
    
    ```elixir
    #{params.code}
    ```
    
    Test Requirements:
    - Framework: #{params.test_framework}
    - Coverage target: #{params.coverage_target}%
    - Include mocks: #{params.include_mocks}
    - Include performance tests: #{params.include_performance}
    
    Functions to test:
    #{format_functions_list(plan.functions_to_test)}
    
    """
    
    type_specific = case params.test_type do
      "comprehensive" ->
        """
        Generate comprehensive tests including:
        1. Happy path unit tests for all public functions
        2. Edge case tests (nil, empty, boundary values)
        3. Error handling tests
        4. Property-based tests where applicable
        5. Integration tests if multiple functions interact
        """
      
      "unit" ->
        """
        Generate unit tests for each function:
        1. Test normal operation with typical inputs
        2. Test return values match expectations
        3. Test each clause/pattern match
        4. Test error conditions
        """
      
      "property" ->
        """
        Generate property-based tests using StreamData:
        1. Identify properties that should always hold
        2. Generate appropriate generators for inputs
        3. Test invariants and laws
        4. Include shrinking for better error reports
        """
      
      "edge_cases" ->
        """
        Focus on edge cases and error conditions:
        1. Nil and empty inputs
        2. Boundary values (0, -1, max values)
        3. Invalid inputs
        4. Resource exhaustion scenarios
        5. Concurrent access if applicable
        """
      
      "integration" ->
        """
        Generate integration tests:
        1. Test interactions between functions/modules
        2. Test full workflows
        3. Test side effects are handled correctly
        4. Test external dependencies if mocked
        """
      
      "doctest" ->
        """
        Generate doctests for @doc attributes:
        1. Create examples that demonstrate usage
        2. Show expected inputs and outputs
        3. Cover main use cases
        4. Keep examples clear and educational
        """
    end
    
    existing = if params.existing_tests != "" do
      "\n\nExisting tests to avoid duplicating:\n#{params.existing_tests}"
    else
      ""
    end
    
    additional = """
    
    Additional requirements:
    - Follow ExUnit best practices
    - Use descriptive test names
    - Include setup blocks where needed
    - Add appropriate assertions
    - Group related tests with describe blocks
    #{if params.include_mocks, do: "- Include Mox mock definitions for external dependencies", else: ""}
    #{if params.include_performance, do: "- Include benchmarks using Benchee", else: ""}
    """
    
    base_prompt <> type_specific <> existing <> additional
  end
  
  defp extract_testable_functions(ast) do
    {_, functions} = Macro.postwalk(ast, [], fn
      {:def, meta, [{name, _, args} | rest]} = node, acc ->
        function_info = %{
          name: name,
          arity: length(args || []),
          line: meta[:line],
          public: true,
          args: extract_arg_info(args),
          guards: extract_guards(rest),
          doc: extract_doc(rest)
        }
        {node, [function_info | acc]}
      
      {:defp, meta, [{name, _, args} | _]} = node, acc ->
        # Include private functions in analysis but mark them
        function_info = %{
          name: name,
          arity: length(args || []),
          line: meta[:line],
          public: false,
          args: extract_arg_info(args)
        }
        {node, [function_info | acc]}
      
      node, acc ->
        {node, acc}
    end)
    
    Enum.reverse(functions)
  end
  
  defp extract_modules(ast) do
    {_, modules} = Macro.postwalk(ast, [], fn
      {:defmodule, meta, [{:__aliases__, _, parts} | _]} = node, acc ->
        {node, [%{name: Module.concat(parts), line: meta[:line]} | acc]}
      node, acc ->
        {node, acc}
    end)
    
    Enum.reverse(modules)
  end
  
  defp extract_specs(ast) do
    {_, specs} = Macro.postwalk(ast, [], fn
      {:@, _, [{:spec, _, spec_def}]} = node, acc ->
        {node, [parse_spec(spec_def) | acc]}
      node, acc ->
        {node, acc}
    end)
    
    Enum.reverse(specs)
  end
  
  defp extract_behaviours(ast) do
    {_, behaviours} = Macro.postwalk(ast, [], fn
      {:@, _, [{:behaviour, _, [module]}]} = node, acc ->
        {node, [module | acc]}
      {:@, _, [{:behavior, _, [module]}]} = node, acc ->
        {node, [module | acc]}
      node, acc ->
        {node, acc}
    end)
    
    Enum.uniq(Enum.reverse(behaviours))
  end
  
  defp extract_dependencies(ast) do
    {_, deps} = Macro.postwalk(ast, [], fn
      {{:., _, [{:__aliases__, _, mod_parts}, _fun]}, _, _} = node, acc ->
        {node, [Module.concat(mod_parts) | acc]}
      node, acc ->
        {node, acc}
    end)
    
    Enum.uniq(Enum.reverse(deps))
  end
  
  defp analyze_complexity(ast) do
    {_, complexity} = Macro.postwalk(ast, 0, fn
      {:if, _, _} = node, acc -> {node, acc + 1}
      {:case, _, _} = node, acc -> {node, acc + 2}
      {:cond, _, _} = node, acc -> {node, acc + 2}
      {:with, _, _} = node, acc -> {node, acc + 1}
      {:try, _, _} = node, acc -> {node, acc + 3}
      node, acc -> {node, acc}
    end)
    
    complexity
  end
  
  defp identify_test_patterns(ast) do
    patterns = []
    
    # Check for GenServer callbacks
    if has_genserver_callbacks?(ast), do: [:genserver | patterns], else: patterns
    # Check for streams
    |> then(fn p -> if has_streams?(ast), do: [:streams | p], else: p end)
    # Check for processes
    |> then(fn p -> if has_processes?(ast), do: [:processes | p], else: p end)
    # Check for side effects
    |> then(fn p -> if has_io?(ast), do: [:io | p], else: p end)
  end
  
  defp identify_side_effects(ast) do
    {_, effects} = Macro.postwalk(ast, [], fn
      {:!, _, _} = node, acc -> {node, [:send | acc]}
      {fun, _, _} = node, acc when fun in [:spawn, :spawn_link] ->
        {node, [:process_creation | acc]}
      {{:., _, [IO, _]}, _, _} = node, acc ->
        {node, [:io | acc]}
      {{:., _, [File, _]}, _, _} = node, acc ->
        {node, [:file_system | acc]}
      node, acc ->
        {node, acc}
    end)
    
    Enum.uniq(effects)
  end
  
  defp filter_testable_functions(functions, params) do
    functions
    |> Enum.filter(fn f ->
      # Only test public functions unless specifically requested
      f.public || params.test_type == "comprehensive"
    end)
  end
  
  defp determine_test_categories(analysis, params) do
    categories = [:unit]
    
    categories = if analysis.complexity > 10, do: [:integration | categories], else: categories
    categories = if params.test_type in ["comprehensive", "property"], do: [:property | categories], else: categories
    categories = if params.include_performance, do: [:performance | categories], else: categories
    
    Enum.reverse(categories)
  end
  
  defp identify_mock_requirements(analysis, params) do
    if params.include_mocks do
      analysis.dependencies
      |> Enum.filter(&external_dependency?/1)
      |> Enum.map(fn dep ->
        %{module: dep, mock_name: :"#{dep}Mock"}
      end)
    else
      []
    end
  end
  
  defp external_dependency?(module) do
    # Simple heuristic - consider non-Elixir stdlib modules as external
    module_str = to_string(module)
    not String.starts_with?(module_str, "Elixir.Enum") and
    not String.starts_with?(module_str, "Elixir.Map") and
    not String.starts_with?(module_str, "Elixir.List")
  end
  
  defp identify_property_opportunities(analysis) do
    analysis.functions
    |> Enum.filter(fn f ->
      # Functions with simple signatures are good property candidates
      f.arity > 0 and f.arity < 4
    end)
    |> Enum.map(fn f ->
      %{
        function: f.name,
        arity: f.arity,
        suggested_properties: suggest_properties(f)
      }
    end)
  end
  
  defp suggest_properties(%{name: name}) do
    cond do
      String.contains?(to_string(name), "sort") -> ["ordering", "length_preservation"]
      String.contains?(to_string(name), "reverse") -> ["involution", "length_preservation"]
      String.contains?(to_string(name), "map") -> ["length_preservation", "element_transformation"]
      String.contains?(to_string(name), "filter") -> ["subset", "predicate_satisfaction"]
      true -> ["idempotence", "associativity", "commutativity"]
    end
  end
  
  defp identify_edge_cases(analysis) do
    _edge_cases = []
    
    # Identify numeric parameters
    edge_cases = analysis.functions
    |> Enum.flat_map(fn f ->
      f.args
      |> Enum.filter(&numeric_arg?/1)
      |> Enum.map(fn _ -> [:zero, :negative, :max_value] end)
    end)
    |> List.flatten()
    |> Enum.uniq()
    
    # Add collection edge cases
    if Enum.any?(analysis.functions, &has_list_args?/1) do
      [:empty_list, :single_element, :large_list | edge_cases]
    else
      edge_cases
    end
  end
  
  defp parse_existing_tests(""), do: []
  defp parse_existing_tests(tests) do
    # Parse existing test names to avoid duplication
    Regex.scan(~r/test\s+"([^"]+)"/, tests)
    |> Enum.map(fn [_, name] -> name end)
  end
  
  defp extract_generated_tests(response) do
    case Regex.run(~r/```(?:elixir|ex)?\n(.*?)\n```/s, response, capture: :all_but_first) do
      [code] -> {:ok, String.trim(code)}
      _ -> 
        # Try without code fence
        if String.contains?(response, "defmodule") do
          {:ok, response}
        else
          {:error, "No test code found in response"}
        end
    end
  end
  
  defp format_tests(tests, _params) do
    # Ensure proper module structure
    if String.starts_with?(tests, "defmodule") do
      tests
    else
      # Wrap in test module if needed
      """
      defmodule GeneratedTest do
        use ExUnit.Case
        
        #{tests}
      end
      """
    end
  end
  
  defp count_tests(test_code) do
    Regex.scan(~r/test\s+"[^"]+"\s+do/, test_code)
    |> length()
  end
  
  defp estimate_coverage(analysis, test_code) do
    total_functions = length(analysis.functions)
    tested_functions = Regex.scan(~r/test.*".*\/(\\d+)/, test_code)
    |> length()
    
    if total_functions > 0 do
      min(100, round((tested_functions / total_functions) * 100))
    else
      0
    end
  end
  
  defp generate_suggestions(analysis, _test_code) do
    suggestions = []
    
    suggestions = if analysis.complexity > 15 do
      ["Consider breaking down complex functions for easier testing" | suggestions]
    else
      suggestions
    end
    
    suggestions = if analysis.side_effects != [] do
      ["Add tests for side effects: #{Enum.join(analysis.side_effects, ", ")}" | suggestions]
    else
      suggestions
    end
    
    suggestions = if length(analysis.functions) > 10 do
      ["Consider grouping related tests with describe blocks" | suggestions]
    else
      suggestions
    end
    
    Enum.reverse(suggestions)
  end
  
  # Helper functions
  
  defp format_functions_list(functions) do
    functions
    |> Enum.map(fn f ->
      "- #{f.name}/#{f.arity}#{if f.public, do: "", else: " (private)"}"
    end)
    |> Enum.join("\n")
  end
  
  defp extract_arg_info(nil), do: []
  defp extract_arg_info(args) do
    Enum.map(args, fn
      {name, _, _} when is_atom(name) -> %{name: name, type: :any}
      _ -> %{name: :unknown, type: :any}
    end)
  end
  
  defp extract_guards(_), do: []
  defp extract_doc(_), do: nil
  defp parse_spec(_), do: %{}
  
  defp has_genserver_callbacks?(ast) do
    _callbacks = [:init, :handle_call, :handle_cast, :handle_info]
    
    {_, found} = Macro.postwalk(ast, false, fn
      {:def, _, [{name, _, _} | _]}, _ when name in [:init, :handle_call, :handle_cast, :handle_info] ->
        {nil, true}
      node, acc ->
        {node, acc}
    end)
    
    found
  end
  
  defp has_streams?(ast) do
    {_, found} = Macro.postwalk(ast, false, fn
      {{:., _, [Stream, _]}, _, _}, _ -> {nil, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp has_processes?(ast) do
    {_, found} = Macro.postwalk(ast, false, fn
      {fun, _, _}, _ when fun in [:spawn, :spawn_link, :send] -> {nil, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp has_io?(ast) do
    {_, found} = Macro.postwalk(ast, false, fn
      {{:., _, [IO, _]}, _, _}, _ -> {nil, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp numeric_arg?(%{name: name}) do
    name_str = to_string(name)
    String.contains?(name_str, ["count", "number", "amount", "size", "length"])
  end
  
  defp has_list_args?(%{args: args}) do
    Enum.any?(args, fn %{name: name} ->
      String.contains?(to_string(name), ["list", "items", "elements"])
    end)
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
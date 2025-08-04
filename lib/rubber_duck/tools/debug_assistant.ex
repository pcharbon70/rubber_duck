defmodule RubberDuck.Tools.DebugAssistant do
  @moduledoc """
  Analyzes stack traces or runtime errors and suggests causes or fixes.
  
  This tool helps developers understand and resolve errors by analyzing
  stack traces, error messages, and providing contextual debugging advice.
  """
  
  use RubberDuck.Tool
  
  alias RubberDuck.LLM.Service
  
  tool do
    name :debug_assistant
    description "Analyzes stack traces or runtime errors and suggests causes or fixes"
    category :debugging
    version "1.0.0"
    tags [:debugging, :troubleshooting, :error_analysis, :diagnostics]
    
    parameter :error_message do
      type :string
      required true
      description "The error message or exception text"
      constraints [
        min_length: 1,
        max_length: 10000
      ]
    end
    
    parameter :stack_trace do
      type :string
      required false
      description "The full stack trace if available"
      default ""
      constraints [
        max_length: 50000
      ]
    end
    
    parameter :code_context do
      type :string
      required false
      description "Relevant code around where the error occurred"
      default ""
      constraints [
        max_length: 10000
      ]
    end
    
    parameter :analysis_depth do
      type :string
      required false
      description "How deep to analyze the error"
      default "comprehensive"
      constraints [
        enum: [
          "quick",          # Basic error explanation
          "comprehensive",  # Full analysis with multiple hypotheses
          "step_by_step"    # Detailed debugging steps
        ]
      ]
    end
    
    parameter :runtime_info do
      type :map
      required false
      description "Runtime information (Elixir version, dependencies, etc.)"
      default %{}
    end
    
    parameter :previous_attempts do
      type :list
      required false
      description "Previous debugging attempts that didn't work"
      default []
    end
    
    parameter :error_history do
      type :list
      required false
      description "Recent errors in the same session/module"
      default []
    end
    
    parameter :include_examples do
      type :boolean
      required false
      description "Include code examples in the solution"
      default true
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 2
    end
    
    security do
      sandbox :strict
      capabilities [:llm_access]
      rate_limit [max_requests: 100, window_seconds: 60]
    end
  end
  
  @doc """
  Executes the debug analysis based on the provided error information.
  """
  def execute(params, context) do
    with {:ok, parsed_error} <- parse_error_info(params),
         {:ok, analysis} <- analyze_error_patterns(parsed_error),
         {:ok, debugging_plan} <- create_debugging_plan(analysis, params),
         {:ok, suggestions} <- generate_suggestions(debugging_plan, params, context) do
      
      {:ok, %{
        error_type: analysis.error_type,
        likely_causes: analysis.likely_causes,
        debugging_steps: debugging_plan.steps,
        suggested_fixes: suggestions.fixes,
        code_examples: if(params.include_examples, do: suggestions.examples, else: []),
        additional_resources: suggestions.resources,
        confidence: calculate_confidence(analysis, parsed_error)
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp parse_error_info(params) do
    error_info = %{
      message: params.error_message,
      stack_trace: parse_stack_trace(params.stack_trace),
      error_module: extract_error_module(params.error_message),
      error_function: extract_error_function(params.stack_trace),
      line_numbers: extract_line_numbers(params.stack_trace),
      code_context: params.code_context,
      runtime_info: params.runtime_info
    }
    
    {:ok, error_info}
  end
  
  defp parse_stack_trace(""), do: []
  defp parse_stack_trace(stack_trace) do
    stack_trace
    |> String.split("\n")
    |> Enum.map(&parse_stack_line/1)
    |> Enum.reject(&is_nil/1)
  end
  
  defp parse_stack_line(line) do
    # Parse Elixir stack trace format
    # Example: "    (app 0.1.0) lib/module.ex:42: Module.function/2"
    case Regex.run(~r/\(([^)]+)\)\s+([^:]+):(\d+):\s+(.+)/, line) do
      [_, app, file, line_num, location] ->
        %{
          app: app,
          file: file,
          line: String.to_integer(line_num),
          location: location
        }
      _ ->
        # Try alternative format
        case Regex.run(~r/([^:]+):(\d+):\s+(.+)/, line) do
          [_, file, line_num, location] ->
            %{
              app: "unknown",
              file: file,
              line: String.to_integer(line_num),
              location: location
            }
          _ -> nil
        end
    end
  end
  
  defp extract_error_module(error_message) do
    # Extract module name from error message
    case Regex.run(~r/\(([A-Z][\w.]+)\)/, error_message) do
      [_, module] -> module
      _ -> 
        case Regex.run(~r/[A-Z][\w.]+/, error_message) do
          [module] -> module
          _ -> "Unknown"
        end
    end
  end
  
  defp extract_error_function(""), do: nil
  defp extract_error_function(stack_trace) do
    case parse_stack_trace(stack_trace) do
      [first | _] -> first.location
      [] -> nil
    end
  end
  
  defp extract_line_numbers(stack_trace) do
    parse_stack_trace(stack_trace)
    |> Enum.map(& &1.line)
    |> Enum.uniq()
  end
  
  defp analyze_error_patterns(error_info) do
    error_type = categorize_error(error_info.message)
    patterns = identify_common_patterns(error_info.message, error_type)
    
    analysis = %{
      error_type: error_type,
      patterns: patterns,
      likely_causes: determine_likely_causes(error_type, patterns, error_info),
      severity: assess_severity(error_type),
      category: categorize_error_domain(error_info)
    }
    
    {:ok, analysis}
  end
  
  defp categorize_error(message) do
    cond do
      message =~ ~r/UndefinedFunctionError/ -> :undefined_function
      message =~ ~r/ArgumentError/ -> :argument_error
      message =~ ~r/ArithmeticError/ -> :arithmetic_error
      message =~ ~r/BadMapError/ -> :bad_map_error
      message =~ ~r/BadStructError/ -> :bad_struct_error
      message =~ ~r/CaseClauseError/ -> :case_clause_error
      message =~ ~r/CompileError/ -> :compile_error
      message =~ ~r/CondClauseError/ -> :cond_clause_error
      message =~ ~r/FunctionClauseError/ -> :function_clause_error
      message =~ ~r/KeyError/ -> :key_error
      message =~ ~r/MatchError/ -> :match_error
      message =~ ~r/Protocol\.UndefinedError/ -> :protocol_undefined
      message =~ ~r/RuntimeError/ -> :runtime_error
      message =~ ~r/SystemLimitError/ -> :system_limit_error
      message =~ ~r/TokenMissingError/ -> :token_missing_error
      message =~ ~r/TryClauseError/ -> :try_clause_error
      message =~ ~r/WithClauseError/ -> :with_clause_error
      message =~ ~r/Postgrex/ -> :database_error
      message =~ ~r/Phoenix/ -> :phoenix_error
      message =~ ~r/Ecto/ -> :ecto_error
      message =~ ~r/GenServer/ -> :genserver_error
      message =~ ~r/timeout/ -> :timeout_error
      message =~ ~r/connection/ -> :connection_error
      true -> :generic_error
    end
  end
  
  defp identify_common_patterns(message, _error_type) do
    patterns = []
    
    # Pattern detection based on error type and message content
    patterns = if message =~ ~r/nil/, do: [:nil_value | patterns], else: patterns
    patterns = if message =~ ~r/empty/, do: [:empty_collection | patterns], else: patterns
    patterns = if message =~ ~r/not found/, do: [:resource_not_found | patterns], else: patterns
    patterns = if message =~ ~r/already exists/, do: [:duplicate_resource | patterns], else: patterns
    patterns = if message =~ ~r/invalid/, do: [:validation_failure | patterns], else: patterns
    patterns = if message =~ ~r/timeout/, do: [:timeout | patterns], else: patterns
    patterns = if message =~ ~r/connection/, do: [:connection_issue | patterns], else: patterns
    
    patterns
  end
  
  defp determine_likely_causes(error_type, patterns, _error_info) do
    base_causes = case error_type do
      :undefined_function ->
        [
          "Function doesn't exist or module not loaded",
          "Typo in function name or wrong arity",
          "Module not aliased or imported",
          "Dependency not included in mix.exs"
        ]
      
      :function_clause_error ->
        [
          "No function clause matching the given arguments",
          "Pattern matching failure in function head",
          "Guard clause preventing match",
          "Wrong data type passed to function"
        ]
      
      :key_error ->
        [
          "Accessing a key that doesn't exist in a map",
          "Struct field not defined",
          "Using atom key on string-keyed map or vice versa",
          "Data shape different than expected"
        ]
      
      :match_error ->
        [
          "Pattern match failed",
          "Unexpected data structure returned",
          "Missing error handling for failure case",
          "Assumption about data shape incorrect"
        ]
      
      :timeout_error ->
        [
          "Operation took longer than allowed timeout",
          "Deadlock or infinite loop",
          "External service not responding",
          "Heavy computation blocking process"
        ]
      
      :database_error ->
        [
          "Database connection issues",
          "Invalid query syntax",
          "Constraint violation",
          "Missing migration or schema mismatch"
        ]
      
      _ ->
        ["Generic error occurred"]
    end
    
    # Add pattern-specific causes
    pattern_causes = patterns
    |> Enum.flat_map(fn
      :nil_value -> ["Unexpected nil value", "Missing required data"]
      :empty_collection -> ["Empty list or map when data expected"]
      :resource_not_found -> ["Referenced resource doesn't exist"]
      _ -> []
    end)
    
    Enum.uniq(base_causes ++ pattern_causes)
  end
  
  defp assess_severity(error_type) do
    case error_type do
      :compile_error -> :critical
      :system_limit_error -> :critical
      :database_error -> :high
      :timeout_error -> :high
      :undefined_function -> :medium
      :function_clause_error -> :medium
      :key_error -> :low
      :match_error -> :low
      _ -> :medium
    end
  end
  
  defp categorize_error_domain(error_info) do
    cond do
      error_info.error_module =~ ~r/Ecto/ -> :database
      error_info.error_module =~ ~r/Phoenix/ -> :web
      error_info.error_module =~ ~r/GenServer/ -> :concurrency
      error_info.error_module =~ ~r/Stream/ -> :data_processing
      error_info.error_module =~ ~r/File/ -> :file_system
      true -> :application
    end
  end
  
  defp create_debugging_plan(analysis, params) do
    steps = case params.analysis_depth do
      "quick" -> generate_quick_steps(analysis)
      "comprehensive" -> generate_comprehensive_steps(analysis)
      "step_by_step" -> generate_detailed_steps(analysis)
    end
    
    plan = %{
      steps: steps,
      priority: determine_debugging_priority(analysis),
      estimated_time: estimate_debugging_time(analysis, params.analysis_depth)
    }
    
    {:ok, plan}
  end
  
  defp generate_quick_steps(analysis) do
    [
      "Check the error message and identify the failing function",
      "Verify the data being passed matches expected types",
      "Look for the most likely cause: #{hd(analysis.likely_causes)}"
    ]
  end
  
  defp generate_comprehensive_steps(analysis) do
    [
      "1. Examine the stack trace to identify the exact failure point",
      "2. Check all function arguments and their types",
      "3. Verify pattern matches and guard clauses",
      "4. Test each likely cause:\n   #{Enum.map_join(analysis.likely_causes, "\n   ", &"- #{&1}")}",
      "5. Add debugging output (IO.inspect) to trace data flow",
      "6. Check for edge cases and error handling",
      "7. Review recent changes that might have introduced the error"
    ]
  end
  
  defp generate_detailed_steps(analysis) do
    base_steps = [
      %{
        step: 1,
        action: "Locate the error source",
        details: "Find the exact line and function where the error occurs",
        commands: ["Check stack trace line numbers", "Open the file at the error location"]
      },
      %{
        step: 2,
        action: "Inspect input data",
        details: "Add IO.inspect/2 calls to see actual vs expected data",
        commands: ["IO.inspect(variable, label: \"Variable name\")", "Check data types with is_* guards"]
      },
      %{
        step: 3,
        action: "Test hypotheses",
        details: "Systematically test each likely cause",
        commands: ["Use IEx to test function with different inputs", "Check for nil values"]
      }
    ]
    
    # Add error-specific steps
    specific_steps = case analysis.error_type do
      :undefined_function ->
        [%{
          step: 4,
          action: "Verify module and function existence",
          details: "Ensure the module is compiled and function is defined",
          commands: ["Module.defines?(ModuleName, :function_name, arity)", "Check module aliases"]
        }]
      
      :database_error ->
        [%{
          step: 4,
          action: "Check database connection",
          details: "Verify database is running and accessible",
          commands: ["Mix.Task.run(\"ecto.migrate\")", "Check connection configuration"]
        }]
      
      _ -> []
    end
    
    base_steps ++ specific_steps
  end
  
  defp determine_debugging_priority(analysis) do
    case analysis.severity do
      :critical -> :immediate
      :high -> :urgent
      :medium -> :normal
      :low -> :low
    end
  end
  
  defp estimate_debugging_time(_analysis, depth) do
    case depth do
      "quick" -> "5-10 minutes"
      "comprehensive" -> "15-30 minutes"
      "step_by_step" -> "30-60 minutes"
    end
  end
  
  defp generate_suggestions(debugging_plan, params, context) do
    prompt = build_suggestion_prompt(params, debugging_plan)
    
    case Service.generate(%{
      prompt: prompt,
      max_tokens: 2000,
      temperature: 0.3,
      model: context[:llm_model] || "gpt-4"
    }) do
      {:ok, response} -> parse_suggestions(response, params)
      error -> error
    end
  end
  
  defp build_suggestion_prompt(params, debugging_plan) do
    """
    Analyze this Elixir error and provide debugging suggestions:
    
    Error Message:
    #{params.error_message}
    
    #{if params.stack_trace != "", do: "Stack Trace:\n#{params.stack_trace}\n", else: ""}
    #{if params.code_context != "", do: "Code Context:\n#{params.code_context}\n", else: ""}
    
    Analysis shows this is likely a #{debugging_plan.priority} priority issue.
    
    Please provide:
    1. Specific fixes for this error (2-3 solutions)
    2. #{if params.include_examples, do: "Code examples showing the fix", else: "Brief fix descriptions"}
    3. Resources for learning more about this error type
    
    #{if params.previous_attempts != [], do: "Already tried:\n#{Enum.join(params.previous_attempts, "\n")}", else: ""}
    
    Focus on Elixir-specific solutions and best practices.
    """
  end
  
  defp parse_suggestions(response, params) do
    # Parse the LLM response to extract fixes, examples, and resources
    sections = String.split(response, ~r/\n\d+\.\s+/)
    
    fixes = extract_fixes(sections)
    examples = if params.include_examples, do: extract_code_examples(response), else: []
    resources = extract_resources(response)
    
    {:ok, %{
      fixes: fixes,
      examples: examples,
      resources: resources
    }}
  end
  
  defp extract_fixes(sections) do
    sections
    |> Enum.filter(&String.contains?(&1, ["fix", "solution", "resolve"]))
    |> Enum.take(3)
    |> Enum.map(&String.trim/1)
  end
  
  defp extract_code_examples(response) do
    Regex.scan(~r/```(?:elixir)?\n(.*?)\n```/s, response, capture: :all_but_first)
    |> Enum.map(fn [code] -> String.trim(code) end)
  end
  
  defp extract_resources(response) do
    # Extract URLs and resource mentions
    urls = Regex.scan(~r/https?:\/\/[^\s]+/, response) |> List.flatten()
    
    # Common Elixir resources
    resources = []
    resources = if response =~ ~r/hexdocs/i, do: ["HexDocs documentation" | resources], else: resources
    resources = if response =~ ~r/elixir.*forum/i, do: ["Elixir Forum" | resources], else: resources
    resources = if response =~ ~r/stack.*overflow/i, do: ["Stack Overflow" | resources], else: resources
    
    Enum.uniq(urls ++ resources)
  end
  
  defp calculate_confidence(analysis, error_info) do
    # Calculate confidence based on available information
    base_confidence = 50
    
    confidence = base_confidence
    confidence = if error_info.stack_trace != [], do: confidence + 20, else: confidence
    confidence = if error_info.code_context != "", do: confidence + 15, else: confidence
    confidence = if length(analysis.likely_causes) > 2, do: confidence + 10, else: confidence
    confidence = if analysis.error_type != :generic_error, do: confidence + 5, else: confidence
    
    min(100, confidence)
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
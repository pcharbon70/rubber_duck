defmodule RubberDuck.Tools.CodeSummarizer do
  @moduledoc """
  Summarizes the responsibilities and purpose of a file or module.
  
  This tool analyzes Elixir code to generate concise summaries of what
  modules, files, or code sections do, including their main responsibilities,
  key functions, and architectural patterns.
  """
  
  use RubberDuck.Tool
  
  alias RubberDuck.LLM.Service
  
  tool do
    name :code_summarizer
    description "Summarizes the responsibilities and purpose of a file or module"
    category :documentation
    version "1.0.0"
    tags [:documentation, :analysis, :summary, :understanding]
    
    parameter :code do
      type :string
      required true
      description "The code to summarize"
      constraints [
        min_length: 1,
        max_length: 100_000
      ]
    end
    
    parameter :summary_type do
      type :string
      required false
      description "Type of summary to generate"
      default "comprehensive"
      constraints [
        enum: [
          "brief",          # Short one-line summary
          "comprehensive", # Detailed analysis
          "technical",     # Focus on technical aspects
          "functional",    # Focus on functionality
          "architectural"  # Focus on design patterns
        ]
      ]
    end
    
    parameter :focus_level do
      type :string
      required false
      description "Level of code to focus summary on"
      default "module"
      constraints [
        enum: ["file", "module", "function", "all"]
      ]
    end
    
    parameter :include_examples do
      type :boolean
      required false
      description "Include usage examples in summary"
      default true
    end
    
    parameter :include_dependencies do
      type :boolean
      required false
      description "Include dependency analysis"
      default true
    end
    
    parameter :include_complexity do
      type :boolean
      required false
      description "Include complexity analysis"
      default false
    end
    
    parameter :target_audience do
      type :string
      required false
      description "Target audience for the summary"
      default "developer"
      constraints [
        enum: ["developer", "manager", "newcomer", "maintainer"]
      ]
    end
    
    parameter :max_length do
      type :integer
      required false
      description "Maximum length of summary in words"
      default 200
      constraints [
        min: 10,
        max: 1000
      ]
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
  Executes code summarization based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, parsed} <- parse_and_analyze_code(params.code),
         {:ok, extracted} <- extract_key_information(parsed, params),
         {:ok, summary} <- generate_summary(extracted, params, context) do
      
      {:ok, %{
        summary: summary,
        analysis: %{
          modules: extracted.modules,
          functions: extracted.function_summary,
          dependencies: extracted.dependencies,
          complexity: extracted.complexity,
          patterns: extracted.patterns
        },
        metadata: %{
          summary_type: params.summary_type,
          focus_level: params.focus_level,
          target_audience: params.target_audience,
          code_metrics: extracted.metrics
        }
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp parse_and_analyze_code(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} ->
        analysis = %{
          ast: ast,
          raw_code: code,
          lines: String.split(code, "\n"),
          line_count: length(String.split(code, "\n")),
          char_count: String.length(code)
        }
        {:ok, analysis}
      
      {:error, {line, error, token}} ->
        {:error, "Parse error on line #{line}: #{error} #{inspect(token)}"}
    end
  end
  
  defp extract_key_information(parsed, params) do
    extracted = %{
      modules: extract_modules(parsed.ast),
      functions: extract_functions(parsed.ast),
      dependencies: if(params.include_dependencies, do: extract_dependencies(parsed.ast), else: []),
      complexity: if(params.include_complexity, do: analyze_complexity(parsed.ast), else: %{}),
      patterns: identify_patterns(parsed.ast),
      metrics: calculate_metrics(parsed),
      documentation: extract_documentation(parsed.ast)
    }
    
    # Add function summary based on focus level
    function_summary = case params.focus_level do
      "function" -> detailed_function_analysis(extracted.functions)
      "module" -> module_function_summary(extracted.functions)
      "file" -> file_function_summary(extracted.functions)
      "all" -> comprehensive_function_analysis(extracted.functions)
    end
    
    extracted = Map.put(extracted, :function_summary, function_summary)
    
    {:ok, extracted}
  end
  
  defp extract_modules(ast) do
    {_, modules} = Macro.postwalk(ast, [], fn node, acc ->
      case node do
        {:defmodule, meta, [{:__aliases__, _, parts} | [body]]} ->
          module_info = %{
            name: Module.concat(parts),
            line: Keyword.get(meta, :line, 0),
            functions: extract_module_functions(body),
            attributes: extract_module_attributes(body),
            documentation: extract_module_doc(body)
          }
          {node, [module_info | acc]}
        _ ->
          {node, acc}
      end
    end)
    
    Enum.reverse(modules)
  end
  
  defp extract_module_functions(body) do
    {_, functions} = Macro.postwalk(body, [], fn node, acc ->
      case node do
        {:def, meta, [{name, _, args} | _]} when is_atom(name) ->
          func_info = %{
            name: name,
            arity: if(args, do: length(args), else: 0),
            line: Keyword.get(meta, :line, 0),
            visibility: :public
          }
          {node, [func_info | acc]}
        
        {:defp, meta, [{name, _, args} | _]} when is_atom(name) ->
          func_info = %{
            name: name,
            arity: if(args, do: length(args), else: 0),
            line: Keyword.get(meta, :line, 0),
            visibility: :private
          }
          {node, [func_info | acc]}
        
        _ ->
          {node, acc}
      end
    end)
    
    Enum.reverse(functions)
  end
  
  defp extract_module_attributes(body) do
    {_, attributes} = Macro.postwalk(body, [], fn node, acc ->
      case node do
        {:@, _, [{attr, _, _}]} when attr in [:doc, :moduledoc, :spec, :type, :behaviour] ->
          {node, [attr | acc]}
        _ ->
          {node, acc}
      end
    end)
    
    Enum.uniq(Enum.reverse(attributes))
  end
  
  defp extract_module_doc(body) do
    {_, docs} = Macro.postwalk(body, nil, fn node, acc ->
      case node do
        {:@, _, [{:moduledoc, _, [doc]}]} when is_binary(doc) ->
          {node, doc}
        _ ->
          {node, acc}
      end
    end)
    
    docs
  end
  
  defp extract_functions(ast) do
    {_, functions} = Macro.postwalk(ast, [], fn node, acc ->
      case node do
        {:def, meta, [{name, _, args} | [body]]} when is_atom(name) ->
          func_info = %{
            name: name,
            arity: if(args, do: length(args), else: 0),
            line: Keyword.get(meta, :line, 0),
            visibility: :public,
            calls: extract_function_calls(body),
            complexity: estimate_function_complexity(body),
            purpose: infer_function_purpose(name, args, body)
          }
          {node, [func_info | acc]}
        
        {:defp, meta, [{name, _, args} | [body]]} when is_atom(name) ->
          func_info = %{
            name: name,
            arity: if(args, do: length(args), else: 0),
            line: Keyword.get(meta, :line, 0),
            visibility: :private,
            calls: extract_function_calls(body),
            complexity: estimate_function_complexity(body),
            purpose: infer_function_purpose(name, args, body)
          }
          {node, [func_info | acc]}
        
        _ ->
          {node, acc}
      end
    end)
    
    Enum.reverse(functions)
  end
  
  defp extract_function_calls(body) do
    {_, calls} = Macro.postwalk(body, [], fn node, acc ->
      case node do
        {func_name, _, _} when is_atom(func_name) and func_name not in [:__aliases__, :., :when] ->
          {node, [func_name | acc]}
        {{:., _, [{:__aliases__, _, parts}, func_name]}, _, _} ->
          module = Module.concat(parts)
          {node, [{module, func_name} | acc]}
        _ ->
          {node, acc}
      end
    end)
    
    Enum.uniq(Enum.reverse(calls))
  end
  
  defp estimate_function_complexity(body) do
    {_, complexity} = Macro.postwalk(body, 1, fn
      {:if, _, _} = node, acc -> {node, acc + 1}
      {:case, _, _} = node, acc -> {node, acc + 2}
      {:cond, _, _} = node, acc -> {node, acc + 2}
      {:with, _, _} = node, acc -> {node, acc + 1}
      {:try, _, _} = node, acc -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    
    complexity
  end
  
  defp infer_function_purpose(name, args, body) do
    name_str = to_string(name)
    arity = if args, do: length(args), else: 0
    
    cond do
      name in [:new, :create, :build] -> :constructor
      name in [:get, :fetch, :find, :load] -> :getter
      name in [:put, :set, :update, :save] -> :setter
      name in [:delete, :remove, :destroy] -> :destructor
      String.ends_with?(name_str, "?") -> :predicate
      String.ends_with?(name_str, "!") -> :mutator
      String.starts_with?(name_str, "is_") -> :predicate
      String.starts_with?(name_str, "has_") -> :predicate
      String.starts_with?(name_str, "can_") -> :predicate
      String.contains?(name_str, "valid") -> :validator
      String.contains?(name_str, "parse") -> :parser
      String.contains?(name_str, "format") -> :formatter
      String.contains?(name_str, "handle") -> :handler
      arity == 0 -> :constant
      contains_io_operations?(body) -> :io_operation
      contains_calculations?(body) -> :calculator
      true -> :general
    end
  end
  
  defp contains_io_operations?(body) do
    {_, found} = Macro.postwalk(body, false, fn
      {func, _, _} = node, _acc when func in [:puts, :inspect, :print, :write] -> {node, true}
      {{:., _, [{:__aliases__, _, [:IO]}, _]}, _, _} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp contains_calculations?(body) do
    {_, found} = Macro.postwalk(body, false, fn
      {op, _, _} = node, _acc when op in [:+, :-, :*, :/, :div, :rem] -> {node, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp extract_dependencies(ast) do
    {_, deps} = Macro.postwalk(ast, %{imports: [], aliases: [], uses: [], external_calls: []}, fn node, acc ->
      case node do
        {:import, _, [{:__aliases__, _, parts} | _]} ->
          {node, update_in(acc.imports, &[Module.concat(parts) | &1])}
        
        {:alias, _, [{:__aliases__, _, parts} | _]} ->
          {node, update_in(acc.aliases, &[Module.concat(parts) | &1])}
        
        {:use, _, [{:__aliases__, _, parts} | _]} ->
          {node, update_in(acc.uses, &[Module.concat(parts) | &1])}
        
        {{:., _, [{:__aliases__, _, parts}, func]}, _, _} ->
          module = Module.concat(parts)
          {node, update_in(acc.external_calls, &[{module, func} | &1])}
        
        _ ->
          {node, acc}
      end
    end)
    
    %{
      imports: Enum.uniq(deps.imports),
      aliases: Enum.uniq(deps.aliases),
      uses: Enum.uniq(deps.uses),
      external_calls: Enum.uniq(deps.external_calls)
    }
  end
  
  defp analyze_complexity(ast) do
    {_, analysis} = Macro.postwalk(ast, %{cyclomatic: 1, nesting_depth: 0, max_nesting: 0}, fn node, acc ->
      case node do
        {:if, _, _} ->
          {node, %{acc | cyclomatic: acc.cyclomatic + 1, nesting_depth: acc.nesting_depth + 1, max_nesting: max(acc.max_nesting, acc.nesting_depth + 1)}}
        
        {:case, _, _} ->
          {node, %{acc | cyclomatic: acc.cyclomatic + 2, nesting_depth: acc.nesting_depth + 1, max_nesting: max(acc.max_nesting, acc.nesting_depth + 1)}}
        
        {:cond, _, _} ->
          {node, %{acc | cyclomatic: acc.cyclomatic + 2}}
        
        {:with, _, _} ->
          {node, %{acc | cyclomatic: acc.cyclomatic + 1}}
        
        _ ->
          {node, acc}
      end
    end)
    
    analysis
  end
  
  defp identify_patterns(ast) do
    patterns = []
    
    # Check for common patterns
    patterns = if has_genserver_pattern?(ast), do: [:genserver | patterns], else: patterns
    patterns = if has_supervision_pattern?(ast), do: [:supervisor | patterns], else: patterns
    patterns = if has_protocol_pattern?(ast), do: [:protocol | patterns], else: patterns
    patterns = if has_behaviour_pattern?(ast), do: [:behaviour | patterns], else: patterns
    patterns = if has_struct_pattern?(ast), do: [:struct | patterns], else: patterns
    patterns = if has_pipeline_pattern?(ast), do: [:pipeline | patterns], else: patterns
    patterns = if has_error_handling_pattern?(ast), do: [:error_handling | patterns], else: patterns
    
    Enum.reverse(patterns)
  end
  
  defp has_genserver_pattern?(ast) do
    {_, found} = Macro.postwalk(ast, false, fn
      {:use, _, [{:__aliases__, _, [:GenServer]} | _]} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp has_supervision_pattern?(ast) do
    {_, found} = Macro.postwalk(ast, false, fn
      {:use, _, [{:__aliases__, _, [:Supervisor]} | _]} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp has_protocol_pattern?(ast) do
    {_, found} = Macro.postwalk(ast, false, fn
      {:defprotocol, _, _} = node, _acc -> {node, true}
      {:defimpl, _, _} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp has_behaviour_pattern?(ast) do
    {_, found} = Macro.postwalk(ast, false, fn
      {:@, _, [{:behaviour, _, _}]} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp has_struct_pattern?(ast) do
    {_, found} = Macro.postwalk(ast, false, fn
      {:defstruct, _, _} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp has_pipeline_pattern?(ast) do
    {_, found} = Macro.postwalk(ast, false, fn
      {:|>, _, _} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp has_error_handling_pattern?(ast) do
    {_, found} = Macro.postwalk(ast, false, fn
      {:with, _, _} = node, _acc -> {node, true}
      {:try, _, _} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    found
  end
  
  defp calculate_metrics(parsed) do
    %{
      lines_of_code: parsed.line_count,
      characters: parsed.char_count,
      blank_lines: count_blank_lines(parsed.lines),
      comment_lines: count_comment_lines(parsed.lines),
      code_lines: parsed.line_count - count_blank_lines(parsed.lines) - count_comment_lines(parsed.lines)
    }
  end
  
  defp count_blank_lines(lines) do
    Enum.count(lines, &(String.trim(&1) == ""))
  end
  
  defp count_comment_lines(lines) do
    Enum.count(lines, &String.starts_with?(String.trim(&1), "#"))
  end
  
  defp extract_documentation(ast) do
    {_, docs} = Macro.postwalk(ast, %{moduledocs: [], docs: []}, fn node, acc ->
      case node do
        {:@, _, [{:moduledoc, _, [doc]}]} when is_binary(doc) ->
          {node, update_in(acc.moduledocs, &[doc | &1])}
        
        {:@, _, [{:doc, _, [doc]}]} when is_binary(doc) ->
          {node, update_in(acc.docs, &[doc | &1])}
        
        _ ->
          {node, acc}
      end
    end)
    
    %{
      moduledocs: Enum.reverse(docs.moduledocs),
      function_docs: Enum.reverse(docs.docs)
    }
  end
  
  defp detailed_function_analysis(functions) do
    Enum.map(functions, fn func ->
      %{
        signature: "#{func.name}/#{func.arity}",
        purpose: func.purpose,
        complexity: func.complexity,
        visibility: func.visibility,
        calls: length(func.calls),
        description: generate_function_description(func)
      }
    end)
  end
  
  defp module_function_summary(functions) do
    public_functions = Enum.filter(functions, &(&1.visibility == :public))
    private_functions = Enum.filter(functions, &(&1.visibility == :private))
    
    %{
      public_count: length(public_functions),
      private_count: length(private_functions),
      main_functions: Enum.take(public_functions, 5) |> Enum.map(&"#{&1.name}/#{&1.arity}"),
      complexity_distribution: analyze_complexity_distribution(functions)
    }
  end
  
  defp file_function_summary(functions) do
    %{
      total_functions: length(functions),
      average_complexity: calculate_average_complexity(functions),
      most_complex: find_most_complex_function(functions),
      purpose_distribution: analyze_purpose_distribution(functions)
    }
  end
  
  defp comprehensive_function_analysis(functions) do
    %{
      detailed: detailed_function_analysis(functions),
      module_summary: module_function_summary(functions),
      file_summary: file_function_summary(functions)
    }
  end
  
  defp generate_function_description(func) do
    case func.purpose do
      :constructor -> "Creates and initializes new instances"
      :getter -> "Retrieves and returns data"
      :setter -> "Updates or modifies data"
      :destructor -> "Removes or cleans up resources"
      :predicate -> "Tests conditions and returns boolean"
      :validator -> "Validates input and ensures correctness"
      :parser -> "Parses and transforms data formats"
      :formatter -> "Formats data for display or output"
      :handler -> "Handles events or processes requests"
      :io_operation -> "Performs input/output operations"
      :calculator -> "Performs calculations and computations"
      _ -> "General purpose function"
    end
  end
  
  defp analyze_complexity_distribution(functions) do
    complexities = Enum.map(functions, & &1.complexity)
    
    %{
      low: Enum.count(complexities, &(&1 <= 3)),
      medium: Enum.count(complexities, &(&1 > 3 and &1 <= 7)),
      high: Enum.count(complexities, &(&1 > 7))
    }
  end
  
  defp calculate_average_complexity(functions) do
    if length(functions) > 0 do
      total = Enum.sum(Enum.map(functions, & &1.complexity))
      Float.round(total / length(functions), 2)
    else
      0.0
    end
  end
  
  defp find_most_complex_function(functions) do
    case Enum.max_by(functions, & &1.complexity, fn -> nil end) do
      nil -> nil
      func -> "#{func.name}/#{func.arity} (complexity: #{func.complexity})"
    end
  end
  
  defp analyze_purpose_distribution(functions) do
    functions
    |> Enum.group_by(& &1.purpose)
    |> Enum.map(fn {purpose, funcs} -> {purpose, length(funcs)} end)
    |> Enum.into(%{})
  end
  
  defp generate_summary(extracted, params, context) do
    case params.summary_type do
      "brief" -> generate_brief_summary(extracted, params)
      "comprehensive" -> generate_comprehensive_summary(extracted, params, context)
      "technical" -> generate_technical_summary(extracted, params)
      "functional" -> generate_functional_summary(extracted, params)
      "architectural" -> generate_architectural_summary(extracted, params)
    end
  end
  
  defp generate_brief_summary(extracted, _params) do
    module_count = length(extracted.modules)
    function_count = length(extracted.functions)
    
    primary_module = if module_count > 0, do: hd(extracted.modules).name, else: "Unknown"
    
    summary = if module_count == 1 do
      "#{primary_module} module with #{function_count} functions"
    else
      "#{module_count} modules with #{function_count} total functions"
    end
    
    {:ok, summary}
  end
  
  defp generate_comprehensive_summary(extracted, params, context) do
    prompt = build_comprehensive_prompt(extracted, params)
    
    case Service.generate(%{
      prompt: prompt,
      max_tokens: params.max_length * 4,  # Rough conversion
      temperature: 0.3,
      model: context[:llm_model] || "gpt-4"
    }) do
      {:ok, response} ->
        summary = trim_to_word_limit(response, params.max_length)
        {:ok, summary}
      
      {:error, _} ->
        # Fallback to template-based summary
        generate_template_summary(extracted, params)
    end
  end
  
  defp build_comprehensive_prompt(extracted, params) do
    module_info = if length(extracted.modules) > 0 do
      modules = Enum.map(extracted.modules, fn mod ->
        "- #{mod.name}: #{length(mod.functions)} functions"
      end) |> Enum.join("\n")
      "Modules:\n#{modules}\n\n"
    else
      ""
    end
    
    function_info = if length(extracted.functions) > 0 do
      main_functions = extracted.functions
      |> Enum.filter(&(&1.visibility == :public))
      |> Enum.take(10)
      |> Enum.map(&"- #{&1.name}/#{&1.arity}: #{generate_function_description(&1)}")
      |> Enum.join("\n")
      "Key Functions:\n#{main_functions}\n\n"
    else
      ""
    end
    
    pattern_info = if length(extracted.patterns) > 0 do
      "Patterns: #{Enum.join(extracted.patterns, ", ")}\n\n"
    else
      ""
    end
    
    dependency_info = if extracted.dependencies != [] and length(extracted.dependencies.imports) > 0 do
      "Dependencies: #{Enum.join(extracted.dependencies.imports, ", ")}\n\n"
    else
      ""
    end
    
    audience_instruction = case params.target_audience do
      "manager" -> "Write for a technical manager who needs a high-level overview."
      "newcomer" -> "Write for a new developer who needs to understand the codebase."
      "maintainer" -> "Write for a maintainer who needs to understand maintenance concerns."
      _ -> "Write for an experienced developer."
    end
    
    """
    Analyze this Elixir code and provide a #{params.summary_type} summary.
    
    #{module_info}#{function_info}#{pattern_info}#{dependency_info}
    Code Metrics:
    - Lines of code: #{extracted.metrics.lines_of_code}
    - Functions: #{length(extracted.functions)}
    - Complexity patterns: #{inspect(extracted.patterns)}
    
    #{audience_instruction}
    
    Focus: #{params.focus_level} level analysis.
    Maximum length: #{params.max_length} words.
    
    Provide a clear, concise summary that explains:
    1. What this code does (main purpose)
    2. Key responsibilities
    3. Notable patterns or architectural decisions
    #{if params.include_examples, do: "4. Usage examples or key entry points", else: ""}
    """
  end
  
  defp generate_template_summary(extracted, params) do
    # Template-based fallback summary
    module_count = length(extracted.modules)
    function_count = length(extracted.functions)
    public_count = Enum.count(extracted.functions, &(&1.visibility == :public))
    
    summary_parts = []
    
    # Basic description
    basic = if module_count == 1 do
      primary_module = hd(extracted.modules)
      "This code defines the #{primary_module.name} module"
    else
      "This code contains #{module_count} modules"
    end
    summary_parts = [basic | summary_parts]
    
    # Function information
    if function_count > 0 do
      func_desc = "with #{public_count} public and #{function_count - public_count} private functions"
      summary_parts = [func_desc | summary_parts]
    end
    
    # Patterns
    if length(extracted.patterns) > 0 do
      pattern_desc = "implementing #{Enum.join(extracted.patterns, ", ")} patterns"
      summary_parts = [pattern_desc | summary_parts]
    end
    
    # Dependencies
    if extracted.dependencies != [] and length(extracted.dependencies.imports) > 0 do
      dep_desc = "and depending on #{Enum.join(Enum.take(extracted.dependencies.imports, 3), ", ")}"
      summary_parts = [dep_desc | summary_parts]
    end
    
    summary = summary_parts
    |> Enum.reverse()
    |> Enum.join(" ")
    |> String.trim_trailing(",")
    |> Kernel.<>(".")
    
    {:ok, summary}
  end
  
  defp generate_technical_summary(extracted, _params) do
    complexity = if extracted.complexity != %{} do
      "Cyclomatic complexity: #{extracted.complexity.cyclomatic}, Max nesting: #{extracted.complexity.max_nesting}. "
    else
      ""
    end
    
    patterns = if length(extracted.patterns) > 0 do
      "Uses #{Enum.join(extracted.patterns, ", ")} patterns. "
    else
      ""
    end
    
    deps = if extracted.dependencies != [] and length(extracted.dependencies.imports) > 0 do
      "Dependencies: #{Enum.join(extracted.dependencies.imports, ", ")}."
    else
      "No external dependencies."
    end
    
    summary = "#{complexity}#{patterns}#{deps}"
    {:ok, String.trim(summary)}
  end
  
  defp generate_functional_summary(extracted, _params) do
    purposes = extracted.functions
    |> Enum.map(& &1.purpose)
    |> Enum.uniq()
    
    main_purposes = case purposes do
      [] -> "No specific functionality identified"
      [single] -> "Primarily #{single} functionality"
      multiple -> "Provides #{Enum.join(Enum.take(multiple, 3), ", ")} functionality"
    end
    
    public_functions = Enum.filter(extracted.functions, &(&1.visibility == :public))
    entry_points = if length(public_functions) > 0 do
      main_funcs = public_functions
      |> Enum.take(3)
      |> Enum.map(&"#{&1.name}/#{&1.arity}")
      |> Enum.join(", ")
      " Main entry points: #{main_funcs}."
    else
      ""
    end
    
    summary = "#{main_purposes}.#{entry_points}"
    {:ok, String.trim(summary)}
  end
  
  defp generate_architectural_summary(extracted, _params) do
    patterns = if length(extracted.patterns) > 0 do
      "Implements #{Enum.join(extracted.patterns, ", ")} architectural patterns. "
    else
      "Uses standard Elixir module structure. "
    end
    
    structure = if length(extracted.modules) > 1 do
      "Multi-module architecture with #{length(extracted.modules)} modules. "
    else
      "Single module architecture. "
    end
    
    dependencies = if extracted.dependencies != [] and length(extracted.dependencies.imports) > 0 do
      "Integrates with #{length(extracted.dependencies.imports)} external modules."
    else
      "Self-contained with minimal external dependencies."
    end
    
    summary = "#{structure}#{patterns}#{dependencies}"
    {:ok, String.trim(summary)}
  end
  
  defp trim_to_word_limit(text, max_words) do
    words = String.split(text, ~r/\s+/)
    if length(words) <= max_words do
      text
    else
      words
      |> Enum.take(max_words)
      |> Enum.join(" ")
      |> Kernel.<>("...")
    end
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
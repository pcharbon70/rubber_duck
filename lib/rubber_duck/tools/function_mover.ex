defmodule RubberDuck.Tools.FunctionMover do
  @moduledoc """
  Moves functions between files or modules and updates references.
  
  This tool analyzes code to safely move functions between modules while:
  - Preserving functionality and behavior
  - Updating all references to the moved function
  - Handling imports, aliases, and fully-qualified calls
  - Maintaining proper module dependencies
  """
  
  use RubberDuck.Tool
  
  alias RubberDuck.LLM.Service
  
  tool do
    name :function_mover
    description "Moves functions between files or modules and updates references"
    category :code_transformation
    version "1.0.0"
    tags [:refactoring, :move, :function, :module, :reorganization]
    
    parameter :source_code do
      type :string
      required true
      description "The source module code containing the function to move"
      constraints [
        min_length: 1,
        max_length: 50_000
      ]
    end
    
    parameter :target_code do
      type :string
      required true
      description "The target module code where the function will be moved"
      constraints [
        min_length: 1,
        max_length: 50_000
      ]
    end
    
    parameter :function_name do
      type :string
      required true
      description "Name of the function to move (e.g., 'calculate_total')"
      constraints [
        min_length: 1,
        max_length: 100,
        pattern: ~r/^[a-z_][a-zA-Z0-9_!?]*$/
      ]
    end
    
    parameter :function_arity do
      type :integer
      required false
      description "Arity of the function to move (if multiple functions with same name)"
      default nil
      constraints [
        min: 0,
        max: 255
      ]
    end
    
    parameter :source_module do
      type :string
      required true
      description "Full source module name (e.g., 'MyApp.Calculations')"
      constraints [
        pattern: ~r/^[A-Z][A-Za-z0-9._]*$/
      ]
    end
    
    parameter :target_module do
      type :string
      required true
      description "Full target module name (e.g., 'MyApp.Utils.Math')"
      constraints [
        pattern: ~r/^[A-Z][A-Za-z0-9._]*$/
      ]
    end
    
    parameter :update_references do
      type :boolean
      required false
      description "Whether to update references in other files"
      default true
    end
    
    parameter :affected_files do
      type :list
      required false
      description "List of files that may contain references to update"
      default []
    end
    
    parameter :visibility do
      type :string
      required false
      description "Visibility of the function in the target module"
      default "preserve"
      constraints [
        enum: ["preserve", "public", "private"]
      ]
    end
    
    parameter :include_dependencies do
      type :boolean
      required false
      description "Whether to also move private functions that the target function depends on"
      default false
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 45_000
      async true
      retries 2
    end
    
    security do
      sandbox :strict
      capabilities [:llm_access, :code_analysis]
      rate_limit [max_requests: 50, window_seconds: 60]
    end
  end
  
  @doc """
  Executes the function move operation.
  """
  def execute(params, context) do
    with {:ok, source_analysis} <- analyze_source_module(params),
         {:ok, target_analysis} <- analyze_target_module(params),
         {:ok, function_info} <- find_function_to_move(source_analysis, params),
         {:ok, dependencies} <- analyze_dependencies(function_info, source_analysis, params),
         {:ok, move_plan} <- create_move_plan(function_info, dependencies, params),
         {:ok, updated_source} <- remove_from_source(params.source_code, move_plan, context),
         {:ok, updated_target} <- add_to_target(params.target_code, move_plan, context),
         {:ok, reference_updates} <- update_references_if_needed(params, move_plan, context) do
      
      {:ok, %{
        updated_source: updated_source,
        updated_target: updated_target,
        moved_function: %{
          name: function_info.name,
          arity: function_info.arity,
          type: function_info.type
        },
        dependencies_moved: Enum.map(dependencies, &{&1.name, &1.arity}),
        reference_updates: reference_updates,
        warnings: generate_warnings(move_plan, source_analysis, target_analysis)
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp analyze_source_module(params) do
    case parse_module(params.source_code) do
      {:ok, ast} ->
        analysis = %{
          ast: ast,
          module_name: params.source_module,
          functions: extract_functions(ast),
          imports: extract_imports(ast),
          aliases: extract_aliases(ast),
          module_attributes: extract_module_attributes(ast)
        }
        {:ok, analysis}
      error -> error
    end
  end
  
  defp analyze_target_module(params) do
    case parse_module(params.target_code) do
      {:ok, ast} ->
        analysis = %{
          ast: ast,
          module_name: params.target_module,
          functions: extract_functions(ast),
          imports: extract_imports(ast),
          aliases: extract_aliases(ast),
          existing_functions: extract_function_names(ast)
        }
        {:ok, analysis}
      error -> error
    end
  end
  
  defp parse_module(code) do
    case Code.string_to_quoted(code, columns: true, token_metadata: true) do
      {:ok, ast} -> {:ok, ast}
      {:error, {line, error, _}} -> 
        {:error, "Parse error on line #{line}: #{error}"}
    end
  end
  
  defp find_function_to_move(source_analysis, params) do
    matching_functions = source_analysis.functions
    |> Enum.filter(fn func ->
      func.name == String.to_atom(params.function_name) &&
      (is_nil(params.function_arity) || func.arity == params.function_arity)
    end)
    
    case matching_functions do
      [] -> 
        {:error, "Function #{params.function_name} not found in source module"}
      [function] -> 
        {:ok, function}
      multiple ->
        if params.function_arity do
          case Enum.find(multiple, &(&1.arity == params.function_arity)) do
            nil -> {:error, "Function #{params.function_name}/#{params.function_arity} not found"}
            function -> {:ok, function}
          end
        else
          {:error, "Multiple functions named #{params.function_name} found. Please specify arity."}
        end
    end
  end
  
  defp analyze_dependencies(function_info, source_analysis, params) do
    if params.include_dependencies do
      # Find all private functions that this function calls
      called_functions = extract_called_functions(function_info.ast)
      
      dependencies = source_analysis.functions
      |> Enum.filter(fn func ->
        func.type == :defp && 
        Enum.any?(called_functions, fn {name, arity} ->
          func.name == name && func.arity == arity
        end)
      end)
      
      {:ok, dependencies}
    else
      {:ok, []}
    end
  end
  
  defp create_move_plan(function_info, dependencies, params) do
    plan = %{
      main_function: function_info,
      dependencies: dependencies,
      source_module: params.source_module,
      target_module: params.target_module,
      visibility: determine_visibility(function_info, params),
      imports_needed: [],  # Would analyze what imports the function needs
      aliases_needed: []   # Would analyze what aliases the function needs
    }
    
    {:ok, plan}
  end
  
  defp determine_visibility(function_info, params) do
    case params.visibility do
      "preserve" -> function_info.type
      "public" -> :def
      "private" -> :defp
    end
  end
  
  defp remove_from_source(source_code, move_plan, context) do
    prompt = build_removal_prompt(source_code, move_plan)
    
    case Service.generate(%{
      prompt: prompt,
      max_tokens: 4000,
      temperature: 0.2,
      model: context[:llm_model] || "gpt-4"
    }) do
      {:ok, response} -> extract_code_from_response(response)
      error -> error
    end
  end
  
  defp build_removal_prompt(source_code, move_plan) do
    functions_to_remove = [move_plan.main_function | move_plan.dependencies]
    |> Enum.map(fn f -> "#{f.name}/#{f.arity}" end)
    |> Enum.join(", ")
    
    """
    Remove the following functions from this Elixir module: #{functions_to_remove}
    
    Source code:
    ```elixir
    #{source_code}
    ```
    
    Requirements:
    1. Remove the complete function definition(s) including any @doc, @spec, or other attributes
    2. Keep all other functions and module structure intact
    3. Remove any module attributes that are only used by the removed function(s)
    4. Clean up any unused imports or aliases if they were only used by removed functions
    5. Maintain proper formatting and indentation
    
    Return the updated module code.
    """
  end
  
  defp add_to_target(target_code, move_plan, context) do
    prompt = build_addition_prompt(target_code, move_plan)
    
    case Service.generate(%{
      prompt: prompt,
      max_tokens: 4000,
      temperature: 0.2,
      model: context[:llm_model] || "gpt-4"
    }) do
      {:ok, response} -> extract_code_from_response(response)
      error -> error
    end
  end
  
  defp build_addition_prompt(target_code, move_plan) do
    """
    Add the following function to this Elixir module.
    
    Target module code:
    ```elixir
    #{target_code}
    ```
    
    Function to add:
    - Name: #{move_plan.main_function.name}
    - Arity: #{move_plan.main_function.arity}
    - Visibility: #{move_plan.visibility}
    
    The function should be moved from module #{move_plan.source_module}.
    
    Requirements:
    1. Add the function with proper visibility (#{move_plan.visibility})
    2. Place it in a logical location within the module
    3. Add any necessary imports or aliases that the function requires
    4. Include any dependent private functions if needed
    5. Maintain consistent code style with the rest of the module
    6. Ensure no naming conflicts with existing functions
    
    Return the updated module code with the function properly integrated.
    """
  end
  
  defp update_references_if_needed(params, move_plan, context) do
    if params.update_references && length(params.affected_files) > 0 do
      updates = Enum.map(params.affected_files, fn file_info ->
        case update_file_references(file_info, move_plan, context) do
          {:ok, updated} -> %{file: file_info["path"], status: :updated, content: updated}
          {:error, reason} -> %{file: file_info["path"], status: :error, reason: reason}
        end
      end)
      
      {:ok, updates}
    else
      {:ok, []}
    end
  end
  
  defp update_file_references(file_info, move_plan, context) do
    prompt = """
    Update references to a moved function in this file.
    
    File content:
    ```elixir
    #{file_info["content"]}
    ```
    
    Function moved:
    - Function: #{move_plan.main_function.name}/#{move_plan.main_function.arity}
    - From: #{move_plan.source_module}
    - To: #{move_plan.target_module}
    
    Update all references to use the new module location.
    This includes:
    1. Direct calls with module prefix
    2. Imports that need to be updated
    3. Aliases that might need adjustment
    
    Return the updated file content.
    """
    
    case Service.generate(%{
      prompt: prompt,
      max_tokens: 4000,
      temperature: 0.2,
      model: context[:llm_model] || "gpt-4"
    }) do
      {:ok, response} -> extract_code_from_response(response)
      error -> error
    end
  end
  
  defp extract_code_from_response(response) do
    case Regex.run(~r/```(?:elixir|ex)?\n(.*?)\n```/s, response, capture: :all_but_first) do
      [code] -> {:ok, String.trim(code)}
      _ -> 
        # Try without code fence
        code = response
        |> String.split("\n")
        |> Enum.drop_while(&(!String.contains?(&1, ["defmodule"])))
        |> Enum.join("\n")
        |> String.trim()
        
        if code == "" do
          {:error, "No valid code found in response"}
        else
          {:ok, code}
        end
    end
  end
  
  defp generate_warnings(move_plan, source_analysis, target_analysis) do
    warnings = []
    
    # Check for naming conflicts
    existing_names = target_analysis.existing_functions
    |> Enum.map(fn {name, arity} -> {name, arity} end)
    |> MapSet.new()
    
    warnings = if MapSet.member?(existing_names, {move_plan.main_function.name, move_plan.main_function.arity}) do
      ["Target module already has a function #{move_plan.main_function.name}/#{move_plan.main_function.arity}" | warnings]
    else
      warnings
    end
    
    # Check for circular dependencies
    warnings = if imports_module?(target_analysis, source_analysis.module_name) do
      ["Moving this function may create circular dependencies" | warnings]
    else
      warnings
    end
    
    warnings
  end
  
  defp imports_module?(analysis, module_name) do
    Enum.any?(analysis.imports, fn imp -> 
      imp.module == module_name
    end)
  end
  
  # AST extraction helpers
  
  defp extract_functions(ast) do
    {_, functions} = Macro.postwalk(ast, [], fn node, acc ->
      case node do
        {:def, meta, [{name, _, args} | _rest]} when is_atom(name) ->
          func_info = %{
            name: name,
            arity: length(args || []),
            type: :def,
            line: Keyword.get(meta, :line, 0),
            ast: node
          }
          {node, [func_info | acc]}
          
        {:defp, meta, [{name, _, args} | _rest]} when is_atom(name) ->
          func_info = %{
            name: name,
            arity: length(args || []),
            type: :defp,
            line: Keyword.get(meta, :line, 0),
            ast: node
          }
          {node, [func_info | acc]}
          
        _ -> {node, acc}
      end
    end)
    
    Enum.reverse(functions)
  end
  
  defp extract_function_names(ast) do
    extract_functions(ast)
    |> Enum.map(fn f -> {f.name, f.arity} end)
  end
  
  defp extract_imports(ast) do
    {_, imports} = Macro.postwalk(ast, [], fn node, acc ->
      case node do
        {:import, _, [{:__aliases__, _, parts} | _]} ->
          {node, [%{module: Module.concat(parts)} | acc]}
        _ -> {node, acc}
      end
    end)
    
    Enum.reverse(imports)
  end
  
  defp extract_aliases(ast) do
    {_, aliases} = Macro.postwalk(ast, [], fn node, acc ->
      case node do
        {:alias, _, [{:__aliases__, _, parts} | _]} ->
          {node, [%{module: Module.concat(parts)} | acc]}
        _ -> {node, acc}
      end
    end)
    
    Enum.reverse(aliases)
  end
  
  defp extract_module_attributes(ast) do
    {_, attrs} = Macro.postwalk(ast, [], fn node, acc ->
      case node do
        {:@, _, [{name, _, _}]} when is_atom(name) ->
          {node, [name | acc]}
        _ -> {node, acc}
      end
    end)
    
    Enum.reverse(attrs) |> Enum.uniq()
  end
  
  defp extract_called_functions(ast) do
    {_, calls} = Macro.postwalk(ast, [], fn node, acc ->
      case node do
        {name, _, args} when is_atom(name) and is_list(args) ->
          {node, [{name, length(args)} | acc]}
        _ -> {node, acc}
      end
    end)
    
    Enum.reverse(calls) |> Enum.uniq()
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
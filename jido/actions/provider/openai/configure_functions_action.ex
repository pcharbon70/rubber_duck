defmodule RubberDuck.Jido.Actions.Provider.OpenAI.ConfigureFunctionsAction do
  @moduledoc """
  Action for configuring OpenAI function calling capabilities.

  This action handles the setup and management of OpenAI's function calling features,
  including function definitions, parameter schemas, execution policies, and 
  result handling for tool-augmented conversations.

  ## Parameters

  - `operation` - Function operation to perform (required: :configure, :update, :validate, :analyze)
  - `functions` - List of function definitions to configure (required for :configure)
  - `function_choice` - Function calling strategy (default: :auto)
  - `parallel_calls` - Whether to allow parallel function calls (default: true)
  - `validation_mode` - Schema validation strictness (default: :strict)
  - `execution_timeout` - Function execution timeout in ms (default: 30000)
  - `retry_policy` - Retry configuration for failed calls (default: %{})

  ## Returns

  - `{:ok, result}` - Function configuration completed successfully
  - `{:error, reason}` - Function configuration failed

  ## Example

      params = %{
        operation: :configure,
        functions: [
          %{
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: %{
              type: "object",
              properties: %{
                location: %{type: "string", description: "City name"},
                units: %{type: "string", enum: ["celsius", "fahrenheit"]}
              },
              required: ["location"]
            }
          }
        ],
        function_choice: :auto,
        parallel_calls: true
      }

      {:ok, result} = ConfigureFunctionsAction.run(params, context)
  """

  use Jido.Action,
    name: "configure_functions",
    description: "Configure OpenAI function calling capabilities",
    schema: [
      operation: [
        type: :atom,
        required: true,
        doc: "Function operation (configure, update, validate, analyze, test)"
      ],
      functions: [
        type: :list,
        default: [],
        doc: "List of function definitions to configure"
      ],
      function_choice: [
        type: {:union, [:atom, :string]},
        default: :auto,
        doc: "Function calling strategy (auto, none, or specific function name)"
      ],
      parallel_calls: [
        type: :boolean,
        default: true,
        doc: "Whether to allow parallel function calls"
      ],
      validation_mode: [
        type: :atom,
        default: :strict,
        doc: "Schema validation strictness (strict, permissive, none)"
      ],
      execution_timeout: [
        type: :integer,
        default: 30000,
        doc: "Function execution timeout in milliseconds"
      ],
      retry_policy: [
        type: :map,
        default: %{max_retries: 3, backoff_ms: 1000},
        doc: "Retry configuration for failed function calls"
      ],
      error_handling: [
        type: :atom,
        default: :continue,
        doc: "How to handle function errors (continue, halt, retry)"
      ],
      result_format: [
        type: :atom,
        default: :structured,
        doc: "Format for function results (structured, raw, json)"
      ]
    ]

  require Logger

  @valid_function_choices [:auto, :none]
  @valid_validation_modes [:strict, :permissive, :none]
  @valid_error_handling [:continue, :halt, :retry]
  @valid_result_formats [:structured, :raw, :json]
  @max_functions_per_request 128
  @max_function_name_length 64
  @max_description_length 1024

  @impl true
  def run(params, context) do
    Logger.info("Configuring OpenAI functions: #{params.operation}")

    with {:ok, validated_params} <- validate_function_parameters(params),
         {:ok, result} <- execute_function_operation(validated_params, context) do
      
      emit_functions_configured_signal(params.operation, result)
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Function configuration failed: #{inspect(reason)}")
        emit_functions_error_signal(params.operation, reason)
        {:error, reason}
    end
  end

  # Parameter validation

  defp validate_function_parameters(params) do
    with {:ok, _} <- validate_operation(params.operation),
         {:ok, _} <- validate_function_choice(params.function_choice),
         {:ok, _} <- validate_validation_mode(params.validation_mode),
         {:ok, _} <- validate_error_handling(params.error_handling),
         {:ok, _} <- validate_result_format(params.result_format),
         {:ok, _} <- validate_functions_list(params.functions, params.operation),
         {:ok, _} <- validate_retry_policy(params.retry_policy) do
      
      {:ok, params}
    else
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  defp validate_operation(operation) do
    valid_operations = [:configure, :update, :validate, :analyze, :test, :remove]
    if operation in valid_operations do
      {:ok, operation}
    else
      {:error, {:invalid_operation, operation, valid_operations}}
    end
  end

  defp validate_function_choice(choice) when choice in @valid_function_choices, do: {:ok, choice}
  defp validate_function_choice(choice) when is_binary(choice) do
    # Specific function name
    if String.length(choice) > 0 and String.length(choice) <= @max_function_name_length do
      {:ok, choice}
    else
      {:error, {:invalid_function_name, choice}}
    end
  end
  defp validate_function_choice(choice), do: {:error, {:invalid_function_choice, choice}}

  defp validate_validation_mode(mode) do
    if mode in @valid_validation_modes do
      {:ok, mode}
    else
      {:error, {:invalid_validation_mode, mode, @valid_validation_modes}}
    end
  end

  defp validate_error_handling(handling) do
    if handling in @valid_error_handling do
      {:ok, handling}
    else
      {:error, {:invalid_error_handling, handling, @valid_error_handling}}
    end
  end

  defp validate_result_format(format) do
    if format in @valid_result_formats do
      {:ok, format}
    else
      {:error, {:invalid_result_format, format, @valid_result_formats}}
    end
  end

  defp validate_functions_list(functions, operation) when operation in [:configure, :update] do
    cond do
      not is_list(functions) ->
        {:error, :functions_must_be_list}
      
      length(functions) == 0 ->
        {:error, :functions_list_empty}
      
      length(functions) > @max_functions_per_request ->
        {:error, {:too_many_functions, length(functions), @max_functions_per_request}}
      
      true ->
        validate_individual_functions(functions)
    end
  end
  defp validate_functions_list(_functions, _operation), do: {:ok, :not_required}

  defp validate_individual_functions(functions) do
    invalid_functions = Enum.with_index(functions)
    |> Enum.filter(fn {function, _index} ->
      not valid_function_definition?(function)
    end)
    
    if Enum.empty?(invalid_functions) do
      {:ok, :valid}
    else
      invalid_indices = Enum.map(invalid_functions, &elem(&1, 1))
      {:error, {:invalid_function_definitions, invalid_indices}}
    end
  end

  defp valid_function_definition?(function) do
    required_fields = [:name, :description]
    
    has_required_fields = Enum.all?(required_fields, fn field ->
      Map.has_key?(function, field) and not is_nil(function[field])
    end)
    
    valid_name = is_binary(function[:name]) and 
                 String.length(function[:name]) > 0 and
                 String.length(function[:name]) <= @max_function_name_length and
                 String.match?(function[:name], ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)
    
    valid_description = is_binary(function[:description]) and
                       String.length(function[:description]) > 0 and
                       String.length(function[:description]) <= @max_description_length
    
    valid_parameters = case function[:parameters] do
      nil -> true
      params -> valid_parameters_schema?(params)
    end
    
    has_required_fields and valid_name and valid_description and valid_parameters
  end

  defp valid_parameters_schema?(params) do
    # Validate JSON Schema format for parameters
    is_map(params) and 
    Map.has_key?(params, :type) and
    params[:type] == "object" and
    Map.has_key?(params, :properties) and
    is_map(params[:properties])
  end

  defp validate_retry_policy(retry_policy) when is_map(retry_policy) do
    max_retries = retry_policy[:max_retries] || 3
    backoff_ms = retry_policy[:backoff_ms] || 1000
    
    cond do
      not is_integer(max_retries) or max_retries < 0 or max_retries > 10 ->
        {:error, {:invalid_max_retries, max_retries}}
      
      not is_integer(backoff_ms) or backoff_ms < 0 or backoff_ms > 30000 ->
        {:error, {:invalid_backoff_ms, backoff_ms}}
      
      true ->
        {:ok, retry_policy}
    end
  end
  defp validate_retry_policy(_), do: {:error, :retry_policy_must_be_map}

  # Operation execution

  defp execute_function_operation(params, context) do
    case params.operation do
      :configure -> configure_functions(params, context)
      :update -> update_functions(params, context)
      :validate -> validate_functions(params, context)
      :analyze -> analyze_functions(params, context)
      :test -> test_functions(params, context)
      :remove -> remove_functions(params, context)
    end
  end

  # Function configuration

  defp configure_functions(params, context) do
    with {:ok, processed_functions} <- process_function_definitions(params.functions),
         {:ok, config} <- build_function_configuration(params, processed_functions),
         {:ok, _} <- store_function_configuration(config, context) do
      
      result = %{
        operation: :configure,
        functions_configured: length(processed_functions),
        configuration: config,
        function_names: Enum.map(processed_functions, & &1.name),
        capabilities: analyze_function_capabilities(processed_functions),
        validation_results: validate_function_compatibility(processed_functions),
        metadata: %{
          configured_at: DateTime.utc_now(),
          validation_mode: params.validation_mode,
          parallel_calls_enabled: params.parallel_calls
        }
      }
      
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_function_definitions(functions) do
    processed_functions = Enum.map(functions, fn function ->
      %{
        name: function.name,
        description: function.description,
        parameters: process_parameters_schema(function[:parameters]),
        metadata: %{
          parameter_count: count_parameters(function[:parameters]),
          complexity_score: calculate_complexity_score(function),
          estimated_execution_time: estimate_execution_time(function)
        }
      }
    end)
    
    {:ok, processed_functions}
  end

  defp process_parameters_schema(nil), do: %{type: "object", properties: %{}}
  defp process_parameters_schema(params) when is_map(params) do
    # Ensure schema has required fields and normalize structure
    base_schema = %{
      type: params[:type] || "object",
      properties: params[:properties] || %{},
      required: params[:required] || []
    }
    
    # Add additional schema validations
    Map.merge(base_schema, %{
      additionalProperties: params[:additionalProperties] || false,
      description: params[:description] || "Function parameters"
    })
  end

  defp count_parameters(nil), do: 0
  defp count_parameters(params) when is_map(params) do
    case params[:properties] do
      properties when is_map(properties) -> map_size(properties)
      _ -> 0
    end
  end

  defp calculate_complexity_score(function) do
    base_score = 1.0
    
    # Increase score based on parameter count
    param_count = count_parameters(function[:parameters])
    param_score = param_count * 0.1
    
    # Increase score based on description complexity
    description_score = String.length(function[:description] || "") / 100.0
    
    # Check for nested objects or arrays in parameters
    nesting_score = calculate_nesting_complexity(function[:parameters])
    
    base_score + param_score + description_score + nesting_score
  end

  defp calculate_nesting_complexity(nil), do: 0.0
  defp calculate_nesting_complexity(params) when is_map(params) do
    properties = params[:properties] || %{}
    
    Enum.reduce(properties, 0.0, fn {_key, prop_schema}, acc ->
      case prop_schema do
        %{type: "object"} -> acc + 0.5
        %{type: "array"} -> acc + 0.3
        _ -> acc
      end
    end)
  end

  defp estimate_execution_time(function) do
    # Simple heuristic based on function complexity
    base_time = 1000  # 1 second base
    complexity = calculate_complexity_score(function)
    round(base_time * complexity)
  end

  defp build_function_configuration(params, processed_functions) do
    config = %{
      functions: processed_functions,
      function_choice: params.function_choice,
      parallel_calls: params.parallel_calls,
      validation_mode: params.validation_mode,
      execution_timeout: params.execution_timeout,
      retry_policy: params.retry_policy,
      error_handling: params.error_handling,
      result_format: params.result_format,
      configuration_metadata: %{
        total_functions: length(processed_functions),
        average_complexity: calculate_average_complexity(processed_functions),
        supports_parallel: params.parallel_calls,
        created_at: DateTime.utc_now()
      }
    }
    
    {:ok, config}
  end

  defp calculate_average_complexity(functions) do
    if length(functions) == 0 do
      0.0
    else
      total_complexity = Enum.reduce(functions, 0.0, fn func, acc ->
        acc + func.metadata.complexity_score
      end)
      total_complexity / length(functions)
    end
  end

  defp store_function_configuration(config, _context) do
    # TODO: Store in actual agent state
    Logger.debug("Storing function configuration: #{length(config.functions)} functions")
    {:ok, :stored}
  end

  defp analyze_function_capabilities(functions) do
    %{
      total_functions: length(functions),
      parameter_functions: Enum.count(functions, fn f -> 
        count_parameters(f.parameters) > 0 
      end),
      simple_functions: Enum.count(functions, fn f -> 
        f.metadata.complexity_score <= 2.0 
      end),
      complex_functions: Enum.count(functions, fn f -> 
        f.metadata.complexity_score > 2.0 
      end),
      estimated_total_execution_time: Enum.reduce(functions, 0, fn f, acc ->
        acc + f.metadata.estimated_execution_time
      end),
      function_categories: categorize_functions(functions)
    }
  end

  defp categorize_functions(functions) do
    categories = Enum.reduce(functions, %{}, fn function, acc ->
      category = categorize_single_function(function)
      Map.update(acc, category, 1, &(&1 + 1))
    end)
    
    categories
  end

  defp categorize_single_function(function) do
    name = String.downcase(function.name)
    description = String.downcase(function.description)
    
    cond do
      String.contains?(name <> description, ["get", "fetch", "retrieve", "read"]) -> :data_retrieval
      String.contains?(name <> description, ["create", "add", "insert", "post"]) -> :data_creation
      String.contains?(name <> description, ["update", "modify", "edit", "patch"]) -> :data_modification
      String.contains?(name <> description, ["delete", "remove", "destroy"]) -> :data_deletion
      String.contains?(name <> description, ["calculate", "compute", "process"]) -> :computation
      String.contains?(name <> description, ["send", "notify", "alert", "message"]) -> :communication
      String.contains?(name <> description, ["search", "find", "query", "filter"]) -> :search
      true -> :utility
    end
  end

  defp validate_function_compatibility(functions) do
    warnings = []
    errors = []
    
    # Check for naming conflicts
    function_names = Enum.map(functions, & &1.name)
    duplicate_names = function_names -- Enum.uniq(function_names)
    
    errors = if length(duplicate_names) > 0 do
      [{:duplicate_function_names, duplicate_names} | errors]
    else
      errors
    end
    
    # Check for overly complex functions
    complex_functions = Enum.filter(functions, fn f ->
      f.metadata.complexity_score > 5.0
    end)
    
    warnings = if length(complex_functions) > 0 do
      complex_names = Enum.map(complex_functions, & &1.name)
      [{:high_complexity_functions, complex_names} | warnings]
    else
      warnings
    end
    
    # Check for functions with many parameters
    parameter_heavy = Enum.filter(functions, fn f ->
      count_parameters(f.parameters) > 10
    end)
    
    warnings = if length(parameter_heavy) > 0 do
      heavy_names = Enum.map(parameter_heavy, & &1.name)
      [{:many_parameters_functions, heavy_names} | warnings]
    else
      warnings
    end
    
    %{
      valid: length(errors) == 0,
      errors: errors,
      warnings: warnings,
      compatibility_score: calculate_compatibility_score(errors, warnings)
    }
  end

  defp calculate_compatibility_score(errors, warnings) do
    base_score = 100.0
    error_penalty = length(errors) * 20.0
    warning_penalty = length(warnings) * 5.0
    
    max(0.0, base_score - error_penalty - warning_penalty)
  end

  # Function updates

  defp update_functions(params, context) do
    case get_current_function_config(context) do
      {:ok, current_config} ->
        updated_functions = merge_function_updates(current_config.functions, params.functions)
        
        with {:ok, processed_functions} <- process_function_definitions(updated_functions),
             {:ok, updated_config} <- build_function_configuration(params, processed_functions),
             {:ok, _} <- store_function_configuration(updated_config, context) do
          
          result = %{
            operation: :update,
            previous_function_count: length(current_config.functions),
            updated_function_count: length(processed_functions),
            changes: calculate_function_changes(current_config.functions, processed_functions),
            updated_configuration: updated_config
          }
          
          {:ok, result}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_current_function_config(_context) do
    # TODO: Get actual configuration from agent state
    {:ok, %{
      functions: [],
      function_choice: :auto,
      parallel_calls: true
    }}
  end

  defp merge_function_updates(current_functions, new_functions) do
    # Merge by function name, new functions override existing ones
    current_by_name = Enum.reduce(current_functions, %{}, fn func, acc ->
      Map.put(acc, func.name, func)
    end)
    
    updated_by_name = Enum.reduce(new_functions, current_by_name, fn func, acc ->
      Map.put(acc, func.name, func)
    end)
    
    Map.values(updated_by_name)
  end

  defp calculate_function_changes(old_functions, new_functions) do
    old_names = MapSet.new(Enum.map(old_functions, & &1.name))
    new_names = MapSet.new(Enum.map(new_functions, & &1.name))
    
    %{
      added: MapSet.difference(new_names, old_names) |> MapSet.to_list(),
      removed: MapSet.difference(old_names, new_names) |> MapSet.to_list(),
      modified: MapSet.intersection(old_names, new_names) |> MapSet.to_list(),
      total_changes: MapSet.size(MapSet.union(
        MapSet.difference(new_names, old_names),
        MapSet.difference(old_names, new_names)
      ))
    }
  end

  # Function validation

  defp validate_functions(params, _context) do
    functions = params.functions
    
    validation_results = Enum.map(functions, fn function ->
      %{
        function_name: function.name,
        valid: valid_function_definition?(function),
        schema_validation: validate_function_schema(function),
        name_validation: validate_function_name(function.name),
        description_validation: validate_function_description(function.description),
        parameters_validation: validate_function_parameters_detailed(function[:parameters])
      }
    end)
    
    overall_valid = Enum.all?(validation_results, & &1.valid)
    
    result = %{
      operation: :validate,
      overall_valid: overall_valid,
      functions_validated: length(functions),
      validation_results: validation_results,
      validation_summary: create_validation_summary(validation_results)
    }
    
    {:ok, result}
  end

  defp validate_function_schema(function) do
    case function[:parameters] do
      nil -> %{valid: true, message: "No parameters defined"}
      params -> 
        cond do
          not is_map(params) ->
            %{valid: false, message: "Parameters must be a map"}
          
          not Map.has_key?(params, :type) ->
            %{valid: false, message: "Parameters must have a type field"}
          
          params[:type] != "object" ->
            %{valid: false, message: "Parameters type must be 'object'"}
          
          not Map.has_key?(params, :properties) ->
            %{valid: false, message: "Parameters must have properties field"}
          
          not is_map(params[:properties]) ->
            %{valid: false, message: "Properties must be a map"}
          
          true ->
            %{valid: true, message: "Schema is valid"}
        end
    end
  end

  defp validate_function_name(name) do
    cond do
      not is_binary(name) ->
        %{valid: false, message: "Name must be a string"}
      
      String.length(name) == 0 ->
        %{valid: false, message: "Name cannot be empty"}
      
      String.length(name) > @max_function_name_length ->
        %{valid: false, message: "Name too long (max #{@max_function_name_length} chars)"}
      
      not String.match?(name, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/) ->
        %{valid: false, message: "Name must start with letter/underscore and contain only alphanumeric/underscore"}
      
      true ->
        %{valid: true, message: "Name is valid"}
    end
  end

  defp validate_function_description(description) do
    cond do
      not is_binary(description) ->
        %{valid: false, message: "Description must be a string"}
      
      String.length(description) == 0 ->
        %{valid: false, message: "Description cannot be empty"}
      
      String.length(description) > @max_description_length ->
        %{valid: false, message: "Description too long (max #{@max_description_length} chars)"}
      
      true ->
        %{valid: true, message: "Description is valid"}
    end
  end

  defp validate_function_parameters_detailed(nil) do
    %{valid: true, message: "No parameters to validate", parameter_count: 0}
  end
  defp validate_function_parameters_detailed(params) when is_map(params) do
    properties = params[:properties] || %{}
    required = params[:required] || []
    
    # Validate each property
    property_validations = Enum.map(properties, fn {prop_name, prop_schema} ->
      validate_property_schema(prop_name, prop_schema)
    end)
    
    # Validate required fields exist
    missing_required = required -- Map.keys(properties)
    
    all_valid = Enum.all?(property_validations, & &1.valid) and length(missing_required) == 0
    
    %{
      valid: all_valid,
      message: if(all_valid, do: "Parameters are valid", else: "Parameter validation failed"),
      parameter_count: map_size(properties),
      required_count: length(required),
      property_validations: property_validations,
      missing_required: missing_required
    }
  end
  defp validate_function_parameters_detailed(_) do
    %{valid: false, message: "Parameters must be a map", parameter_count: 0}
  end

  defp validate_property_schema(prop_name, prop_schema) do
    cond do
      not is_map(prop_schema) ->
        %{property: prop_name, valid: false, message: "Property schema must be a map"}
      
      not Map.has_key?(prop_schema, :type) ->
        %{property: prop_name, valid: false, message: "Property must have a type"}
      
      prop_schema[:type] not in ["string", "number", "integer", "boolean", "array", "object"] ->
        %{property: prop_name, valid: false, message: "Invalid property type"}
      
      true ->
        %{property: prop_name, valid: true, message: "Property is valid"}
    end
  end

  defp create_validation_summary(validation_results) do
    total = length(validation_results)
    valid_count = Enum.count(validation_results, & &1.valid)
    
    %{
      total_functions: total,
      valid_functions: valid_count,
      invalid_functions: total - valid_count,
      success_rate: if(total > 0, do: valid_count / total * 100, else: 0),
      common_issues: extract_common_issues(validation_results)
    }
  end

  defp extract_common_issues(validation_results) do
    invalid_results = Enum.filter(validation_results, fn result -> not result.valid end)
    
    # Extract common validation failure reasons
    issues = Enum.flat_map(invalid_results, fn result ->
      [
        result.name_validation,
        result.description_validation,
        result.schema_validation,
        result.parameters_validation
      ]
      |> Enum.filter(fn validation -> not validation.valid end)
      |> Enum.map(& &1.message)
    end)
    
    # Count frequency of each issue
    Enum.reduce(issues, %{}, fn issue, acc ->
      Map.update(acc, issue, 1, &(&1 + 1))
    end)
  end

  # Function analysis

  defp analyze_functions(params, context) do
    functions = params.functions
    
    analysis = %{
      complexity_analysis: analyze_complexity_distribution(functions),
      parameter_analysis: analyze_parameter_patterns(functions),
      naming_analysis: analyze_naming_patterns(functions),
      usage_predictions: predict_usage_patterns(functions),
      optimization_suggestions: generate_optimization_suggestions(functions),
      compatibility_matrix: analyze_function_compatibility_matrix(functions)
    }
    
    result = %{
      operation: :analyze,
      functions_analyzed: length(functions),
      analysis: analysis,
      summary: create_analysis_summary(analysis)
    }
    
    {:ok, result}
  end

  defp analyze_complexity_distribution(functions) do
    complexities = Enum.map(functions, fn f ->
      calculate_complexity_score(%{
        name: f.name,
        description: f.description,
        parameters: f[:parameters]
      })
    end)
    
    %{
      min_complexity: Enum.min(complexities, fn -> 0.0 end),
      max_complexity: Enum.max(complexities, fn -> 0.0 end),
      average_complexity: if(length(complexities) > 0, do: Enum.sum(complexities) / length(complexities), else: 0.0),
      complexity_distribution: %{
        simple: Enum.count(complexities, &(&1 <= 2.0)),
        moderate: Enum.count(complexities, &(&1 > 2.0 and &1 <= 4.0)),
        complex: Enum.count(complexities, &(&1 > 4.0))
      }
    }
  end

  defp analyze_parameter_patterns(functions) do
    parameter_counts = Enum.map(functions, fn f ->
      count_parameters(f[:parameters])
    end)
    
    %{
      functions_with_no_params: Enum.count(parameter_counts, &(&1 == 0)),
      functions_with_params: Enum.count(parameter_counts, &(&1 > 0)),
      average_parameter_count: if(length(parameter_counts) > 0, do: Enum.sum(parameter_counts) / length(parameter_counts), else: 0.0),
      max_parameters: Enum.max(parameter_counts, fn -> 0 end),
      parameter_distribution: Enum.frequencies(parameter_counts)
    }
  end

  defp analyze_naming_patterns(functions) do
    names = Enum.map(functions, & &1.name)
    
    # Analyze naming conventions
    snake_case = Enum.count(names, &String.contains?(&1, "_"))
    camel_case = Enum.count(names, &String.match?(&1, ~r/[a-z][A-Z]/))
    
    # Analyze verb patterns
    verb_patterns = %{
      get: Enum.count(names, &String.starts_with?(String.downcase(&1), "get")),
      set: Enum.count(names, &String.starts_with?(String.downcase(&1), "set")),
      create: Enum.count(names, &String.starts_with?(String.downcase(&1), "create")),
      update: Enum.count(names, &String.starts_with?(String.downcase(&1), "update")),
      delete: Enum.count(names, &String.starts_with?(String.downcase(&1), "delete"))
    }
    
    %{
      total_functions: length(names),
      naming_conventions: %{
        snake_case: snake_case,
        camel_case: camel_case,
        mixed: length(names) - snake_case - camel_case
      },
      verb_patterns: verb_patterns,
      average_name_length: if(length(names) > 0, do: Enum.sum(Enum.map(names, &String.length/1)) / length(names), else: 0.0)
    }
  end

  defp predict_usage_patterns(functions) do
    # Simple heuristics for predicting which functions might be used more
    categories = categorize_functions(functions)
    
    usage_predictions = Enum.map(functions, fn function ->
      category = categorize_single_function(function)
      complexity = calculate_complexity_score(function)
      param_count = count_parameters(function[:parameters])
      
      # Simpler functions and data retrieval tend to be used more
      usage_score = case category do
        :data_retrieval -> 0.8
        :search -> 0.7
        :utility -> 0.6
        :computation -> 0.5
        :data_creation -> 0.4
        :data_modification -> 0.3
        :data_deletion -> 0.2
        :communication -> 0.5
      end
      
      # Adjust based on complexity and parameters
      adjusted_score = usage_score * (1.0 - (complexity - 1.0) * 0.1) * (1.0 - param_count * 0.05)
      
      %{
        function_name: function.name,
        category: category,
        predicted_usage_score: max(0.0, min(1.0, adjusted_score)),
        factors: %{
          category_base_score: usage_score,
          complexity_penalty: (complexity - 1.0) * 0.1,
          parameter_penalty: param_count * 0.05
        }
      }
    end)
    
    %{
      predictions: usage_predictions,
      high_usage_functions: Enum.filter(usage_predictions, &(&1.predicted_usage_score > 0.7))
      |> Enum.map(& &1.function_name),
      category_predictions: categories
    }
  end

  defp generate_optimization_suggestions(functions) do
    suggestions = []
    
    # Check for overly complex functions
    complex_functions = Enum.filter(functions, fn f ->
      calculate_complexity_score(f) > 4.0
    end)
    
    suggestions = if length(complex_functions) > 0 do
      complex_names = Enum.map(complex_functions, & &1.name)
      ["Consider simplifying complex functions: #{Enum.join(complex_names, ", ")}" | suggestions]
    else
      suggestions
    end
    
    # Check for functions with many parameters
    param_heavy = Enum.filter(functions, fn f ->
      count_parameters(f[:parameters]) > 8
    end)
    
    suggestions = if length(param_heavy) > 0 do
      heavy_names = Enum.map(param_heavy, & &1.name)
      ["Consider reducing parameters for: #{Enum.join(heavy_names, ", ")}" | suggestions]
    else
      suggestions
    end
    
    # Check naming consistency
    naming_analysis = analyze_naming_patterns(functions)
    mixed_naming = naming_analysis.naming_conventions.mixed
    
    suggestions = if mixed_naming > 0 do
      ["Consider standardizing function naming convention (snake_case vs camelCase)" | suggestions]
    else
      suggestions
    end
    
    Enum.reverse(suggestions)
  end

  defp analyze_function_compatibility_matrix(functions) do
    # Analyze which functions might work well together
    compatibility_pairs = for f1 <- functions, f2 <- functions, f1.name != f2.name do
      compatibility_score = calculate_pair_compatibility(f1, f2)
      %{
        function_1: f1.name,
        function_2: f2.name,
        compatibility_score: compatibility_score,
        can_run_parallel: compatibility_score > 0.5
      }
    end
    
    %{
      total_pairs: length(compatibility_pairs),
      compatible_pairs: Enum.count(compatibility_pairs, &(&1.compatibility_score > 0.5)),
      parallel_safe_pairs: Enum.count(compatibility_pairs, & &1.can_run_parallel),
      compatibility_matrix: compatibility_pairs
    }
  end

  defp calculate_pair_compatibility(f1, f2) do
    # Simple heuristic: functions in same category are more compatible
    cat1 = categorize_single_function(f1)
    cat2 = categorize_single_function(f2)
    
    base_score = if cat1 == cat2, do: 0.7, else: 0.3
    
    # Data modification functions might conflict with each other
    conflict_categories = [:data_modification, :data_deletion, :data_creation]
    
    if cat1 in conflict_categories and cat2 in conflict_categories and cat1 != cat2 do
      base_score * 0.5
    else
      base_score
    end
  end

  defp create_analysis_summary(analysis) do
    %{
      total_complexity_score: analysis.complexity_analysis.average_complexity,
      parameter_efficiency: analysis.parameter_analysis.average_parameter_count,
      naming_consistency: calculate_naming_consistency(analysis.naming_analysis),
      predicted_high_usage_count: length(analysis.usage_predictions.high_usage_functions),
      optimization_needed: length(analysis.optimization_suggestions) > 0,
      parallel_compatibility: analysis.compatibility_matrix.compatible_pairs / max(1, analysis.compatibility_matrix.total_pairs)
    }
  end

  defp calculate_naming_consistency(naming_analysis) do
    conventions = naming_analysis.naming_conventions
    total = conventions.snake_case + conventions.camel_case + conventions.mixed
    
    if total == 0 do
      1.0
    else
      # Consistency is higher when one convention dominates
      max_convention = max(conventions.snake_case, conventions.camel_case)
      max_convention / total
    end
  end

  # Function testing

  defp test_functions(params, _context) do
    functions = params.functions
    
    test_results = Enum.map(functions, fn function ->
      test_result = %{
        function_name: function.name,
        schema_test: test_function_schema(function),
        parameter_test: test_function_parameters(function),
        mock_execution_test: test_mock_execution(function),
        overall_test_result: true  # Will be calculated based on individual tests
      }
      
      # Calculate overall result
      overall_result = test_result.schema_test.passed and 
                      test_result.parameter_test.passed and 
                      test_result.mock_execution_test.passed
      
      %{test_result | overall_test_result: overall_result}
    end)
    
    overall_success = Enum.all?(test_results, & &1.overall_test_result)
    
    result = %{
      operation: :test,
      overall_success: overall_success,
      functions_tested: length(functions),
      passed_tests: Enum.count(test_results, & &1.overall_test_result),
      failed_tests: Enum.count(test_results, fn r -> not r.overall_test_result end),
      test_results: test_results,
      test_summary: create_test_summary(test_results)
    }
    
    {:ok, result}
  end

  defp test_function_schema(function) do
    # Test that the function schema is valid OpenAI format
    try do
      openai_format = %{
        name: function.name,
        description: function.description,
        parameters: function[:parameters] || %{type: "object", properties: %{}}
      }
      
      # Validate it would be accepted by OpenAI
      valid = valid_function_definition?(function) and 
              is_map(openai_format.parameters) and
              openai_format.parameters[:type] == "object"
      
      %{
        passed: valid,
        message: if(valid, do: "Schema is valid", else: "Schema validation failed"),
        openai_format: openai_format
      }
    rescue
      error ->
        %{
          passed: false,
          message: "Schema test failed: #{Exception.message(error)}",
          error: error
        }
    end
  end

  defp test_function_parameters(function) do
    parameters = function[:parameters]
    
    if is_nil(parameters) do
      %{passed: true, message: "No parameters to test"}
    else
      properties = parameters[:properties] || %{}
      required = parameters[:required] || []
      
      # Test each property type
      property_tests = Enum.map(properties, fn {prop_name, prop_schema} ->
        test_property_type(prop_name, prop_schema)
      end)
      
      all_passed = Enum.all?(property_tests, & &1.passed)
      
      %{
        passed: all_passed,
        message: if(all_passed, do: "All parameters valid", else: "Some parameter tests failed"),
        property_tests: property_tests,
        required_fields_test: %{
          required_count: length(required),
          all_required_defined: Enum.all?(required, &Map.has_key?(properties, &1))
        }
      }
    end
  end

  defp test_property_type(prop_name, prop_schema) do
    try do
      valid_type = prop_schema[:type] in ["string", "number", "integer", "boolean", "array", "object"]
      has_description = Map.has_key?(prop_schema, :description)
      
      %{
        property: prop_name,
        passed: valid_type,
        message: if(valid_type, do: "Property type valid", else: "Invalid property type"),
        has_description: has_description,
        type: prop_schema[:type]
      }
    rescue
      error ->
        %{
          property: prop_name,
          passed: false,
          message: "Property test failed: #{Exception.message(error)}",
          error: error
        }
    end
  end

  defp test_mock_execution(function) do
    # Create mock parameters and test function would execute properly
    try do
      mock_params = generate_mock_parameters(function[:parameters])
      
      # Simulate function execution
      execution_result = %{
        function_name: function.name,
        mock_parameters: mock_params,
        estimated_execution_time: estimate_execution_time(function),
        would_succeed: true
      }
      
      %{
        passed: true,
        message: "Mock execution successful",
        execution_result: execution_result
      }
    rescue
      error ->
        %{
          passed: false,
          message: "Mock execution failed: #{Exception.message(error)}",
          error: error
        }
    end
  end

  defp generate_mock_parameters(nil), do: %{}
  defp generate_mock_parameters(parameters) do
    properties = parameters[:properties] || %{}
    
    Enum.reduce(properties, %{}, fn {prop_name, prop_schema}, acc ->
      mock_value = case prop_schema[:type] do
        "string" -> "mock_string"
        "number" -> 42.0
        "integer" -> 42
        "boolean" -> true
        "array" -> []
        "object" -> %{}
        _ -> "unknown_type"
      end
      
      Map.put(acc, prop_name, mock_value)
    end)
  end

  defp create_test_summary(test_results) do
    total = length(test_results)
    passed = Enum.count(test_results, & &1.overall_test_result)
    
    %{
      total_functions: total,
      passed_functions: passed,
      failed_functions: total - passed,
      success_rate: if(total > 0, do: passed / total * 100, else: 0),
      common_failures: extract_common_test_failures(test_results)
    }
  end

  defp extract_common_test_failures(test_results) do
    failed_results = Enum.filter(test_results, fn result -> not result.overall_test_result end)
    
    failure_reasons = Enum.flat_map(failed_results, fn result ->
      reasons = []
      
      reasons = if not result.schema_test.passed do
        [result.schema_test.message | reasons]
      else
        reasons
      end
      
      reasons = if not result.parameter_test.passed do
        [result.parameter_test.message | reasons]
      else
        reasons
      end
      
      reasons = if not result.mock_execution_test.passed do
        [result.mock_execution_test.message | reasons]
      else
        reasons
      end
      
      reasons
    end)
    
    Enum.frequencies(failure_reasons)
  end

  # Function removal

  defp remove_functions(params, context) do
    function_names_to_remove = case params[:function_names] do
      names when is_list(names) -> names
      name when is_binary(name) -> [name]
      _ -> []
    end
    
    case get_current_function_config(context) do
      {:ok, current_config} ->
        remaining_functions = Enum.filter(current_config.functions, fn function ->
          function.name not in function_names_to_remove
        end)
        
        updated_config = %{current_config | functions: remaining_functions}
        
        case store_function_configuration(updated_config, context) do
          {:ok, _} ->
            result = %{
              operation: :remove,
              functions_removed: length(function_names_to_remove),
              remaining_functions: length(remaining_functions),
              removed_function_names: function_names_to_remove,
              updated_configuration: updated_config
            }
            
            {:ok, result}
            
          {:error, reason} ->
            {:error, reason}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Signal emission

  defp emit_functions_configured_signal(operation, result) do
    # TODO: Emit actual signal
    Logger.debug("Functions #{operation} completed: #{inspect(Map.keys(result))}")
  end

  defp emit_functions_error_signal(operation, reason) do
    # TODO: Emit actual signal
    Logger.debug("Functions #{operation} failed: #{inspect(reason)}")
  end
end
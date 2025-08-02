defmodule RubberDuck.Agents.Migration.Helpers do
  @moduledoc """
  Migration helper utilities for converting legacy agents to Jido compliance.
  
  This module provides utilities for:
  - Detecting legacy behavior patterns
  - Extracting actions from existing agent implementations
  - Generating signal mapping configurations
  - Validating Jido compliance
  - Analyzing agent structure and dependencies
  
  ## Usage
  
      # Detect legacy patterns in an agent
      {:ok, patterns} = Helpers.detect_legacy_patterns(AnalysisAgent)
      
      # Extract potential actions from agent module
      {:ok, actions} = Helpers.extract_actions(AnalysisAgent)
      
      # Generate signal mappings
      {:ok, mappings} = Helpers.generate_signal_mappings(AnalysisAgent)
      
      # Validate compliance
      {:ok, compliance} = Helpers.validate_compliance(AnalysisAgent)
  """
  
  require Logger
  
  @type legacy_pattern :: :behavior_usage | :direct_signal_handling | :genserver_callbacks | :missing_actions
  @type action_candidate :: %{
    name: String.t(),
    function: atom(),
    arity: integer(),
    description: String.t(),
    parameters: [atom()],
    return_type: atom()
  }
  @type signal_mapping :: %{
    signal_type: String.t(),
    action_module: String.t(),
    param_extractor: String.t()
  }
  @type compliance_result :: %{
    compliant: boolean(),
    issues: [String.t()],
    recommendations: [String.t()],
    score: float()
  }

  @doc """
  Detects legacy behavior patterns in an agent module.
  
  Returns a list of detected legacy patterns that need to be addressed
  during migration to Jido compliance.
  """
  @spec detect_legacy_patterns(module()) :: {:ok, [legacy_pattern()]} | {:error, term()}
  def detect_legacy_patterns(module) do
    patterns = []
    
    patterns = check_behavior_usage(module, patterns)
    patterns = check_direct_signal_handling(module, patterns)
    patterns = check_genserver_callbacks(module, patterns)
    patterns = check_missing_actions(module, patterns)
    
    {:ok, patterns}
  rescue
    error -> {:error, {:pattern_detection_failed, error}}
  end
  
  @doc """
  Extracts potential action candidates from an agent module.
  
  Analyzes the module's functions to identify business logic that 
  should be extracted into Jido Actions.
  """
  @spec extract_actions(module()) :: {:ok, [action_candidate()]} | {:error, term()}
  def extract_actions(module) do
    try do
      # Get module info
      functions = get_module_functions(module)
      
      # Filter for action candidates
      candidates = 
        functions
        |> Enum.filter(&is_action_candidate?/1)
        |> Enum.map(&create_action_candidate/1)
      
      {:ok, candidates}
    rescue
      error -> {:error, {:action_extraction_failed, error}}
    end
  end
  
  @doc """
  Generates signal mapping configurations for an agent.
  
  Analyzes signal handling patterns and suggests appropriate
  signal-to-action mappings for Jido compliance.
  """
  @spec generate_signal_mappings(module()) :: {:ok, [signal_mapping()]} | {:error, term()}
  def generate_signal_mappings(module) do
    try do
      # Analyze signal handlers
      signal_handlers = find_signal_handlers(module)
      
      # Generate mappings
      mappings = 
        signal_handlers
        |> Enum.map(&create_signal_mapping/1)
        |> Enum.reject(&is_nil/1)
      
      {:ok, mappings}
    rescue
      error -> {:error, {:signal_mapping_failed, error}}
    end
  end
  
  @doc """
  Validates Jido compliance for an agent module.
  
  Performs comprehensive analysis to determine compliance level
  and provides recommendations for improvement.
  """
  @spec validate_compliance(module()) :: {:ok, compliance_result()} | {:error, term()}
  def validate_compliance(module) do
    try do
      issues = []
      recommendations = []
      
      # Check base agent usage
      {issues, recommendations} = check_base_agent_usage(module, issues, recommendations)
      
      # Check action registration
      {issues, recommendations} = check_action_registration(module, issues, recommendations)
      
      # Check signal handling
      {issues, recommendations} = check_signal_handling(module, issues, recommendations)
      
      # Check state management
      {issues, recommendations} = check_state_management(module, issues, recommendations)
      
      # Calculate compliance score
      score = calculate_compliance_score(issues)
      
      result = %{
        compliant: score >= 0.8,
        issues: issues,
        recommendations: recommendations,
        score: score
      }
      
      {:ok, result}
    rescue
      error -> {:error, {:compliance_validation_failed, error}}
    end
  end
  
  @doc """
  Analyzes agent dependencies and relationships.
  
  Helps identify migration order and potential conflicts.
  """
  @spec analyze_dependencies(module()) :: {:ok, map()} | {:error, term()}
  def analyze_dependencies(module) do
    try do
      dependencies = %{
        imports: get_module_imports(module),
        aliases: get_module_aliases(module),
        agent_dependencies: find_agent_dependencies(module),
        action_dependencies: find_action_dependencies(module)
      }
      
      {:ok, dependencies}
    rescue
      error -> {:error, {:dependency_analysis_failed, error}}
    end
  end
  
  # Private helper functions
  
  defp check_behavior_usage(module, patterns) do
    if uses_legacy_behavior?(module) do
      [:behavior_usage | patterns]
    else
      patterns
    end
  end
  
  defp check_direct_signal_handling(module, patterns) do
    if has_direct_signal_handling?(module) do
      [:direct_signal_handling | patterns]
    else
      patterns
    end
  end
  
  defp check_genserver_callbacks(module, patterns) do
    if has_genserver_callbacks?(module) do
      [:genserver_callbacks | patterns]
    else
      patterns
    end
  end
  
  defp check_missing_actions(module, patterns) do
    if missing_action_architecture?(module) do
      [:missing_actions | patterns]
    else
      patterns
    end
  end
  
  defp uses_legacy_behavior?(module) do
    # Check if module uses RubberDuck.Agents.Behavior
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        module.module_info(:attributes)
        |> Keyword.get(:behaviour, [])
        |> Enum.any?(&(&1 == RubberDuck.Agents.Behavior))
      _ -> false
    end
  rescue
    _ -> false
  end
  
  defp has_direct_signal_handling?(module) do
    # Check for handle_signal/2 functions
    module.__info__(:functions)
    |> Enum.any?(fn {name, arity} -> name == :handle_signal and arity == 2 end)
  rescue
    _ -> false
  end
  
  defp has_genserver_callbacks?(module) do
    # Check for GenServer callback functions
    genserver_callbacks = [:handle_call, :handle_cast, :handle_info, :handle_continue]
    
    functions = module.__info__(:functions)
    
    Enum.any?(genserver_callbacks, fn callback ->
      Enum.any?(functions, fn {name, _arity} -> name == callback end)
    end)
  rescue
    _ -> false
  end
  
  defp missing_action_architecture?(module) do
    # Check if module has actions/0 function
    not function_exported?(module, :actions, 0)
  rescue
    _ -> true
  end
  
  defp get_module_functions(module) do
    module.__info__(:functions)
  rescue
    _ -> []
  end
  
  defp is_action_candidate?({name, arity}) do
    # Filter criteria for action candidates
    name_str = Atom.to_string(name)
    
    # Include public functions that look like business logic
    not String.starts_with?(name_str, "_") and
    arity > 0 and
    name not in [:init, :terminate, :handle_call, :handle_cast, :handle_info, :handle_continue] and
    not String.starts_with?(name_str, "handle_")
  end
  
  defp create_action_candidate({name, arity}) do
    %{
      name: action_name_from_function(name),
      function: name,
      arity: arity,
      description: generate_action_description(name),
      parameters: generate_parameter_names(arity),
      return_type: :tagged_tuple
    }
  end
  
  defp action_name_from_function(function_name) do
    function_name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.trim()
  end
  
  defp generate_action_description(function_name) do
    "Action extracted from #{function_name} function"
  end
  
  defp generate_parameter_names(arity) do
    1..arity
    |> Enum.map(fn i -> String.to_atom("param#{i}") end)
  end
  
  defp find_signal_handlers(module) do
    # Look for signal handling patterns in the module
    try do
      functions = module.__info__(:functions)
      
      Enum.filter(functions, fn {name, _arity} ->
        name_str = Atom.to_string(name)
        String.contains?(name_str, "signal") or String.contains?(name_str, "handle")
      end)
    rescue
      _ -> []
    end
  end
  
  defp create_signal_mapping({function_name, _arity}) do
    # Generate signal mapping based on function name
    signal_type = infer_signal_type(function_name)
    action_module = generate_action_module_name(function_name)
    
    if signal_type do
      %{
        signal_type: signal_type,
        action_module: action_module,
        param_extractor: "extract_params"
      }
    end
  end
  
  defp infer_signal_type(function_name) do
    case Atom.to_string(function_name) do
      "handle_" <> rest -> String.replace(rest, "_", ".")
      name -> String.replace(name, "_", ".")
    end
  end
  
  defp generate_action_module_name(function_name) do
    function_name
    |> Atom.to_string()
    |> String.replace("handle_", "")
    |> Macro.camelize()
    |> Kernel.<>("Action")
  end
  
  defp check_base_agent_usage(module, issues, recommendations) do
    if uses_base_agent?(module) do
      {issues, recommendations}
    else
      issue = "Module does not use RubberDuck.Agents.BaseAgent"
      recommendation = "Convert to use RubberDuck.Agents.BaseAgent foundation"
      {[issue | issues], [recommendation | recommendations]}
    end
  end
  
  defp check_action_registration(module, issues, recommendations) do
    if has_action_registration?(module) do
      {issues, recommendations}
    else
      issue = "Module missing action registration"
      recommendation = "Implement actions/0 function with proper action modules"
      {[issue | issues], [recommendation | recommendations]}
    end
  end
  
  defp check_signal_handling(module, issues, recommendations) do
    if has_proper_signal_handling?(module) do
      {issues, recommendations}
    else
      issue = "Module uses direct signal handling instead of action routing"
      recommendation = "Replace handle_signal/2 with signal_mappings/0"
      {[issue | issues], [recommendation | recommendations]}
    end
  end
  
  defp check_state_management(module, issues, recommendations) do
    if has_proper_state_management?(module) do
      {issues, recommendations}
    else
      issue = "Module uses legacy state management patterns"
      recommendation = "Use Jido state management with proper validation"
      {[issue | issues], [recommendation | recommendations]}
    end
  end
  
  defp uses_base_agent?(module) do
    # Check if module uses BaseAgent
    try do
      case Code.ensure_loaded(module) do
        {:module, ^module} ->
          # Check module attributes for BaseAgent usage
          behaviours = module.module_info(:attributes)
                      |> Keyword.get(:behaviour, [])
          
          Enum.any?(behaviours, &(&1 == RubberDuck.Agents.BaseAgent))
        _ -> false
      end
    rescue
      _ -> false
    end
  end
  
  defp has_action_registration?(module) do
    function_exported?(module, :actions, 0)
  end
  
  defp has_proper_signal_handling?(module) do
    function_exported?(module, :signal_mappings, 0) and
    not function_exported?(module, :handle_signal, 2)
  end
  
  defp has_proper_state_management?(module) do
    # Check for Jido state management patterns
    not has_genserver_callbacks?(module)
  end
  
  defp calculate_compliance_score(issues) do
    max_issues = 10.0
    issue_count = length(issues)
    
    max(0.0, (max_issues - issue_count) / max_issues)
  end
  
  defp get_module_imports(module) do
    # Get module imports (simplified)
    try do
      module.module_info(:compile)
      |> Keyword.get(:source, "")
      |> Path.basename()
    rescue
      _ -> []
    end
  end
  
  defp get_module_aliases(module) do
    # Get module aliases (simplified)
    try do
      module.module_info(:attributes)
      |> Keyword.get(:compile, [])
    rescue
      _ -> []
    end
  end
  
  defp find_agent_dependencies(_module) do
    # Find other agent dependencies (simplified)
    []
  end
  
  defp find_action_dependencies(_module) do
    # Find action dependencies (simplified)
    []
  end
end
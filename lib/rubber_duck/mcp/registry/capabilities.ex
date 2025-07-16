defmodule RubberDuck.MCP.Registry.Capabilities do
  @moduledoc """
  Manages capability definitions and matching for MCP tools.
  
  Capabilities represent what a tool can do, its requirements,
  and how it can be composed with other tools.
  """
  
  @type capability :: atom()
  @type capability_spec :: %{
    name: capability(),
    description: String.t(),
    input_types: [atom()],
    output_types: [atom()],
    composable_with: [capability()],
    requirements: [capability()]
  }
  
  # Predefined capability definitions
  @capabilities %{
    # Core capabilities
    text_processing: %{
      description: "Can process and transform text data",
      input_types: [:string, :text],
      output_types: [:string, :text],
      composable_with: [:text_analysis, :file_operations],
      requirements: []
    },
    
    text_analysis: %{
      description: "Can analyze text for patterns, sentiment, etc.",
      input_types: [:string, :text],
      output_types: [:map, :analysis_result],
      composable_with: [:text_processing, :data_visualization],
      requirements: []
    },
    
    code_analysis: %{
      description: "Can analyze source code structure and quality",
      input_types: [:string, :file_path, :ast],
      output_types: [:map, :analysis_result, :ast],
      composable_with: [:code_generation, :refactoring],
      requirements: []
    },
    
    code_generation: %{
      description: "Can generate source code",
      input_types: [:map, :specification],
      output_types: [:string, :code],
      composable_with: [:code_analysis, :file_operations],
      requirements: []
    },
    
    file_operations: %{
      description: "Can read, write, and manipulate files",
      input_types: [:string, :file_path],
      output_types: [:string, :binary, :file_info],
      composable_with: [:text_processing, :code_analysis],
      requirements: [:file_system_access]
    },
    
    workflow_execution: %{
      description: "Can execute predefined workflows",
      input_types: [:map, :workflow_spec],
      output_types: [:map, :workflow_result],
      composable_with: [:monitoring, :logging],
      requirements: [:workflow_engine]
    },
    
    streaming: %{
      description: "Supports streaming data processing",
      input_types: [:stream, :enumerable],
      output_types: [:stream, :enumerable],
      composable_with: [:text_processing, :data_transformation],
      requirements: []
    },
    
    async: %{
      description: "Supports asynchronous execution",
      input_types: [:any],
      output_types: [:task, :future],
      composable_with: [:monitoring, :cancellation],
      requirements: []
    },
    
    monitoring: %{
      description: "Can monitor and report on operations",
      input_types: [:any],
      output_types: [:metrics, :events],
      composable_with: [:logging, :alerting],
      requirements: []
    },
    
    data_transformation: %{
      description: "Can transform data between formats",
      input_types: [:any],
      output_types: [:any],
      composable_with: [:validation, :streaming],
      requirements: []
    },
    
    validation: %{
      description: "Can validate data against schemas or rules",
      input_types: [:any],
      output_types: [:validation_result],
      composable_with: [:data_transformation, :error_handling],
      requirements: []
    },
    
    conversation_management: %{
      description: "Can manage conversation state and context",
      input_types: [:map, :conversation_event],
      output_types: [:map, :conversation_state],
      composable_with: [:memory_storage, :context_analysis],
      requirements: []
    },
    
    memory_storage: %{
      description: "Can store and retrieve data persistently",
      input_types: [:any],
      output_types: [:any],
      composable_with: [:indexing, :search],
      requirements: [:storage_backend]
    },
    
    search: %{
      description: "Can search through data collections",
      input_types: [:string, :query],
      output_types: [:list, :search_results],
      composable_with: [:ranking, :filtering],
      requirements: []
    },
    
    llm_integration: %{
      description: "Can interact with language models",
      input_types: [:string, :prompt],
      output_types: [:string, :completion],
      composable_with: [:prompt_engineering, :response_parsing],
      requirements: [:llm_provider]
    }
  }
  
  @doc """
  Gets the definition of a capability.
  """
  def get_definition(capability) when is_atom(capability) do
    Map.get(@capabilities, capability)
  end
  
  @doc """
  Lists all defined capabilities.
  """
  def list_all do
    Map.keys(@capabilities)
  end
  
  @doc """
  Checks if a capability is defined.
  """
  def defined?(capability) when is_atom(capability) do
    Map.has_key?(@capabilities, capability)
  end
  
  @doc """
  Validates a list of capabilities.
  """
  def validate_capabilities(capabilities) when is_list(capabilities) do
    invalid = Enum.reject(capabilities, &defined?/1)
    
    if Enum.empty?(invalid) do
      :ok
    else
      {:error, {:undefined_capabilities, invalid}}
    end
  end
  
  @doc """
  Checks if two capabilities can be composed.
  """
  def composable?(cap1, cap2) when is_atom(cap1) and is_atom(cap2) do
    case get_definition(cap1) do
      nil -> false
      %{composable_with: composable} ->
        cap2 in composable or
        # Check reverse composability
        case get_definition(cap2) do
          nil -> false
          %{composable_with: composable2} -> cap1 in composable2
        end
    end
  end
  
  @doc """
  Finds capabilities that match given input/output types.
  """
  def find_by_types(opts \\ []) do
    input_types = opts[:input_types] || []
    output_types = opts[:output_types] || []
    
    @capabilities
    |> Enum.filter(fn {_cap, spec} ->
      input_match = Enum.empty?(input_types) or
        Enum.any?(input_types, fn type -> type in spec.input_types end)
        
      output_match = Enum.empty?(output_types) or
        Enum.any?(output_types, fn type -> type in spec.output_types end)
        
      input_match and output_match
    end)
    |> Enum.map(fn {cap, _spec} -> cap end)
  end
  
  @doc """
  Builds a capability chain for transforming input to output.
  """
  def build_chain(from_type, to_type) do
    # Simple implementation - could be enhanced with graph algorithms
    capabilities = @capabilities
    |> Enum.filter(fn {_cap, spec} ->
      from_type in spec.input_types and to_type in spec.output_types
    end)
    |> Enum.map(fn {cap, _spec} -> cap end)
    
    case capabilities do
      [] -> find_multi_step_chain(from_type, to_type)
      caps -> {:ok, caps}
    end
  end
  
  @doc """
  Infers capabilities from a tool's schema.
  """
  def infer_from_schema(schema) when is_map(schema) do
    inferred = []
    
    # Check for async parameter
    inferred = if has_parameter?(schema, "async") do
      [:async | inferred]
    else
      inferred
    end
    
    # Check for streaming parameter
    inferred = if has_parameter?(schema, "stream") or has_parameter?(schema, "stream_progress") do
      [:streaming | inferred]
    else
      inferred
    end
    
    # Check for file-related parameters
    inferred = if has_file_parameters?(schema) do
      [:file_operations | inferred]
    else
      inferred
    end
    
    # Check for workflow parameters
    inferred = if has_parameter?(schema, "workflow_name") or has_parameter?(schema, "workflow_id") do
      [:workflow_execution | inferred]
    else
      inferred
    end
    
    inferred
  end
  
  @doc """
  Checks if a set of capabilities meets requirements.
  """
  def requirements_met?(capabilities, required_capabilities) do
    Enum.all?(required_capabilities, fn req ->
      req in capabilities or has_capability_requirement?(capabilities, req)
    end)
  end
  
  # Private functions
  
  defp find_multi_step_chain(from_type, to_type) do
    # Simplified two-step chain finder
    intermediate_caps = @capabilities
    |> Enum.filter(fn {_cap, spec} ->
      from_type in spec.input_types
    end)
    
    for {cap1, spec1} <- intermediate_caps,
        intermediate_type <- spec1.output_types,
        {cap2, spec2} <- @capabilities,
        intermediate_type in spec2.input_types,
        to_type in spec2.output_types,
        composable?(cap1, cap2) do
      [cap1, cap2]
    end
    |> case do
      [] -> {:error, :no_chain_found}
      chains -> {:ok, List.first(chains)}
    end
  end
  
  defp has_parameter?(schema, param_name) do
    case schema do
      %{"properties" => props} -> Map.has_key?(props, param_name)
      _ -> false
    end
  end
  
  defp has_file_parameters?(schema) do
    case schema do
      %{"properties" => props} ->
        Enum.any?(props, fn {name, _spec} ->
          String.contains?(name, "file") or String.contains?(name, "path")
        end)
      _ -> false
    end
  end
  
  defp has_capability_requirement?(capabilities, requirement) do
    # Check if any capability provides the requirement
    Enum.any?(capabilities, fn cap ->
      case get_definition(cap) do
        nil -> false
        %{requirements: reqs} -> requirement in reqs
      end
    end)
  end
end
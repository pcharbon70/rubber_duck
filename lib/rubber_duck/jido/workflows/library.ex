defmodule RubberDuck.Jido.Workflows.Library do
  @moduledoc """
  Library of pre-built workflow patterns for common agent orchestration scenarios.
  
  This module provides reusable workflow templates that can be customized
  for specific use cases. Each workflow is designed to handle common patterns
  in distributed agent systems.
  
  ## Available Workflows
  
  - MapReduce: Distributed map-reduce pattern
  - Pipeline: Sequential processing pipeline
  - FanOut: Parallel task distribution
  - Consensus: Multi-agent consensus building
  - Retry: Automatic retry with backoff
  - CircuitBreaker: Fault-tolerant execution
  - Saga: Distributed transaction pattern
  
  ## Example
  
      # Use a pre-built workflow
      {:ok, result} = Library.run_workflow(:map_reduce, %{
        data: [1, 2, 3, 4, 5],
        map_fn: &(&1 * 2),
        reduce_fn: &Enum.sum/1
      })
      
      # Customize a workflow template
      workflow = Library.get_template(:pipeline)
      |> Library.customize(%{steps: [MyStep1, MyStep2]})
      |> Library.build()
  """
  
  alias RubberDuck.Jido.Agents.WorkflowCoordinator
  
  @type template :: %{
    name: String.t(),
    title: String.t(),
    description: String.t(),
    module: module(),
    category: String.t(),
    complexity: String.t(),
    required_capabilities: [atom()],
    estimated_duration: String.t(),
    tags: [String.t()],
    required_inputs: [atom()],
    optional_inputs: [atom()],
    input_schema: map(),
    output_description: String.t(),
    examples: [map()],
    documentation: String.t()
  }
  
  @workflow_templates %{
    map_reduce: RubberDuck.Jido.Workflows.Library.MapReduce,
    pipeline: RubberDuck.Jido.Workflows.Library.Pipeline,
    fan_out: RubberDuck.Jido.Workflows.Library.FanOut,
    consensus: RubberDuck.Jido.Workflows.Library.Consensus,
    retry: RubberDuck.Jido.Workflows.Library.RetryWorkflow,
    circuit_breaker: RubberDuck.Jido.Workflows.Library.CircuitBreaker,
    saga: RubberDuck.Jido.Workflows.Library.Saga
  }
  
  @doc """
  Lists all available workflow templates with full details.
  """
  def list_templates do
    @workflow_templates
    |> Enum.map(fn {name, module} ->
      create_template_metadata(name, module)
    end)
  end
  
  @doc """
  Gets a template by name with full metadata.
  """
  def get_template(name) when is_binary(name) do
    atom_name = String.to_atom(name)
    get_template(atom_name)
  end
  def get_template(name) when is_atom(name) do
    case Map.get(@workflow_templates, name) do
      nil -> {:error, :not_found}
      module -> {:ok, create_template_metadata(name, module)}
    end
  end
  
  @doc """
  Gets the input schema for a template.
  """
  def get_template_schema(name) when is_binary(name) do
    get_template_schema(String.to_atom(name))
  end
  def get_template_schema(name) when is_atom(name) do
    case get_template(name) do
      {:ok, template} -> {:ok, template.input_schema}
      error -> error
    end
  end
  
  @doc """
  Gets example inputs for a template.
  """
  def get_template_examples(name) when is_binary(name) do
    get_template_examples(String.to_atom(name))
  end
  def get_template_examples(name) when is_atom(name) do
    case get_template(name) do
      {:ok, template} -> template.examples
      _ -> []
    end
  end
  
  @doc """
  Gets detailed information about a workflow template.
  """
  def describe_template(name) when is_atom(name) do
    case Map.get(@workflow_templates, name) do
      nil ->
        {:error, :template_not_found}
      
      module ->
        {:ok, %{
          name: name,
          module: module,
          description: get_description(module),
          required_inputs: get_required_inputs(module),
          options: get_available_options(module)
        }}
    end
  end
  
  @doc """
  Runs a workflow from the library with given inputs.
  """
  def run_workflow(template_name, inputs, opts \\ []) do
    case Map.get(@workflow_templates, template_name) do
      nil ->
        {:error, :template_not_found}
      
      module ->
        WorkflowCoordinator.execute_workflow(module, inputs, opts)
    end
  end
  
  @doc """
  Gets a workflow template for customization.
  """
  def get_template(name) when is_atom(name) do
    case Map.get(@workflow_templates, name) do
      nil -> {:error, :template_not_found}
      module -> {:ok, module}
    end
  end
  
  @doc """
  Creates a custom workflow based on a template.
  """
  def create_custom_workflow(template_name, customizations) do
    with {:ok, template} <- get_template(template_name) do
      # This would create a new module dynamically or return a workflow struct
      # For now, we'll return a configuration that can be executed
      {:ok, %{
        template: template,
        customizations: customizations
      }}
    end
  end
  
  # Private helpers
  
  defp create_template_metadata(name, module) do
    %{
      name: to_string(name),
      title: humanize_name(name),
      description: get_description(module),
      module: module,
      category: get_category(name),
      complexity: get_complexity(name),
      required_capabilities: get_required_capabilities(name),
      estimated_duration: get_estimated_duration(name),
      tags: get_tags(name),
      required_inputs: get_required_inputs(module),
      optional_inputs: get_optional_inputs(module),
      input_schema: get_input_schema(module),
      output_description: get_output_description(module),
      examples: get_examples(name),
      documentation: get_documentation(module)
    }
  end
  
  defp humanize_name(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  
  defp get_category(:map_reduce), do: "data_processing"
  defp get_category(:pipeline), do: "orchestration"
  defp get_category(:fan_out), do: "parallelization"
  defp get_category(:consensus), do: "coordination"
  defp get_category(:retry), do: "resilience"
  defp get_category(:circuit_breaker), do: "resilience"
  defp get_category(:saga), do: "transactions"
  defp get_category(_), do: "general"
  
  defp get_complexity(:map_reduce), do: "intermediate"
  defp get_complexity(:pipeline), do: "simple"
  defp get_complexity(:fan_out), do: "simple"
  defp get_complexity(:consensus), do: "advanced"
  defp get_complexity(:retry), do: "simple"
  defp get_complexity(:circuit_breaker), do: "intermediate"
  defp get_complexity(:saga), do: "advanced"
  defp get_complexity(_), do: "intermediate"
  
  defp get_required_capabilities(:map_reduce), do: [:computation, :aggregation]
  defp get_required_capabilities(:pipeline), do: [:processing]
  defp get_required_capabilities(:fan_out), do: [:processing]
  defp get_required_capabilities(:consensus), do: [:coordination, :voting]
  defp get_required_capabilities(:retry), do: []
  defp get_required_capabilities(:circuit_breaker), do: []
  defp get_required_capabilities(:saga), do: [:transaction, :compensation]
  defp get_required_capabilities(_), do: []
  
  defp get_estimated_duration(:map_reduce), do: "2-30 minutes"
  defp get_estimated_duration(:pipeline), do: "30 seconds - 5 minutes"
  defp get_estimated_duration(:fan_out), do: "1-10 minutes"
  defp get_estimated_duration(:consensus), do: "30 seconds - 2 minutes"
  defp get_estimated_duration(:retry), do: "Variable"
  defp get_estimated_duration(:circuit_breaker), do: "Variable"
  defp get_estimated_duration(:saga), do: "1-15 minutes"
  defp get_estimated_duration(_), do: "Variable"
  
  defp get_tags(:map_reduce), do: ["distributed", "data", "parallel"]
  defp get_tags(:pipeline), do: ["sequential", "processing", "simple"]
  defp get_tags(:fan_out), do: ["parallel", "distribution", "scaling"]
  defp get_tags(:consensus), do: ["coordination", "voting", "agreement"]
  defp get_tags(:retry), do: ["resilience", "fault-tolerance", "reliability"]
  defp get_tags(:circuit_breaker), do: ["resilience", "fault-tolerance", "protection"]
  defp get_tags(:saga), do: ["transactions", "compensation", "consistency"]
  defp get_tags(_), do: []
  
  defp get_optional_inputs(module) do
    if function_exported?(module, :optional_inputs, 0) do
      module.optional_inputs()
    else
      []
    end
  end
  
  defp get_input_schema(module) do
    if function_exported?(module, :input_schema, 0) do
      module.input_schema()
    else
      # Create basic schema from required inputs
      required_inputs = get_required_inputs(module)
      Enum.reduce(required_inputs, %{}, fn input, acc ->
        Map.put(acc, input, %{type: :any, required: true})
      end)
    end
  end
  
  defp get_output_description(module) do
    if function_exported?(module, :output_description, 0) do
      module.output_description()
    else
      "Workflow execution result"
    end
  end
  
  defp get_examples(:map_reduce) do
    [
      %{
        description: "Simple number doubling and sum",
        inputs: %{
          "data" => [1, 2, 3, 4, 5],
          "map_action" => "DoubleAction",
          "reduce_action" => "SumAction",
          "chunk_size" => 2
        }
      }
    ]
  end
  defp get_examples(:pipeline) do
    [
      %{
        description: "Data validation and transformation pipeline",
        inputs: %{
          "data" => %{"value" => 42},
          "stages" => [
            %{"action" => "ValidateAction", "capability" => "validation"},
            %{"action" => "TransformAction", "capability" => "transformation"}
          ]
        }
      }
    ]
  end
  defp get_examples(_), do: []
  
  defp get_documentation(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => module_doc}, _, _} -> module_doc || "No documentation available"
      _ -> "No documentation available"
    end
  rescue
    _ -> "No documentation available"
  end
  
  defp get_description(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => module_doc}, _, _} -> module_doc
      _ -> "No description available"
    end
  rescue
    _ -> "No description available"
  end
  
  defp get_required_inputs(module) do
    if function_exported?(module, :required_inputs, 0) do
      module.required_inputs()
    else
      []
    end
  end
  
  defp get_available_options(module) do
    if function_exported?(module, :available_options, 0) do
      module.available_options()
    else
      []
    end
  end
end
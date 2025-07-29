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
  Lists all available workflow templates.
  """
  def list_templates do
    Map.keys(@workflow_templates)
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
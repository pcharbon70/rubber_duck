defmodule RubberDuck.Agents.PlanDecomposer.HierarchicalDecomposer do
  @moduledoc """
  Hierarchical decomposition strategy for breaking down complex tasks into phases and subtasks.
  
  This strategy is best for complex features with multiple components where tasks
  can be organized into phases with parallel and sequential dependencies.
  """
  
  use Jido.Action,
    name: "hierarchical_decomposer",
    description: "Decomposes plans into hierarchical structure with phases",
    schema: [
      query: [type: :string, required: true],
      context: [type: :map, default: %{}],
      constraints: [type: :map, default: %{}],
      scope: [type: :string, default: "Complete implementation"]
    ]
  
  alias RubberDuck.LLM.Service, as: LLM
  alias RubberDuck.Planning.DecompositionTemplates
  
  require Logger
  
  @impl true
  def run(params, context) do
    state = context[:state] || %{}
    
    # Get the hierarchical decomposition template
    prompt = DecompositionTemplates.get_template(:hierarchical_decomposition, %{
      request: params.query,
      context: inspect(params.context),
      scope: params.scope
    })
    
    case LLM.completion(
      model: state[:llm_config][:model] || "gpt-4",
      messages: [%{role: "user", content: prompt}],
      response_format: %{type: "json_object"}
    ) do
      {:ok, response} ->
        # Extract content from LLM response
        content = extract_content(response)
        
        # Parse hierarchical structure
        hierarchical_data = Jason.decode!(content)
        
        # Extract and flatten tasks
        tasks = extract_hierarchical_tasks(hierarchical_data)
        
        {:ok, tasks}
        
      {:error, reason} ->
        Logger.error("Hierarchical decomposition failed: #{inspect(reason)}")
        {:error, "Failed to decompose: #{inspect(reason)}"}
    end
  end
  
  @doc """
  Entry point for the decomposer matching existing interface.
  """
  def decompose(input, state) do
    params = %{
      query: input.query,
      context: input[:context] || %{},
      constraints: input[:constraints] || %{},
      scope: input[:scope] || "Complete implementation"
    }
    
    run(params, %{state: state})
  end
  
  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{choices: [%{message: %{content: content}} | _]}), do: content
  defp extract_content(_), do: "{\"phases\": []}"
  
  defp extract_hierarchical_tasks(hierarchical_data) do
    phases = hierarchical_data["phases"] || []
    dependencies = hierarchical_data["dependencies"] || []
    critical_path = hierarchical_data["critical_path"] || []
    
    # Flatten the hierarchical structure
    {tasks, _} = phases
    |> Enum.reduce({[], 0}, fn phase, {acc_tasks, position} ->
      phase_tasks = extract_tasks_from_phase(phase, position, critical_path)
      {acc_tasks ++ phase_tasks, position + length(phase_tasks)}
    end)
    
    # Add dependencies to tasks
    add_dependencies_to_tasks(tasks, dependencies)
  end
  
  defp extract_tasks_from_phase(phase, start_position, critical_path) do
    phase_id = phase["id"]
    phase_name = phase["name"]
    phase_tasks = phase["tasks"] || []
    
    phase_tasks
    |> Enum.with_index()
    |> Enum.flat_map(fn {task, task_index} ->
      task_position = start_position + task_index
      
      # Create main task
      main_task = %{
        "id" => task["id"],
        "name" => task["name"],
        "description" => task["description"],
        "complexity" => task["complexity"] || "medium",
        "position" => task_position,
        "phase_id" => phase_id,
        "phase_name" => phase_name,
        "is_critical" => task["id"] in critical_path,
        "metadata" => %{
          "phase" => phase_name,
          "hierarchy_level" => 2,
          "is_critical_path" => task["id"] in critical_path
        }
      }
      
      # Handle subtasks
      subtasks = task["subtasks"] || []
      if Enum.empty?(subtasks) do
        [main_task]
      else
        subtask_list = subtasks
        |> Enum.with_index()
        |> Enum.map(fn {subtask, subtask_index} ->
          %{
            "id" => subtask["id"],
            "name" => subtask["name"],
            "description" => subtask["description"],
            "complexity" => "simple",
            "position" => task_position + (subtask_index + 1) * 0.1,
            "parent_task_id" => task["id"],
            "phase_id" => phase_id,
            "phase_name" => phase_name,
            "metadata" => %{
              "phase" => phase_name,
              "parent_task" => task["name"],
              "hierarchy_level" => 3
            }
          }
        end)
        
        [main_task | subtask_list]
      end
    end)
  end
  
  defp add_dependencies_to_tasks(tasks, dependencies) do
    # Create ID to position mapping
    id_to_position = tasks
    |> Enum.reduce(%{}, fn task, acc ->
      Map.put(acc, task["id"], task["position"])
    end)
    
    # Add dependencies
    tasks
    |> Enum.map(fn task ->
      # Find dependencies for this task
      task_deps = dependencies
      |> Enum.filter(fn dep -> dep["to"] == task["id"] end)
      |> Enum.map(fn dep -> id_to_position[dep["from"]] end)
      |> Enum.filter(&(&1 != nil))
      
      Map.put(task, "depends_on", task_deps)
    end)
  end
end
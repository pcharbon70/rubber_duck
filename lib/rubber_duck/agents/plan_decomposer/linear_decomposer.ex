defmodule RubberDuck.Agents.PlanDecomposer.LinearDecomposer do
  @moduledoc """
  Linear decomposition strategy for breaking down tasks into sequential steps.
  
  This strategy is best for simple, sequential tasks with clear steps where
  each task depends on the completion of the previous one.
  """
  
  use Jido.Action,
    name: "linear_decomposer",
    description: "Decomposes plans into linear sequence of tasks",
    schema: [
      query: [type: :string, required: true],
      context: [type: :map, default: %{}],
      constraints: [type: :map, default: %{}]
    ]
  
  alias RubberDuck.LLM.Service, as: LLM
  alias RubberDuck.Planning.DecompositionTemplates
  
  require Logger
  
  @impl true
  def run(params, context) do
    state = context[:state] || %{}
    
    # Get the linear decomposition template
    prompt = DecompositionTemplates.get_template(:linear_decomposition, %{
      request: params.query,
      context: inspect(params.context),
      constraints: inspect(params.constraints)
    })
    
    case LLM.completion(
      model: state[:llm_config][:model] || "gpt-4",
      messages: [%{role: "user", content: prompt}],
      response_format: %{type: "json_object"}
    ) do
      {:ok, response} ->
        # Extract content from LLM response
        content = extract_content(response)
        
        # Parse and process tasks
        tasks = content
        |> Jason.decode!()
        |> List.wrap()  # Ensure it's a list
        |> Enum.with_index()
        |> Enum.map(fn {task, index} ->
          Map.merge(task, %{
            "position" => index,
            "depends_on" => if(index > 0, do: ["task_#{index - 1}"], else: [])
          })
        end)
        
        {:ok, tasks}
        
      {:error, reason} ->
        Logger.error("Linear decomposition failed: #{inspect(reason)}")
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
      constraints: input[:constraints] || %{}
    }
    
    run(params, %{state: state})
  end
  
  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{choices: [%{message: %{content: content}} | _]}), do: content
  defp extract_content(_), do: "[]"
end
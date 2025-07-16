defmodule RubberDuck.MCP.Registry.Composition do
  @moduledoc """
  Handles tool composition and orchestration for the MCP registry.
  
  This module enables combining multiple tools into workflows with:
  - Sequential execution
  - Parallel execution  
  - Conditional branching
  - Data flow management
  - Error handling and recovery
  """
  
  alias RubberDuck.MCP.Registry
  alias RubberDuck.MCP.Registry.{Metadata, Capabilities}
  
  @type composition_type :: :sequential | :parallel | :conditional
  @type tool_ref :: module() | String.t()
  
  @type tool_spec :: %{
    tool: tool_ref(),
    params: map(),
    output_mapping: map() | nil,
    condition: (map() -> boolean()) | nil
  }
  
  @type composition :: %{
    id: String.t(),
    name: String.t(),
    description: String.t(),
    type: composition_type(),
    tools: [tool_spec()],
    metadata: map(),
    created_at: DateTime.t()
  }
  
  @type execution_result :: %{
    composition_id: String.t(),
    status: :success | :failure | :partial,
    results: [any()],
    errors: [any()],
    execution_time_ms: non_neg_integer()
  }
  
  @doc """
  Creates a sequential composition where tools execute one after another.
  """
  def sequential(name, tools, opts \\ []) do
    build_composition(:sequential, name, tools, opts)
  end
  
  @doc """
  Creates a parallel composition where tools execute concurrently.
  """
  def parallel(name, tools, opts \\ []) do
    build_composition(:parallel, name, tools, opts)
  end
  
  @doc """
  Creates a conditional composition with branching logic.
  """
  def conditional(name, tools, opts \\ []) do
    build_composition(:conditional, name, tools, opts)
  end
  
  @doc """
  Validates a composition for correctness.
  """
  def validate(composition) do
    with :ok <- validate_tools_exist(composition),
         :ok <- validate_data_flow(composition),
         :ok <- validate_capabilities(composition) do
      :ok
    end
  end
  
  @doc """
  Executes a composition with given input.
  """
  def execute(composition, input, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
    result = case composition.type do
      :sequential -> execute_sequential(composition, input, opts)
      :parallel -> execute_parallel(composition, input, opts)
      :conditional -> execute_conditional(composition, input, opts)
    end
    
    end_time = System.monotonic_time(:millisecond)
    execution_time = end_time - start_time
    
    wrap_result(result, composition, execution_time)
  end
  
  @doc """
  Analyzes a composition for optimization opportunities.
  """
  def analyze(composition) do
    %{
      parallelizable_steps: find_parallelizable_steps(composition),
      redundant_tools: find_redundant_tools(composition),
      capability_gaps: find_capability_gaps(composition),
      estimated_latency: estimate_latency(composition)
    }
  end
  
  @doc """
  Converts a composition to a visual representation (Mermaid diagram).
  """
  def to_diagram(composition) do
    """
    graph TD
    #{generate_mermaid_nodes(composition)}
    #{generate_mermaid_edges(composition)}
    """
  end
  
  # Private functions
  
  defp build_composition(type, name, tools, opts) do
    %{
      id: generate_id(),
      name: name,
      description: opts[:description] || "",
      type: type,
      tools: normalize_tool_specs(tools),
      metadata: opts[:metadata] || %{},
      created_at: DateTime.utc_now()
    }
  end
  
  defp normalize_tool_specs(tools) do
    Enum.map(tools, fn
      %{tool: _} = spec -> 
        Map.merge(%{params: %{}, output_mapping: nil, condition: nil}, spec)
      tool when is_atom(tool) ->
        %{tool: tool, params: %{}, output_mapping: nil, condition: nil}
      {tool, params} ->
        %{tool: tool, params: params, output_mapping: nil, condition: nil}
    end)
  end
  
  defp validate_tools_exist(composition) do
    results = Enum.map(composition.tools, fn spec ->
      case Registry.get_tool(spec.tool) do
        {:ok, _} -> :ok
        {:error, :not_found} -> {:error, {:tool_not_found, spec.tool}}
      end
    end)
    
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end
  
  defp validate_data_flow(composition) do
    case composition.type do
      :sequential -> validate_sequential_data_flow(composition)
      :parallel -> validate_parallel_data_flow(composition)
      :conditional -> validate_conditional_data_flow(composition)
    end
  end
  
  defp validate_sequential_data_flow(composition) do
    # Check that output mappings are valid
    Enum.reduce_while(composition.tools, {:ok, %{}}, fn spec, {:ok, context} ->
      if spec.output_mapping do
        # Validate mapping references exist in context
        invalid_refs = Map.keys(spec.output_mapping)
        |> Enum.reject(fn key -> Map.has_key?(context, key) end)
        
        if Enum.empty?(invalid_refs) do
          {:cont, {:ok, Map.put(context, spec.tool, :output)}}
        else
          {:halt, {:error, {:invalid_mapping, spec.tool, invalid_refs}}}
        end
      else
        {:cont, {:ok, Map.put(context, spec.tool, :output)}}
      end
    end)
    |> elem(0)
  end
  
  defp validate_parallel_data_flow(_composition) do
    # Parallel tools don't have direct data dependencies
    :ok
  end
  
  defp validate_conditional_data_flow(composition) do
    # Ensure all branches have conditions except possibly the last
    conditions = Enum.map(composition.tools, & &1.condition)
    has_default = List.last(conditions) == nil
    all_others_have_conditions = Enum.all?(Enum.drop(conditions, -1), & &1 != nil)
    
    if all_others_have_conditions do
      :ok
    else
      {:error, :invalid_conditional_structure}
    end
  end
  
  defp validate_capabilities(composition) do
    # Check capability compatibility between consecutive tools
    case composition.type do
      :sequential -> validate_sequential_capabilities(composition)
      _ -> :ok
    end
  end
  
  defp validate_sequential_capabilities(composition) do
    composition.tools
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce_while(:ok, fn [tool1, tool2], :ok ->
      with {:ok, meta1} <- Registry.get_tool(tool1.tool),
           {:ok, meta2} <- Registry.get_tool(tool2.tool) do
        if compatible_capabilities?(meta1.capabilities, meta2.capabilities) do
          {:cont, :ok}
        else
          {:halt, {:error, {:incompatible_tools, tool1.tool, tool2.tool}}}
        end
      else
        error -> {:halt, error}
      end
    end)
  end
  
  defp compatible_capabilities?(caps1, caps2) do
    # Check if any capability from caps1 is composable with any from caps2
    Enum.any?(caps1, fn cap1 ->
      Enum.any?(caps2, fn cap2 ->
        Capabilities.composable?(cap1, cap2)
      end)
    end)
  end
  
  defp execute_sequential(composition, input, opts) do
    Enum.reduce_while(composition.tools, {:ok, input, []}, fn spec, {:ok, current_input, results} ->
      # Apply output mapping if present
      tool_input = if spec.output_mapping do
        apply_output_mapping(current_input, spec.output_mapping)
      else
        current_input
      end
      
      # Merge with spec params
      final_params = Map.merge(spec.params, tool_input)
      
      # Execute tool
      case execute_tool(spec.tool, final_params, opts) do
        {:ok, result} ->
          {:cont, {:ok, result, results ++ [result]}}
        {:error, _} = error ->
          {:halt, {:error, error, results}}
      end
    end)
  end
  
  defp execute_parallel(composition, input, opts) do
    tasks = Enum.map(composition.tools, fn spec ->
      Task.async(fn ->
        # Merge input with spec params
        final_params = Map.merge(spec.params, input)
        execute_tool(spec.tool, final_params, opts)
      end)
    end)
    
    # Wait for all tasks with timeout
    timeout = opts[:timeout] || 30_000
    
    results = Task.yield_many(tasks, timeout)
    |> Enum.map(fn {task, result} ->
      case result do
        {:ok, {:ok, value}} -> {:ok, value}
        {:ok, {:error, _} = error} -> error
        nil -> 
          Task.shutdown(task, :brutal_kill)
          {:error, :timeout}
      end
    end)
    
    # Check if all succeeded
    errors = Enum.filter(results, &match?({:error, _}, &1))
    
    if Enum.empty?(errors) do
      {:ok, Enum.map(results, fn {:ok, r} -> r end), results}
    else
      {:error, errors, results}
    end
  end
  
  defp execute_conditional(composition, input, opts) do
    # Find the first tool whose condition matches
    matching_spec = Enum.find(composition.tools, fn spec ->
      spec.condition == nil or spec.condition.(input)
    end)
    
    if matching_spec do
      final_params = Map.merge(matching_spec.params, input)
      case execute_tool(matching_spec.tool, final_params, opts) do
        {:ok, result} -> {:ok, result, [result]}
        error -> {:error, error, []}
      end
    else
      {:error, :no_matching_condition, []}
    end
  end
  
  defp execute_tool(tool, params, opts) do
    # This would integrate with the actual MCP server execution
    # For now, return a mock result
    case Registry.get_tool(tool) do
      {:ok, metadata} ->
        # Record execution start
        Registry.record_metric(tool, :execution_start, nil)
        
        # Simulate execution
        start_time = System.monotonic_time(:millisecond)
        Process.sleep(10) # Simulate work
        end_time = System.monotonic_time(:millisecond)
        latency = end_time - start_time
        
        # Record success metric
        Registry.record_metric(tool, {:execution, :success, latency}, nil)
        
        {:ok, %{tool: tool, result: "Mock result for #{inspect(tool)}", latency_ms: latency}}
        
      {:error, :not_found} ->
        {:error, {:tool_not_found, tool}}
    end
  end
  
  defp apply_output_mapping(data, mapping) do
    Enum.reduce(mapping, %{}, fn {new_key, path}, acc ->
      value = get_in(data, parse_path(path))
      Map.put(acc, new_key, value)
    end)
  end
  
  defp parse_path(path) when is_binary(path) do
    String.split(path, ".")
    |> Enum.map(fn segment ->
      case Integer.parse(segment) do
        {index, ""} -> index
        _ -> segment
      end
    end)
  end
  defp parse_path(path), do: [path]
  
  defp wrap_result({:ok, result, all_results}, composition, execution_time) do
    %{
      composition_id: composition.id,
      status: :success,
      results: all_results,
      errors: [],
      execution_time_ms: execution_time,
      final_output: result
    }
  end
  
  defp wrap_result({:error, errors, partial_results}, composition, execution_time) do
    %{
      composition_id: composition.id,
      status: if(Enum.empty?(partial_results), do: :failure, else: :partial),
      results: partial_results,
      errors: List.wrap(errors),
      execution_time_ms: execution_time,
      final_output: nil
    }
  end
  
  defp find_parallelizable_steps(composition) do
    case composition.type do
      :sequential ->
        # Find groups of tools without data dependencies
        composition.tools
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.with_index()
        |> Enum.filter(fn {[t1, t2], _idx} ->
          # If t2 doesn't use output mapping from t1, they could be parallel
          t2.output_mapping == nil
        end)
        |> Enum.map(fn {[t1, t2], idx} -> {idx, idx + 1} end)
      _ ->
        []
    end
  end
  
  defp find_redundant_tools(composition) do
    # Find tools that appear multiple times with same params
    composition.tools
    |> Enum.with_index()
    |> Enum.group_by(fn {spec, _} -> {spec.tool, spec.params} end)
    |> Enum.filter(fn {_, specs} -> length(specs) > 1 end)
    |> Enum.map(fn {{tool, _params}, specs} ->
      %{tool: tool, indices: Enum.map(specs, fn {_, idx} -> idx end)}
    end)
  end
  
  defp find_capability_gaps(composition) do
    # Analyze if there are missing capabilities between tools
    []  # TODO: Implement capability gap analysis
  end
  
  defp estimate_latency(composition) do
    # Estimate based on tool metrics and composition type
    tool_latencies = Enum.map(composition.tools, fn spec ->
      case Registry.get_metrics(spec.tool) do
        {:ok, metrics} -> 
          Registry.Metrics.average_latency(metrics) || 100
        _ -> 
          100  # Default estimate
      end
    end)
    
    case composition.type do
      :sequential -> Enum.sum(tool_latencies)
      :parallel -> Enum.max(tool_latencies)
      :conditional -> Enum.sum(tool_latencies) / length(tool_latencies)
    end
  end
  
  defp generate_mermaid_nodes(composition) do
    composition.tools
    |> Enum.with_index()
    |> Enum.map(fn {spec, idx} ->
      "    T#{idx}[#{inspect(spec.tool)}]"
    end)
    |> Enum.join("\n")
  end
  
  defp generate_mermaid_edges(composition) do
    case composition.type do
      :sequential ->
        composition.tools
        |> Enum.with_index()
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [{_, idx1}, {_, idx2}] ->
          "    T#{idx1} --> T#{idx2}"
        end)
        |> Enum.join("\n")
        
      :parallel ->
        count = length(composition.tools)
        start_edges = Enum.map(0..(count-1), fn idx ->
          "    Start --> T#{idx}"
        end)
        end_edges = Enum.map(0..(count-1), fn idx ->
          "    T#{idx} --> End"
        end)
        (["    Start[Input]"] ++ start_edges ++ end_edges ++ ["    End[Output]"])
        |> Enum.join("\n")
        
      :conditional ->
        composition.tools
        |> Enum.with_index()
        |> Enum.map(fn {spec, idx} ->
          condition = if spec.condition, do: "condition", else: "default"
          "    Start --#{condition}--> T#{idx}"
        end)
        |> Enum.join("\n")
    end
  end
  
  defp generate_id do
    "comp_#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}"
  end
end
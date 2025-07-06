defmodule RubberDuck.Enhancement.PipelineBuilder do
  @moduledoc """
  Builds enhancement pipelines from selected techniques.
  
  Supports sequential, parallel, and conditional pipeline construction
  with proper error handling and resource management.
  """
  
  @type technique :: atom()
  @type technique_config :: {technique(), map()}
  @type pipeline_type :: :sequential | :parallel | :conditional
  @type pipeline_step :: technique_config() | {:parallel, [pipeline_step()]} | {:conditional, condition(), pipeline_step(), pipeline_step()}
  @type condition :: {atom(), any()}
  
  @doc """
  Builds an enhancement pipeline from techniques and type.
  
  ## Pipeline Types
  - `:sequential` - Techniques run one after another
  - `:parallel` - Techniques run concurrently
  - `:conditional` - Techniques run based on conditions
  """
  @spec build([technique_config()], pipeline_type(), map()) :: [pipeline_step()]
  def build(techniques, pipeline_type, config \\ %{})
  
  def build(techniques, :sequential, _config) do
    # Simple sequential pipeline
    techniques
  end
  
  def build(techniques, :parallel, config) do
    # Group techniques that can run in parallel
    groups = group_parallel_techniques(techniques, config)
    
    Enum.map(groups, fn
      [single] -> single
      multiple -> {:parallel, multiple}
    end)
  end
  
  def build(techniques, :conditional, config) do
    # Build conditional pipeline based on technique characteristics
    build_conditional_pipeline(techniques, config)
  end
  
  @doc """
  Optimizes a pipeline for better performance.
  
  Applies optimizations like:
  - Merging compatible parallel operations
  - Removing redundant steps
  - Reordering for better cache usage
  """
  @spec optimize([pipeline_step()]) :: [pipeline_step()]
  def optimize(pipeline) do
    pipeline
    |> merge_parallel_steps()
    |> remove_redundant_steps()
    |> reorder_for_performance()
  end
  
  @doc """
  Validates that a pipeline is well-formed and executable.
  """
  @spec validate([pipeline_step()]) :: :ok | {:error, String.t()}
  def validate(pipeline) do
    cond do
      Enum.empty?(pipeline) ->
        {:error, "Pipeline cannot be empty"}
      
      has_circular_dependencies?(pipeline) ->
        {:error, "Pipeline contains circular dependencies"}
      
      exceeds_resource_limits?(pipeline) ->
        {:error, "Pipeline exceeds resource limits"}
      
      true ->
        :ok
    end
  end
  
  @doc """
  Estimates resource usage for a pipeline.
  """
  @spec estimate_resources([pipeline_step()]) :: map()
  def estimate_resources(pipeline) do
    %{
      estimated_time_ms: estimate_execution_time(pipeline),
      max_parallel_tasks: count_max_parallel_tasks(pipeline),
      memory_estimate_mb: estimate_memory_usage(pipeline),
      api_calls: count_api_calls(pipeline)
    }
  end
  
  # Private functions
  
  defp group_parallel_techniques(techniques, config) do
    max_parallel = Map.get(config, :max_parallel_techniques, 3)
    
    # Group techniques that can run in parallel
    # For now, simple grouping - in production, consider dependencies
    techniques
    |> Enum.chunk_every(max_parallel)
    |> Enum.map(fn chunk ->
      if can_parallelize?(chunk) do
        chunk
      else
        # If can't parallelize, return as sequential steps
        Enum.map(chunk, &[&1]) |> List.flatten()
      end
    end)
    |> List.flatten()
    |> Enum.chunk_by(fn _ -> :rand.uniform() > 0.7 end)  # Simple grouping
  end
  
  defp can_parallelize?(techniques) do
    # Check if techniques can be run in parallel
    # RAG and CoT can run in parallel, but self-correction should be last
    
    has_self_correction = Enum.any?(techniques, fn {tech, _} -> tech == :self_correction end)
    
    if has_self_correction && length(techniques) > 1 do
      false
    else
      # Check for other incompatibilities
      techniques_only = Enum.map(techniques, fn {tech, _} -> tech end)
      
      # No duplicates allowed in parallel
      length(techniques_only) == length(Enum.uniq(techniques_only))
    end
  end
  
  defp build_conditional_pipeline(techniques, config) do
    # Build a conditional pipeline based on technique characteristics
    # This is a simplified version - in production, use more sophisticated logic
    
    case techniques do
      [] -> []
      
      [{:self_correction, sc_config} | rest] ->
        # Self-correction should run conditionally based on error detection
        condition = {:has_errors, true}
        true_branch = {:self_correction, sc_config}
        false_branch = {:noop, %{}}
        
        build_conditional_pipeline(rest, config) ++ [{:conditional, condition, true_branch, false_branch}]
      
      [{:rag, rag_config} | rest] ->
        # RAG might be conditional based on content type
        if Enum.any?(rest, fn {tech, _} -> tech == :cot end) do
          # If CoT follows, make it conditional based on RAG results
          [{:rag, rag_config} | build_conditional_pipeline(rest, config)]
        else
          [{:rag, rag_config} | build_conditional_pipeline(rest, config)]
        end
      
      [first | rest] ->
        [first | build_conditional_pipeline(rest, config)]
    end
  end
  
  defp merge_parallel_steps(pipeline) do
    # Merge adjacent parallel steps if possible
    pipeline
    |> Enum.reduce([], fn
      {:parallel, steps1}, [{:parallel, steps2} | rest] ->
        # Merge if combined size is reasonable
        combined = steps1 ++ steps2
        if length(combined) <= 5 do
          [{:parallel, combined} | rest]
        else
          [{:parallel, steps1}, {:parallel, steps2} | rest]
        end
      
      step, acc ->
        [step | acc]
    end)
    |> Enum.reverse()
  end
  
  defp remove_redundant_steps(pipeline) do
    # Remove duplicate or redundant steps
    seen = MapSet.new()
    
    Enum.reduce(pipeline, {[], seen}, fn
      {technique, _config} = step, {acc, seen_techniques} ->
        if MapSet.member?(seen_techniques, technique) do
          # Skip duplicate technique
          {acc, seen_techniques}
        else
          {[step | acc], MapSet.put(seen_techniques, technique)}
        end
      
      {:parallel, steps}, {acc, seen_techniques} ->
        # Filter parallel steps
        filtered_steps = Enum.reject(steps, fn {tech, _} ->
          MapSet.member?(seen_techniques, tech)
        end)
        
        if Enum.empty?(filtered_steps) do
          {acc, seen_techniques}
        else
          new_seen = Enum.reduce(filtered_steps, seen_techniques, fn {tech, _}, s ->
            MapSet.put(s, tech)
          end)
          {[{:parallel, filtered_steps} | acc], new_seen}
        end
      
      step, {acc, seen_techniques} ->
        {[step | acc], seen_techniques}
    end)
    |> elem(0)
    |> Enum.reverse()
  end
  
  defp reorder_for_performance(pipeline) do
    # Reorder steps for better performance
    # General order: RAG -> CoT -> Self-Correction
    priority_map = %{
      rag: 1,
      cot: 2,
      self_correction: 3
    }
    
    Enum.sort_by(pipeline, fn
      {technique, _} -> Map.get(priority_map, technique, 99)
      {:parallel, _} -> 1.5  # Parallel steps go between RAG and CoT
      {:conditional, _, _, _} -> 2.5  # Conditionals after main processing
      _ -> 99
    end)
  end
  
  defp has_circular_dependencies?(_pipeline) do
    # In this simplified version, we don't have explicit dependencies
    # In production, check for circular references in conditional branches
    false
  end
  
  defp exceeds_resource_limits?(pipeline) do
    max_steps = 10
    step_count = count_total_steps(pipeline)
    step_count > max_steps
  end
  
  defp count_total_steps(pipeline) do
    Enum.reduce(pipeline, 0, fn
      {:parallel, steps}, acc -> acc + length(steps)
      {:conditional, _, true_branch, false_branch}, acc ->
        acc + 1 + count_total_steps([true_branch]) + count_total_steps([false_branch])
      _, acc -> acc + 1
    end)
  end
  
  defp estimate_execution_time(pipeline) do
    # Estimate based on typical execution times
    technique_times = %{
      rag: 2000,
      cot: 3000,
      self_correction: 4000,
      noop: 0
    }
    
    Enum.reduce(pipeline, 0, fn
      {:parallel, steps}, acc ->
        # Parallel steps take as long as the slowest one
        max_time = Enum.map(steps, fn {tech, _} -> 
          Map.get(technique_times, tech, 1000)
        end) |> Enum.max()
        acc + max_time
      
      {:conditional, _, true_branch, false_branch}, acc ->
        # Assume 50% chance for each branch
        {true_time, _} = estimate_execution_time([true_branch])
        {false_time, _} = estimate_execution_time([false_branch])
        acc + (true_time + false_time) / 2
      
      {technique, _}, acc ->
        acc + Map.get(technique_times, technique, 1000)
    end)
  end
  
  defp count_max_parallel_tasks(pipeline) do
    Enum.reduce(pipeline, 1, fn
      {:parallel, steps}, acc -> max(acc, length(steps))
      _, acc -> acc
    end)
  end
  
  defp estimate_memory_usage(pipeline) do
    # Rough estimates in MB
    technique_memory = %{
      rag: 100,  # Vector store queries
      cot: 50,   # Chain state
      self_correction: 75  # Iteration history
    }
    
    base_memory = 50  # Base overhead
    
    step_memory = Enum.reduce(pipeline, 0, fn
      {:parallel, steps}, acc ->
        # Parallel steps use memory simultaneously
        acc + Enum.sum(Enum.map(steps, fn {tech, _} -> 
          Map.get(technique_memory, tech, 25)
        end))
      
      {technique, _}, acc ->
        acc + Map.get(technique_memory, technique, 25)
      
      _, acc -> acc
    end)
    
    base_memory + step_memory
  end
  
  defp count_api_calls(pipeline) do
    # Estimate API calls per technique
    api_calls_per_technique = %{
      rag: 2,  # Embedding + retrieval
      cot: 1,  # LLM call per step (estimated)
      self_correction: 3  # Multiple iterations
    }
    
    Enum.reduce(pipeline, 0, fn
      {:parallel, steps}, acc ->
        acc + Enum.sum(Enum.map(steps, fn {tech, _} -> 
          Map.get(api_calls_per_technique, tech, 0)
        end))
      
      {technique, _}, acc ->
        acc + Map.get(api_calls_per_technique, technique, 0)
      
      _, acc -> acc
    end)
  end
end
defmodule RubberDuck.Planning.Critics.Orchestrator do
  @moduledoc """
  Orchestrates the execution of multiple critics and aggregates their results.
  
  The orchestrator manages:
  - Parallel execution of critics
  - Result aggregation
  - Validation caching
  - Custom critic registration
  - Configuration management
  """
  
  alias RubberDuck.Planning.Critics.{CriticBehaviour, HardCritic, SoftCritic}
  alias RubberDuck.Planning.{Validation, Plan, Task}
  
  require Logger
  
  @default_timeout 30_000  # 30 seconds
  @cache_ttl 3_600_000    # 1 hour in milliseconds
  
  defstruct [
    :hard_critics,
    :soft_critics,
    :custom_critics,
    :config,
    :cache_enabled,
    :parallel_execution,
    :timeout
  ]
  
  @type t :: %__MODULE__{
    hard_critics: [module()],
    soft_critics: [module()],
    custom_critics: [module()],
    config: map(),
    cache_enabled: boolean(),
    parallel_execution: boolean(),
    timeout: non_neg_integer()
  }
  
  @doc """
  Creates a new orchestrator with the given options.
  """
  def new(opts \\ []) do
    %__MODULE__{
      hard_critics: Keyword.get(opts, :hard_critics, HardCritic.all_critics()),
      soft_critics: Keyword.get(opts, :soft_critics, SoftCritic.all_critics()),
      custom_critics: Keyword.get(opts, :custom_critics, []),
      config: Keyword.get(opts, :config, %{}),
      cache_enabled: Keyword.get(opts, :cache_enabled, true),
      parallel_execution: Keyword.get(opts, :parallel_execution, true),
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }
  end
  
  @doc """
  Validates a target (Plan or Task) using all configured critics.
  Returns a list of validation results.
  """
  def validate(orchestrator, target, opts \\ []) do
    target_id = get_target_id(target)
    cache_key = generate_cache_key(target_id, opts)
    
    # Check cache if enabled
    if orchestrator.cache_enabled do
      case get_cached_results(cache_key) do
        {:ok, cached_results} ->
          Logger.debug("Using cached validation results for #{target_id}")
          {:ok, cached_results}
          
        :miss ->
          perform_validation(orchestrator, target, opts, cache_key)
      end
    else
      perform_validation(orchestrator, target, opts, cache_key)
    end
  end
  
  @doc """
  Validates only with hard critics (blocking validations).
  """
  def validate_hard(orchestrator, target, opts \\ []) do
    critics = orchestrator.hard_critics ++ 
              Enum.filter(orchestrator.custom_critics, &(&1.type() == :hard))
    
    run_critics(critics, target, opts, orchestrator)
  end
  
  @doc """
  Validates only with soft critics (quality validations).
  """
  def validate_soft(orchestrator, target, opts \\ []) do
    critics = orchestrator.soft_critics ++ 
              Enum.filter(orchestrator.custom_critics, &(&1.type() == :soft))
    
    run_critics(critics, target, opts, orchestrator)
  end
  
  @doc """
  Adds a custom critic to the orchestrator.
  """
  def add_critic(orchestrator, critic_module) do
    if critic_implements_behaviour?(critic_module) do
      %{orchestrator | custom_critics: [critic_module | orchestrator.custom_critics]}
    else
      raise ArgumentError, "#{inspect(critic_module)} does not implement CriticBehaviour"
    end
  end
  
  @doc """
  Configures a specific critic.
  """
  def configure_critic(orchestrator, critic_module, config) do
    updated_config = Map.put(orchestrator.config, critic_module, config)
    %{orchestrator | config: updated_config}
  end
  
  @doc """
  Aggregates validation results into a summary.
  """
  def aggregate_results(validation_results) do
    results_by_type = Enum.group_by(validation_results, fn {critic, _} -> critic.type() end)
    
    hard_results = Map.get(results_by_type, :hard, [])
    soft_results = Map.get(results_by_type, :soft, [])
    
    %{
      summary: build_summary(validation_results),
      hard_critics: aggregate_critic_type(hard_results),
      soft_critics: aggregate_critic_type(soft_results),
      all_validations: format_all_validations(validation_results),
      blocking_issues: find_blocking_issues(hard_results),
      suggestions: collect_all_suggestions(validation_results),
      metadata: %{
        total_critics_run: length(validation_results),
        execution_time_ms: calculate_total_time(validation_results),
        timestamp: DateTime.utc_now()
      }
    }
  end
  
  @doc """
  Saves validation results to the database.
  """
  def persist_results(target, validation_results) do
    target_attrs = case target do
      %Plan{id: id} -> %{plan_id: id}
      %Task{id: id} -> %{task_id: id}
      _ -> %{}
    end
    
    validations = 
      validation_results
      |> Enum.filter(fn {_, result} -> match?({:ok, _}, result) end)
      |> Enum.map(fn {critic, {:ok, result}} ->
        Map.merge(target_attrs, %{
          critic_name: critic.name(),
          critic_type: critic.type(),
          status: result.status,
          severity: Map.get(result, :severity, CriticBehaviour.default_severity(result.status, critic.type())),
          message: result.message,
          details: Map.get(result, :details),
          suggestions: Map.get(result, :suggestions, []),
          metadata: Map.get(result, :metadata, %{})
        })
      end)
    
    # Batch create validations
    case Ash.bulk_create(Validation, validations, return_records?: true) do
      %{records: records} -> {:ok, records}
      error -> {:error, error}
    end
  end
  
  # Private functions
  
  defp perform_validation(orchestrator, target, opts, cache_key) do
    all_critics = orchestrator.hard_critics ++ 
                  orchestrator.soft_critics ++ 
                  orchestrator.custom_critics
    
    results = run_critics(all_critics, target, opts, orchestrator)
    
    # Cache results if enabled
    if orchestrator.cache_enabled do
      cache_results(cache_key, results)
    end
    
    {:ok, results}
  end
  
  defp run_critics(critics, target, opts, orchestrator) do
    # Filter critics that can handle this target
    applicable_critics = Enum.filter(critics, fn critic ->
      if function_exported?(critic, :can_validate?, 1) do
        critic.can_validate?(target)
      else
        true
      end
    end)
    
    # Sort by priority
    sorted_critics = Enum.sort_by(applicable_critics, & &1.priority())
    
    # Configure critics
    configured_opts = Enum.map(sorted_critics, fn critic ->
      critic_config = Map.get(orchestrator.config, critic, %{})
      merged_opts = Keyword.merge(opts, Keyword.new(critic_config))
      
      if function_exported?(critic, :configure, 1) do
        critic.configure(merged_opts)
      else
        merged_opts
      end
    end)
    
    # Execute critics
    if orchestrator.parallel_execution do
      run_parallel(sorted_critics, target, configured_opts, orchestrator.timeout)
    else
      run_sequential(sorted_critics, target, configured_opts)
    end
  end
  
  defp run_parallel(critics, target, opts_list, timeout) do
    tasks = 
      critics
      |> Enum.zip(opts_list)
      |> Enum.map(fn {critic, opts} ->
        Elixir.Task.async(fn ->
          start_time = System.monotonic_time(:millisecond)
          
          result = try do
            critic.validate(target, opts)
          rescue
            e ->
              Logger.error("Critic #{critic.name()} crashed: #{Exception.message(e)}")
              {:error, "Critic crashed: #{Exception.message(e)}"}
          end
          
          execution_time = System.monotonic_time(:millisecond) - start_time
          {critic, result, execution_time}
        end)
      end)
    
    tasks
    |> Elixir.Task.yield_many(timeout)
    |> Enum.map(fn {task, res} ->
      case res do
        {:ok, {critic, result, time}} ->
          {critic, result, time}
          
        {:exit, reason} ->
          {task_critic(task, critics), {:error, "Critic crashed: #{inspect(reason)}"}, 0}
          
        nil ->
          Elixir.Task.shutdown(task, :brutal_kill)
          {task_critic(task, critics), {:error, "Critic timed out"}, timeout}
      end
    end)
    |> Enum.map(fn {critic, result, _time} -> {critic, result} end)
  end
  
  defp run_sequential(critics, target, opts_list) do
    critics
    |> Enum.zip(opts_list)
    |> Enum.map(fn {critic, opts} ->
      result = try do
        critic.validate(target, opts)
      rescue
        e ->
          Logger.error("Critic #{critic.name()} crashed: #{Exception.message(e)}")
          {:error, "Critic crashed: #{Exception.message(e)}"}
      end
      
      {critic, result}
    end)
  end
  
  defp task_critic(task, critics) do
    # Attempt to find which critic a task belongs to
    # This is a best-effort approach
    Enum.find(critics, fn critic -> 
      inspect(task) =~ inspect(critic)
    end) || UnknownCritic
  end
  
  defp get_target_id(%Plan{id: id}), do: {:plan, id}
  defp get_target_id(%Task{id: id}), do: {:task, id}
  defp get_target_id(%{id: id}), do: {:unknown, id}
  defp get_target_id(_), do: {:unknown, :no_id}
  
  defp generate_cache_key(target_id, opts) do
    opts_hash = :erlang.phash2(opts)
    "critic_validation:#{inspect(target_id)}:#{opts_hash}"
  end
  
  defp get_cached_results(cache_key) do
    case Process.get(cache_key) do
      {results, timestamp} when is_integer(timestamp) ->
        age = System.monotonic_time(:millisecond) - timestamp
        if age < @cache_ttl do
          {:ok, results}
        else
          Process.delete(cache_key)
          :miss
        end
        
      _ ->
        :miss
    end
  end
  
  defp cache_results(cache_key, results) do
    Process.put(cache_key, {results, System.monotonic_time(:millisecond)})
  end
  
  defp build_summary(validation_results) do
    statuses = validation_results
    |> Enum.filter(fn {_, result} -> match?({:ok, _}, result) end)
    |> Enum.map(fn {_, {:ok, result}} -> result.status end)
    
    cond do
      :failed in statuses -> :failed
      :warning in statuses -> :warning
      true -> :passed
    end
  end
  
  defp aggregate_critic_type(critic_results) do
    critic_results
    |> Enum.map(fn {critic, result} ->
      case result do
        {:ok, validation} ->
          %{
            critic: critic.name(),
            status: validation.status,
            message: validation.message,
            details: Map.get(validation, :details)
          }
          
        {:error, error} ->
          %{
            critic: critic.name(),
            status: :error,
            message: "Critic execution failed",
            details: %{error: error}
          }
      end
    end)
  end
  
  defp format_all_validations(validation_results) do
    Enum.map(validation_results, fn {critic, result} ->
      base = %{
        critic_name: critic.name(),
        critic_type: critic.type(),
        priority: critic.priority()
      }
      
      case result do
        {:ok, validation} ->
          Map.merge(base, validation)
          
        {:error, error} ->
          Map.merge(base, %{
            status: :error,
            message: "Execution failed",
            error: error
          })
      end
    end)
  end
  
  defp find_blocking_issues(hard_results) do
    hard_results
    |> Enum.filter(fn {_, result} ->
      match?({:ok, %{status: :failed}}, result)
    end)
    |> Enum.map(fn {critic, {:ok, validation}} ->
      %{
        critic: critic.name(),
        message: validation.message,
        details: Map.get(validation, :details)
      }
    end)
  end
  
  defp collect_all_suggestions(validation_results) do
    validation_results
    |> Enum.filter(fn {_, result} -> match?({:ok, _}, result) end)
    |> Enum.flat_map(fn {_, {:ok, validation}} ->
      Map.get(validation, :suggestions, [])
    end)
    |> Enum.uniq()
  end
  
  defp calculate_total_time(_validation_results) do
    # In the parallel implementation, we track execution times
    # For now, return 0 as we'll need to modify the result structure
    0
  end
  
  defp critic_implements_behaviour?(module) do
    behaviours = module.__info__(:attributes)[:behaviour] || []
    CriticBehaviour in behaviours
  end
  
  # Fallback module for unknown critics
  defmodule UnknownCritic do
    def name, do: "Unknown Critic"
    def type, do: :unknown
    def priority, do: 999
  end
end
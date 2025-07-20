defmodule RubberDuck.Planning.Critics.HardCritic do
  @moduledoc """
  Hard critics for correctness validation of plans and tasks.
  
  Hard critics enforce correctness constraints and fail validation
  when critical issues are found. They include:
  - Syntax validation
  - Dependency validation
  - Constraint satisfaction
  - Feasibility analysis
  - Resource validation
  """
  
  alias RubberDuck.Planning.Critics.CriticBehaviour
  alias RubberDuck.Planning.{Plan, Task, Constraint}
  alias RubberDuck.Analysis.AST
  
  require Logger
  
  # Sub-critic modules
  defmodule SyntaxValidator do
    @moduledoc "Validates code syntax using AST parsing"
    @behaviour CriticBehaviour
    
    @impl true
    def name, do: "Syntax Validator"
    
    @impl true
    def type, do: :hard
    
    @impl true
    def priority, do: 10
    
    @impl true
    def validate(target, _opts) do
      case extract_code_snippets(target) do
        [] ->
          {:ok, CriticBehaviour.validation_result(:passed, "No code snippets to validate")}
          
        snippets ->
          results = Enum.map(snippets, &validate_snippet/1)
          aggregate_syntax_results(results)
      end
    end
    
    defp extract_code_snippets(%{details: %{"code" => code}}), do: [code]
    defp extract_code_snippets(%{details: %{"snippets" => snippets}}), do: snippets
    defp extract_code_snippets(%{description: desc}) when is_binary(desc) do
      # Extract code blocks from markdown
      ~r/```(?:elixir|ex)?\n(.*?)```/ms
      |> Regex.scan(desc, capture: :all_but_first)
      |> Enum.map(&List.first/1)
    end
    defp extract_code_snippets(_), do: []
    
    defp validate_snippet(code) do
      case AST.parse(code, :string) do
        {:ok, _ast} ->
          {:ok, "Valid syntax"}
          
        {:error, {line, error, _}} ->
          {:error, "Syntax error at line #{line}: #{error}"}
          
        {:error, error} ->
          {:error, "Syntax error: #{inspect(error)}"}
      end
    end
    
    defp aggregate_syntax_results(results) do
      errors = Enum.filter(results, &match?({:error, _}, &1))
      
      if Enum.empty?(errors) do
        {:ok, CriticBehaviour.validation_result(:passed, "All syntax validation passed")}
      else
        error_messages = Enum.map(errors, fn {:error, msg} -> msg end)
        
        {:ok, CriticBehaviour.validation_result(
          :failed, 
          "Syntax validation failed",
          details: %{errors: error_messages},
          suggestions: ["Fix syntax errors in code snippets", "Ensure code is valid Elixir"]
        )}
      end
    end
  end
  
  defmodule DependencyValidator do
    @moduledoc "Validates task dependencies and detects cycles"
    @behaviour CriticBehaviour
    
    @impl true
    def name, do: "Dependency Validator"
    
    @impl true
    def type, do: :hard
    
    @impl true
    def priority, do: 20
    
    @impl true
    def validate(%Task{} = task, opts) do
      # For individual tasks, check if dependencies exist
      plan = Keyword.get(opts, :plan)
      
      if plan && task.dependencies do
        validate_task_dependencies(task, plan)
      else
        {:ok, CriticBehaviour.validation_result(:passed, "No dependencies to validate")}
      end
    end
    
    def validate(%Plan{} = plan, _opts) do
      # For plans, check all task dependencies and detect cycles
      case get_plan_tasks(plan) do
        [] ->
          {:ok, CriticBehaviour.validation_result(:passed, "No tasks in plan")}
          
        tasks ->
          validate_plan_dependencies(tasks)
      end
    end
    
    def validate(_, _) do
      {:ok, CriticBehaviour.validation_result(:passed, "Not applicable for this target type")}
    end
    
    defp validate_task_dependencies(task, plan) do
      task_ids = get_plan_tasks(plan) |> Enum.map(& &1.id) |> MapSet.new()
      missing = Enum.reject(task.dependencies, &MapSet.member?(task_ids, &1))
      
      if Enum.empty?(missing) do
        {:ok, CriticBehaviour.validation_result(:passed, "All dependencies exist")}
      else
        {:ok, CriticBehaviour.validation_result(
          :failed,
          "Missing dependencies",
          details: %{missing_dependencies: missing},
          suggestions: ["Ensure all dependency task IDs exist in the plan"]
        )}
      end
    end
    
    defp validate_plan_dependencies(tasks) do
      dependency_map = build_dependency_map(tasks)
      
      case detect_cycles(dependency_map) do
        [] ->
          {:ok, CriticBehaviour.validation_result(:passed, "No dependency cycles detected")}
          
        cycles ->
          {:ok, CriticBehaviour.validation_result(
            :failed,
            "Circular dependencies detected",
            details: %{cycles: cycles},
            suggestions: ["Remove circular dependencies", "Restructure task dependencies"]
          )}
      end
    end
    
    defp build_dependency_map(tasks) do
      Enum.reduce(tasks, %{}, fn task, acc ->
        Map.put(acc, task.id, task.dependencies || [])
      end)
    end
    
    defp detect_cycles(dependency_map) do
      # Simple cycle detection using DFS
      visited = MapSet.new()
      rec_stack = MapSet.new()
      cycles = []
      
      Enum.reduce(Map.keys(dependency_map), cycles, fn node, acc ->
        if MapSet.member?(visited, node) do
          acc
        else
          {_, _, new_cycles} = dfs_cycle_detect(node, dependency_map, visited, rec_stack, [])
          acc ++ new_cycles
        end
      end)
    end
    
    defp dfs_cycle_detect(node, deps, visited, rec_stack, path) do
      visited = MapSet.put(visited, node)
      rec_stack = MapSet.put(rec_stack, node)
      path = [node | path]
      
      deps_for_node = Map.get(deps, node, [])
      
      {visited, rec_stack, cycles} = 
        Enum.reduce(deps_for_node, {visited, rec_stack, []}, fn dep, {v, rs, c} ->
          cond do
            MapSet.member?(rs, dep) ->
              # Found a cycle
              cycle_path = Enum.reverse([dep | Enum.take_while(path, &(&1 != dep))])
              {v, rs, [cycle_path | c]}
              
            not MapSet.member?(v, dep) ->
              dfs_cycle_detect(dep, deps, v, rs, path)
              
            true ->
              {v, rs, c}
          end
        end)
      
      rec_stack = MapSet.delete(rec_stack, node)
      {visited, rec_stack, cycles}
    end
    
    defp get_plan_tasks(%Plan{} = _plan) do
      # This would need to load tasks from the plan
      # For now, return empty list
      []
    end
  end
  
  defmodule ConstraintChecker do
    @moduledoc "Validates plans and tasks against defined constraints"
    @behaviour CriticBehaviour
    
    @impl true
    def name, do: "Constraint Checker"
    
    @impl true
    def type, do: :hard
    
    @impl true
    def priority, do: 30
    
    @impl true
    def validate(target, opts) do
      constraints = Keyword.get(opts, :constraints, [])
      
      if Enum.empty?(constraints) do
        {:ok, CriticBehaviour.validation_result(:passed, "No constraints to check")}
      else
        check_constraints(target, constraints)
      end
    end
    
    defp check_constraints(target, constraints) do
      results = Enum.map(constraints, &check_single_constraint(target, &1))
      
      failed = Enum.filter(results, fn {status, _} -> status == :failed end)
      warnings = Enum.filter(results, fn {status, _} -> status == :warning end)
      
      cond do
        not Enum.empty?(failed) ->
          messages = Enum.map(failed, fn {_, msg} -> msg end)
          {:ok, CriticBehaviour.validation_result(
            :failed,
            "Constraint violations found",
            details: %{violations: messages},
            suggestions: ["Review and fix constraint violations"]
          )}
          
        not Enum.empty?(warnings) ->
          messages = Enum.map(warnings, fn {_, msg} -> msg end)
          {:ok, CriticBehaviour.validation_result(
            :warning,
            "Constraint warnings found",
            details: %{warnings: messages}
          )}
          
        true ->
          {:ok, CriticBehaviour.validation_result(:passed, "All constraints satisfied")}
      end
    end
    
    defp check_single_constraint(target, %Constraint{} = constraint) do
      case constraint.type do
        :max_duration ->
          check_duration_constraint(target, constraint)
          
        :required_resources ->
          check_resource_constraint(target, constraint)
          
        :dependency_limit ->
          check_dependency_limit(target, constraint)
          
        _ ->
          {:passed, "Unknown constraint type: #{constraint.type}"}
      end
    end
    
    defp check_single_constraint(target, constraint_map) when is_map(constraint_map) do
      # Handle raw constraint maps
      type = Map.get(constraint_map, :type, :unknown)
      # Convert to a simple map since Constraint might not have constraint_type field
      check_single_constraint(target, %{type: type, parameters: constraint_map})
    end
    
    defp check_duration_constraint(%{estimated_duration: duration}, constraint) do
      max_duration = get_in(constraint.parameters, ["max_hours"]) || 
                    get_in(constraint.parameters, [:max_hours])
      
      if duration && max_duration && duration > max_duration do
        {:failed, "Duration #{duration}h exceeds maximum #{max_duration}h"}
      else
        {:passed, "Duration constraint satisfied"}
      end
    end
    
    defp check_resource_constraint(target, constraint) do
      required = get_in(constraint.parameters, ["resources"]) ||
                get_in(constraint.parameters, [:resources]) || []
      
      available = Map.get(target, :available_resources, [])
      missing = Enum.reject(required, &(&1 in available))
      
      if Enum.empty?(missing) do
        {:passed, "All required resources available"}
      else
        {:failed, "Missing required resources: #{Enum.join(missing, ", ")}"}
      end
    end
    
    defp check_dependency_limit(%{dependencies: deps}, constraint) when is_list(deps) do
      max_deps = get_in(constraint.parameters, ["max"]) ||
                get_in(constraint.parameters, [:max]) || 10
      
      if length(deps) > max_deps do
        {:warning, "Task has #{length(deps)} dependencies, exceeds recommended #{max_deps}"}
      else
        {:passed, "Dependency count within limits"}
      end
    end
    
    defp check_dependency_limit(_, _), do: {:passed, "No dependencies"}
  end
  
  defmodule FeasibilityAnalyzer do
    @moduledoc "Analyzes whether plans and tasks are feasible"
    @behaviour CriticBehaviour
    
    @impl true
    def name, do: "Feasibility Analyzer"
    
    @impl true
    def type, do: :hard
    
    @impl true
    def priority, do: 40
    
    @impl true
    def validate(target, _opts) do
      checks = [
        check_complexity_feasibility(target),
        check_time_feasibility(target),
        check_scope_feasibility(target)
      ]
      
      aggregate_feasibility_results(checks)
    end
    
    defp check_complexity_feasibility(%{complexity: complexity}) when is_atom(complexity) do
      case complexity do
        :simple -> {:ok, "Simple complexity is feasible"}
        :medium -> {:ok, "Medium complexity is manageable"}
        :complex -> {:warning, "Complex tasks require careful planning"}
        :very_complex -> {:warning, "Very complex tasks have higher risk"}
        _ -> {:ok, "Complexity assessment pending"}
      end
    end
    defp check_complexity_feasibility(_), do: {:ok, "No complexity specified"}
    
    defp check_time_feasibility(%{estimated_duration: duration, deadline: deadline}) 
         when not is_nil(duration) and not is_nil(deadline) do
      hours_until_deadline = DateTime.diff(deadline, DateTime.utc_now(), :hour)
      
      cond do
        hours_until_deadline < 0 ->
          {:error, "Deadline has already passed"}
          
        duration > hours_until_deadline ->
          {:error, "Estimated duration #{duration}h exceeds time until deadline #{hours_until_deadline}h"}
          
        duration > hours_until_deadline * 0.8 ->
          {:warning, "Tight timeline: #{duration}h task with #{hours_until_deadline}h until deadline"}
          
        true ->
          {:ok, "Timeline is feasible"}
      end
    end
    defp check_time_feasibility(_), do: {:ok, "No time constraints"}
    
    defp check_scope_feasibility(%{description: desc}) when is_binary(desc) do
      word_count = String.split(desc) |> length()
      
      cond do
        word_count < 10 ->
          {:warning, "Task description may be too vague (#{word_count} words)"}
          
        word_count > 500 ->
          {:warning, "Task scope may be too large (#{word_count} words)"}
          
        true ->
          {:ok, "Scope appears reasonable"}
      end
    end
    defp check_scope_feasibility(_), do: {:ok, "Scope not assessed"}
    
    defp aggregate_feasibility_results(checks) do
      errors = Enum.filter(checks, &match?({:error, _}, &1))
      warnings = Enum.filter(checks, &match?({:warning, _}, &1))
      
      cond do
        not Enum.empty?(errors) ->
          messages = Enum.map(errors, fn {:error, msg} -> msg end)
          {:ok, CriticBehaviour.validation_result(
            :failed,
            "Feasibility issues found",
            details: %{errors: messages},
            suggestions: ["Address critical feasibility issues", "Consider breaking down the task"]
          )}
          
        not Enum.empty?(warnings) ->
          messages = Enum.map(warnings, fn {:warning, msg} -> msg end)
          {:ok, CriticBehaviour.validation_result(
            :warning,
            "Feasibility concerns",
            details: %{warnings: messages},
            suggestions: ["Review feasibility warnings", "Adjust scope or timeline if needed"]
          )}
          
        true ->
          {:ok, CriticBehaviour.validation_result(:passed, "Plan/task appears feasible")}
      end
    end
  end
  
  defmodule ResourceValidator do
    @moduledoc "Validates resource requirements and availability"
    @behaviour CriticBehaviour
    
    @impl true
    def name, do: "Resource Validator"
    
    @impl true
    def type, do: :hard
    
    @impl true
    def priority, do: 50
    
    @impl true
    def validate(target, opts) do
      available_resources = Keyword.get(opts, :available_resources, %{})
      
      case extract_resource_requirements(target) do
        nil ->
          {:ok, CriticBehaviour.validation_result(:passed, "No resource requirements specified")}
          
        requirements ->
          validate_resources(requirements, available_resources)
      end
    end
    
    defp extract_resource_requirements(%{resource_requirements: reqs}), do: reqs
    defp extract_resource_requirements(%{details: %{"resources" => reqs}}), do: reqs
    defp extract_resource_requirements(_), do: nil
    
    defp validate_resources(requirements, available) when is_map(requirements) do
      validations = Enum.map(requirements, fn {resource, required} ->
        available_amount = Map.get(available, resource, 0)
        
        cond do
          is_number(required) and is_number(available_amount) ->
            if available_amount >= required do
              {:ok, "#{resource}: #{available_amount} available (#{required} required)"}
            else
              {:error, "#{resource}: insufficient (#{available_amount}/#{required})"}
            end
            
          is_boolean(required) ->
            if required and not Map.get(available, resource, false) do
              {:error, "#{resource}: required but not available"}
            else
              {:ok, "#{resource}: requirement met"}
            end
            
          true ->
            {:warning, "#{resource}: cannot validate requirement"}
        end
      end)
      
      aggregate_resource_results(validations)
    end
    
    defp validate_resources(requirements, available) when is_list(requirements) do
      # Handle list of required resources
      missing = Enum.reject(requirements, &Map.has_key?(available, &1))
      
      if Enum.empty?(missing) do
        {:ok, CriticBehaviour.validation_result(:passed, "All required resources available")}
      else
        {:ok, CriticBehaviour.validation_result(
          :failed,
          "Missing required resources",
          details: %{missing: missing},
          suggestions: ["Ensure all required resources are available", "Update resource requirements"]
        )}
      end
    end
    
    defp aggregate_resource_results(validations) do
      errors = Enum.filter(validations, &match?({:error, _}, &1))
      warnings = Enum.filter(validations, &match?({:warning, _}, &1))
      
      cond do
        not Enum.empty?(errors) ->
          messages = Enum.map(errors, fn {:error, msg} -> msg end)
          {:ok, CriticBehaviour.validation_result(
            :failed,
            "Resource validation failed",
            details: %{errors: messages},
            suggestions: ["Acquire missing resources", "Adjust resource requirements"]
          )}
          
        not Enum.empty?(warnings) ->
          messages = Enum.map(warnings, fn {:warning, msg} -> msg end)
          {:ok, CriticBehaviour.validation_result(
            :warning,
            "Resource validation warnings",
            details: %{warnings: messages}
          )}
          
        true ->
          {:ok, CriticBehaviour.validation_result(:passed, "All resource requirements met")}
      end
    end
  end
  
  @doc """
  Returns all available hard critics.
  """
  def all_critics do
    [
      SyntaxValidator,
      DependencyValidator,
      ConstraintChecker,
      FeasibilityAnalyzer,
      ResourceValidator
    ]
  end
  
  @doc """
  Runs all hard critics against a target.
  """
  def validate_all(target, opts \\ []) do
    critics = Keyword.get(opts, :critics, all_critics())
    
    critics
    |> Enum.sort_by(& &1.priority())
    |> Enum.map(fn critic ->
      Logger.debug("Running hard critic: #{critic.name()}")
      
      result = try do
        critic.validate(target, opts)
      rescue
        e ->
          Logger.error("Critic #{critic.name()} failed: #{inspect(e)}")
          {:error, "Critic execution failed: #{Exception.message(e)}"}
      end
      
      {critic, result}
    end)
  end
end
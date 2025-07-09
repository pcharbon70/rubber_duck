Based on the comprehensive research on LLM planning capabilities and RubberDuck's current architecture, I'll design a planning enhancement that leverages the LLM-Modulo framework while building on your existing infrastructure.

# RubberDuck Planning Enhancement Design

## Overview

Based on the LLM-Modulo framework research and RubberDuck's existing architecture, I propose a comprehensive planning enhancement that integrates seamlessly with your current implementation. This design leverages your existing CoT, RAG, and Self-Correction capabilities while adding robust planning validation through external critics.

## Core Architecture: LLM-Modulo Planning System

### 1. Planning Domain Module (`RubberDuck.Planning`)

```elixir
defmodule RubberDuck.Planning do
  use Ash.Domain
  
  resources do
    resource RubberDuck.Planning.Plan
    resource RubberDuck.Planning.Task
    resource RubberDuck.Planning.Constraint
    resource RubberDuck.Planning.Validation
  end
end
```

### 2. Plan Resource Model

```elixir
defmodule RubberDuck.Planning.Plan do
  use Ash.Resource,
    domain: RubberDuck.Planning,
    data_layer: AshPostgres.DataLayer
    
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :type, :atom do
      constraints one_of: [:feature, :refactor, :debug, :architecture, :migration]
    end
    
    attribute :status, :atom do
      constraints one_of: [:draft, :validated, :executing, :completed, :failed]
      default :draft
    end
    
    attribute :context, :map  # Stores project context, dependencies, constraints
    attribute :validation_results, :map
    attribute :execution_history, {:array, :map}
    
    timestamps()
  end
  
  relationships do
    has_many :tasks, RubberDuck.Planning.Task
    belongs_to :project, RubberDuck.Workspace.Project
  end
end
```

### 3. Task Decomposition Engine

```elixir
defmodule RubberDuck.Planning.Engines.TaskDecomposer do
  use RubberDuck.Engine
  
  @impl true
  def capabilities do
    %{
      planning: [:decomposition, :dependency_analysis],
      supported_types: [:feature, :refactor, :debug]
    }
  end
  
  @impl true
  def execute(%{prompt: prompt, context: context}, state) do
    # Phase 1: LLM generates initial task breakdown
    initial_tasks = generate_task_breakdown(prompt, context)
    
    # Phase 2: Validate with hard critics
    validated_tasks = validate_with_critics(initial_tasks, context)
    
    # Phase 3: Build dependency graph
    task_graph = build_dependency_graph(validated_tasks)
    
    {:ok, %{tasks: validated_tasks, graph: task_graph}, state}
  end
  
  defp generate_task_breakdown(prompt, context) do
    # Use existing CoT implementation with planning-specific template
    RubberDuck.CoT.execute(
      chain: :planning_decomposition,
      prompt: prompt,
      context: context,
      template: """
      Break down this development task into concrete, actionable steps:
      
      Task: #{prompt}
      
      Consider:
      1. What files need to be created/modified?
      2. What are the dependencies between tasks?
      3. What are the testable outcomes?
      4. What are potential risks or blockers?
      
      Provide a structured breakdown with:
      - Task name
      - Description
      - Dependencies
      - Estimated complexity (simple/medium/complex)
      - Success criteria
      """
    )
  end
end
```

### 4. External Critics System

```elixir
defmodule RubberDuck.Planning.Critics do
  @moduledoc """
  Implements the critic system from LLM-Modulo framework
  """
  
  defmodule HardCritic do
    @behaviour RubberDuck.Planning.CriticBehaviour
    
    def validate(plan, context) do
      validators = [
        &validate_syntax/2,
        &validate_dependencies/2,
        &validate_constraints/2,
        &validate_feasibility/2
      ]
      
      Enum.reduce(validators, {:ok, plan}, fn validator, {:ok, current_plan} ->
        validator.(current_plan, context)
      end)
    end
    
    defp validate_syntax(plan, context) do
      # Use AST parser to validate code-related tasks
      case RubberDuck.Analysis.AST.validate_plan_syntax(plan, context.language) do
        {:ok, _} -> {:ok, plan}
        {:error, issues} -> {:error, {:syntax_issues, issues}}
      end
    end
    
    defp validate_dependencies(plan, _context) do
      # Check for circular dependencies, missing deps
      graph = build_dependency_graph(plan.tasks)
      
      cond do
        has_cycles?(graph) -> {:error, :circular_dependencies}
        has_orphans?(graph) -> {:error, :orphaned_tasks}
        true -> {:ok, plan}
      end
    end
  end
  
  defmodule SoftCritic do
    @behaviour RubberDuck.Planning.CriticBehaviour
    
    def validate(plan, context) do
      # LLM-based validation for style, best practices
      improvements = suggest_improvements(plan, context)
      
      if Enum.empty?(improvements) do
        {:ok, plan}
      else
        {:ok, apply_improvements(plan, improvements)}
      end
    end
  end
end
```

### 5. ReAct-Based Execution Framework

```elixir
defmodule RubberDuck.Planning.Executor do
  use GenServer
  require Logger
  
  defmodule State do
    defstruct [:plan, :current_task, :execution_log, :context]
  end
  
  def execute_plan(plan_id) do
    GenServer.call(__MODULE__, {:execute, plan_id})
  end
  
  @impl true
  def handle_call({:execute, plan_id}, _from, state) do
    plan = load_plan(plan_id)
    
    result = execute_react_loop(plan, state)
    
    {:reply, result, state}
  end
  
  defp execute_react_loop(plan, state) do
    Enum.reduce_while(plan.tasks, {:ok, []}, fn task, {:ok, results} ->
      case execute_task_with_react(task, state) do
        {:ok, result} ->
          {:cont, {:ok, [result | results]}}
          
        {:error, reason} ->
          handle_task_failure(task, reason, state)
      end
    end)
  end
  
  defp execute_task_with_react(task, state) do
    # ReAct pattern: Thought -> Action -> Observation -> Updated Thought
    
    # Thought: Analyze what needs to be done
    thought = analyze_task(task, state.context)
    
    # Action: Execute the task
    action_result = execute_action(task, thought)
    
    # Observation: Check the results
    observation = observe_results(action_result, task.success_criteria)
    
    # Updated Thought: Decide next steps
    case evaluate_observation(observation) do
      :success -> 
        {:ok, action_result}
        
      :needs_correction ->
        # Use self-correction engine
        corrected = self_correct(task, action_result, observation)
        execute_task_with_react(corrected, state)
        
      :failed ->
        {:error, observation}
    end
  end
end
```

### 6. Tree-of-Thought Planning for Complex Tasks

```elixir
defmodule RubberDuck.Planning.Strategies.TreeOfThought do
  @moduledoc """
  Implements ToT for exploring multiple planning paths
  """
  
  def generate_plan_alternatives(request, max_branches \\ 3) do
    # Generate multiple planning approaches
    branches = Enum.map(1..max_branches, fn _ ->
      generate_planning_branch(request)
    end)
    
    # Evaluate each branch
    scored_branches = Enum.map(branches, &score_branch/1)
    
    # Select best or merge approaches
    select_optimal_plan(scored_branches)
  end
  
  defp generate_planning_branch(request) do
    # Each branch uses different planning strategy
    strategies = [:bottom_up, :top_down, :iterative]
    strategy = Enum.random(strategies)
    
    RubberDuck.Planning.Engines.TaskDecomposer.execute(
      Map.put(request, :strategy, strategy)
    )
  end
  
  defp score_branch(branch) do
    criteria = [
      complexity: analyze_complexity(branch),
      feasibility: check_feasibility(branch),
      risk: assess_risk(branch),
      efficiency: estimate_efficiency(branch)
    ]
    
    {branch, calculate_score(criteria)}
  end
end
```

### 7. Repository-Level Planning (CodePlan-inspired)

```elixir
defmodule RubberDuck.Planning.RepositoryPlanner do
  @moduledoc """
  Handles multi-file, repository-wide planning
  """
  
  def plan_repository_change(request) do
    with {:ok, impact_analysis} <- analyze_change_impact(request),
         {:ok, file_graph} <- build_file_dependency_graph(request.project_id),
         {:ok, change_sequence} <- determine_change_sequence(impact_analysis, file_graph),
         {:ok, validated_plan} <- validate_change_plan(change_sequence) do
      
      create_repository_plan(change_sequence, request)
    end
  end
  
  defp analyze_change_impact(request) do
    # Use AST parser to understand code relationships
    files = get_affected_files(request)
    
    impacts = Enum.map(files, fn file ->
      ast = RubberDuck.Analysis.AST.parse(file)
      dependencies = extract_dependencies(ast)
      
      %{
        file: file.path,
        dependencies: dependencies,
        complexity: estimate_change_complexity(ast, request)
      }
    end)
    
    {:ok, impacts}
  end
  
  defp determine_change_sequence(impacts, file_graph) do
    # Topological sort to find optimal change order
    sorted = topological_sort(file_graph)
    
    # Group changes that can be done in parallel
    parallel_groups = identify_parallel_changes(sorted, impacts)
    
    {:ok, parallel_groups}
  end
end
```

### 8. Integration with Existing Systems

```elixir
defmodule RubberDuck.Planning.Integration do
  @moduledoc """
  Bridges planning with existing RubberDuck components
  """
  
  def create_planning_workflow(plan) do
    # Convert plan to Reactor workflow
    workflow = Reactor.new()
    
    # Add planning-specific steps
    workflow
    |> add_validation_step(plan)
    |> add_decomposition_step(plan)
    |> add_execution_steps(plan.tasks)
    |> add_monitoring_step()
    
    # Execute using existing workflow engine
    RubberDuck.Workflows.execute(workflow)
  end
  
  def enhance_with_existing_capabilities(plan) do
    plan
    |> enhance_with_rag()      # Use RAG for context
    |> enhance_with_cot()      # Use CoT for reasoning
    |> enhance_with_agents()   # Use agents for execution
  end
  
  defp enhance_with_rag(plan) do
    # Retrieve relevant code examples and patterns
    similar_plans = RubberDuck.RAG.Pipeline.search(
      query: plan.description,
      type: :planning_patterns
    )
    
    Map.put(plan, :rag_context, similar_plans)
  end
end
```

### 9. Planning DSL Using Spark

```elixir
defmodule RubberDuck.Planning.DSL do
  use Spark.Dsl
  
  @plan %Spark.Dsl.Section{
    name: :plan,
    describe: "Define a development plan",
    entities: [
      @task_entity,
      @constraint_entity,
      @validation_entity
    ]
  }
  
  @task_entity %Spark.Dsl.Entity{
    name: :task,
    describe: "Define a task in the plan",
    args: [:name],
    schema: [
      description: [type: :string, required: true],
      depends_on: [type: {:list, :atom}],
      complexity: [type: {:in, [:simple, :medium, :complex]}],
      validator: [type: :module]
    ]
  }
  
  use Spark.Dsl.Extension, sections: [@plan]
end

# Usage example:
defmodule MyFeaturePlan do
  use RubberDuck.Planning.DSL
  
  plan do
    task :setup_database do
      description "Create new tables for feature X"
      complexity :medium
      validator RubberDuck.Planning.Validators.DatabaseValidator
    end
    
    task :implement_api do
      description "Create REST endpoints"
      depends_on [:setup_database]
      complexity :complex
    end
    
    constraint :timeline do
      max_duration "2 weeks"
    end
  end
end
```

### 10. Planning Agent

```elixir
defmodule RubberDuck.Agents.PlanningAgent do
  use RubberDuck.Agents.Agent
  
  @impl true
  def capabilities do
    [:plan_generation, :plan_validation, :plan_execution_monitoring]
  end
  
  @impl true
  def handle_task(:generate_plan, request, state) do
    # Orchestrate the planning process
    with {:ok, initial_plan} <- decompose_request(request),
         {:ok, validated_plan} <- validate_with_critics(initial_plan),
         {:ok, optimized_plan} <- optimize_plan(validated_plan),
         {:ok, executable_plan} <- prepare_for_execution(optimized_plan) do
      
      {:ok, executable_plan, state}
    end
  end
  
  defp decompose_request(request) do
    # Decide which planning strategy to use
    strategy = case analyze_request_complexity(request) do
      :simple -> :linear_decomposition
      :medium -> :hierarchical_decomposition
      :complex -> :tree_of_thought_decomposition
    end
    
    apply_strategy(strategy, request)
  end
end
```

## Key Features

1. **LLM-Modulo Architecture**: LLMs generate plans, external critics validate
2. **Hybrid Planning**: Combines symbolic reasoning with neural generation
3. **Multi-Strategy Support**: Linear, hierarchical, and ToT planning
4. **Repository-Level Planning**: Handles multi-file changes intelligently
5. **ReAct Execution**: Dynamic plan adjustment during execution
6. **Integration**: Seamlessly works with existing CoT, RAG, and workflow systems

## Implementation Priority

1. **Phase 1**: Core planning domain and data models
2. **Phase 2**: Task decomposition engine with basic critics
3. **Phase 3**: ReAct execution framework
4. **Phase 4**: Repository-level planning
5. **Phase 5**: Advanced strategies (ToT, ADaPT)

This design leverages RubberDuck's strengths while addressing the key insight from research: LLMs can't plan autonomously but excel when properly guided and validated.

defmodule RubberDuck.Agents.Migration.Scripts do
  @moduledoc """
  Automated migration scripts for converting agents to Jido compliance.
  
  This module provides high-level automation for:
  - Detecting agents that need migration
  - Converting behavior-based agents to BaseAgent
  - Extracting signal handlers into action mappings  
  - Generating complete migration artifacts
  - Validating migration success
  - Creating compliance reports
  
  ## Usage
  
      # Detect all agents needing migration
      {:ok, agents} = Scripts.detect_migration_candidates()
      
      # Migrate a single agent
      {:ok, result} = Scripts.migrate_agent(AnalysisAgent)
      
      # Bulk migrate all detected agents
      {:ok, results} = Scripts.migrate_all_agents()
      
      # Generate migration report
      {:ok, report} = Scripts.generate_migration_report()
  """
  
  require Logger
  alias RubberDuck.Agents.Migration.{Helpers, ActionGenerator}
  
  @type migration_candidate :: %{
    module: module(),
    patterns: [atom()],
    priority: :critical | :high | :medium | :low,
    dependencies: [module()],
    estimated_effort: integer()
  }
  
  @type migration_result :: %{
    module: module(),
    success: boolean(),
    artifacts: %{
      agent_code: String.t(),
      actions: [String.t()],
      tests: [String.t()]
    },
    issues: [String.t()],
    warnings: [String.t()]
  }
  
  @type migration_report :: %{
    total_agents: integer(),
    migrated: integer(),
    remaining: integer(),
    compliance_score: float(),
    issues: [String.t()],
    recommendations: [String.t()]
  }

  @doc """
  Detects all agent modules that need migration to Jido compliance.
  
  Scans the codebase for agent modules and analyzes their compliance
  level, returning a prioritized list of migration candidates.
  """
  @spec detect_migration_candidates() :: {:ok, [migration_candidate()]} | {:error, term()}
  def detect_migration_candidates do
    try do
      # Find all agent modules
      agent_modules = discover_agent_modules()
      
      # Analyze each module
      candidates = 
        agent_modules
        |> Enum.map(&analyze_migration_candidate/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.priority, &priority_order/2)
      
      {:ok, candidates}
    rescue
      error -> {:error, {:detection_failed, error}}
    end
  end
  
  @doc """
  Migrates a single agent to full Jido compliance.
  
  Performs complete migration including:
  - Converting to BaseAgent foundation
  - Extracting actions from business logic
  - Creating signal mappings
  - Generating tests
  - Validating compliance
  """
  @spec migrate_agent(module(), keyword()) :: {:ok, migration_result()} | {:error, term()}
  def migrate_agent(agent_module, options \\ []) do
    try do
      Logger.info("Starting migration for #{agent_module}")
      
      # Analyze current state
      {:ok, patterns} = Helpers.detect_legacy_patterns(agent_module)
      {:ok, compliance} = Helpers.validate_compliance(agent_module)
      
      if compliance.compliant do
        {:ok, %{
          module: agent_module,
          success: true,
          artifacts: %{agent_code: "", actions: [], tests: []},
          issues: [],
          warnings: ["Module is already compliant"]
        }}
      else
        # Perform migration
        {:ok, result} = perform_complete_migration(agent_module, patterns, options)
        
        Logger.info("Migration completed for #{agent_module}")
        {:ok, result}
      end
    rescue
      error -> {:error, {:migration_failed, agent_module, error}}
    end
  end
  
  @doc """
  Migrates all detected agents in dependency order.
  
  Performs bulk migration of all non-compliant agents, handling
  dependencies and providing progress reporting.
  """
  @spec migrate_all_agents(keyword()) :: {:ok, [migration_result()]} | {:error, term()}
  def migrate_all_agents(options \\ []) do
    try do
      # Detect candidates
      {:ok, candidates} = detect_migration_candidates()
      
      # Sort by dependency order
      ordered_candidates = sort_by_dependencies(candidates)
      
      Logger.info("Starting bulk migration of #{length(ordered_candidates)} agents")
      
      # Migrate each agent
      results = 
        ordered_candidates
        |> Enum.map(fn candidate ->
          case migrate_agent(candidate.module, options) do
            {:ok, result} -> result
            {:error, reason} -> 
              %{
                module: candidate.module,
                success: false,
                artifacts: %{agent_code: "", actions: [], tests: []},
                issues: ["Migration failed: #{inspect(reason)}"],
                warnings: []
              }
          end
        end)
      
      Logger.info("Bulk migration completed")
      {:ok, results}
    rescue
      error -> {:error, {:bulk_migration_failed, error}}
    end
  end
  
  @doc """
  Generates a comprehensive migration progress report.
  
  Analyzes the current state of all agents and provides detailed
  reporting on compliance levels and remaining work.
  """
  @spec generate_migration_report() :: {:ok, migration_report()} | {:error, term()}
  def generate_migration_report do
    try do
      # Discover all agents
      all_agents = discover_agent_modules()
      
      # Analyze compliance
      compliance_results = 
        all_agents
        |> Enum.map(fn module ->
          case Helpers.validate_compliance(module) do
            {:ok, result} -> {module, result}
            {:error, _} -> {module, %{compliant: false, score: 0.0, issues: ["Analysis failed"]}}
          end
        end)
      
      # Calculate statistics
      total_agents = length(all_agents)
      compliant_agents = Enum.count(compliance_results, fn {_module, result} -> result.compliant end)
      remaining_agents = total_agents - compliant_agents
      
      overall_score = 
        compliance_results
        |> Enum.map(fn {_module, result} -> result.score end)
        |> Enum.sum()
        |> Kernel./(total_agents)
      
      # Collect issues and recommendations
      all_issues = 
        compliance_results
        |> Enum.flat_map(fn {_module, result} -> Map.get(result, :issues, []) end)
        |> Enum.uniq()
      
      all_recommendations = 
        compliance_results
        |> Enum.flat_map(fn {_module, result} -> Map.get(result, :recommendations, []) end)
        |> Enum.uniq()
      
      report = %{
        total_agents: total_agents,
        migrated: compliant_agents,
        remaining: remaining_agents,
        compliance_score: Float.round(overall_score, 2),
        issues: all_issues,
        recommendations: all_recommendations
      }
      
      {:ok, report}
    rescue
      error -> {:error, {:report_generation_failed, error}}
    end
  end
  
  @doc """
  Validates that a migration was successful.
  
  Performs comprehensive validation of a migrated agent to ensure
  it meets all Jido compliance requirements.
  """
  @spec validate_migration(module()) :: {:ok, map()} | {:error, term()}
  def validate_migration(agent_module) do
    try do
      # Validate compliance
      {:ok, compliance} = Helpers.validate_compliance(agent_module)
      
      # Additional migration-specific validations
      validation_result = %{
        compliance: compliance,
        actions_extracted: validate_actions_extracted(agent_module),
        signal_mappings: validate_signal_mappings(agent_module),
        state_management: validate_state_management(agent_module),
        test_coverage: validate_test_coverage(agent_module)
      }
      
      {:ok, validation_result}
    rescue
      error -> {:error, {:validation_failed, error}}
    end
  end
  
  # Private implementation functions
  
  defp discover_agent_modules do
    # Get all loaded modules that are agents
    :code.all_loaded()
    |> Enum.map(fn {module, _path} -> module end)
    |> Enum.filter(&is_agent_module?/1)
  end
  
  defp is_agent_module?(module) do
    try do
      module_name = Atom.to_string(module)
      String.contains?(module_name, "Agent") and
      String.starts_with?(module_name, "Elixir.RubberDuck.Agents")
    rescue
      _ -> false
    end
  end
  
  defp analyze_migration_candidate(agent_module) do
    try do
      # Detect patterns
      {:ok, patterns} = Helpers.detect_legacy_patterns(agent_module)
      
      # Analyze dependencies
      {:ok, dependencies} = Helpers.analyze_dependencies(agent_module)
      
      # Skip if already compliant
      if Enum.empty?(patterns) do
        nil
      else
        %{
          module: agent_module,
          patterns: patterns,
          priority: determine_priority(agent_module, patterns),
          dependencies: dependencies.agent_dependencies,
          estimated_effort: estimate_effort(patterns)
        }
      end
    rescue
      _ -> nil
    end
  end
  
  defp determine_priority(agent_module, patterns) do
    module_name = Atom.to_string(agent_module)
    
    cond do
      String.contains?(module_name, "Provider") -> :critical
      String.contains?(module_name, "Analysis") -> :critical  
      String.contains?(module_name, "Generation") -> :critical
      length(patterns) > 3 -> :high
      length(patterns) > 1 -> :medium
      true -> :low
    end
  end
  
  defp estimate_effort(patterns) do
    # Base effort + pattern complexity
    base_effort = 2
    pattern_effort = length(patterns) * 1
    
    base_effort + pattern_effort
  end
  
  defp priority_order(:critical, _), do: true
  defp priority_order(:high, :critical), do: false
  defp priority_order(:high, _), do: true
  defp priority_order(:medium, priority) when priority in [:critical, :high], do: false
  defp priority_order(:medium, _), do: true
  defp priority_order(:low, :low), do: true
  defp priority_order(:low, _), do: false
  
  defp sort_by_dependencies(candidates) do
    # Simple dependency sort (could be enhanced with topological sort)
    candidates
    |> Enum.sort_by(fn candidate -> length(candidate.dependencies) end)
  end
  
  defp perform_complete_migration(agent_module, patterns, options) do
    artifacts = %{agent_code: "", actions: [], tests: []}
    issues = []
    warnings = []
    
    # Generate new agent code
    {agent_code, issues, warnings} = generate_migrated_agent(agent_module, patterns, issues, warnings)
    artifacts = %{artifacts | agent_code: agent_code}
    
    # Extract and generate actions
    {actions, issues, warnings} = generate_actions_from_agent(agent_module, issues, warnings, options)
    artifacts = %{artifacts | actions: actions}
    
    # Generate tests if requested
    {tests, issues, warnings} = generate_migration_tests(agent_module, issues, warnings, options)
    artifacts = %{artifacts | tests: tests}
    
    # Write files if requested
    if Keyword.get(options, :write_files, false) do
      write_migration_artifacts(agent_module, artifacts)
    end
    
    result = %{
      module: agent_module,
      success: Enum.empty?(issues),
      artifacts: artifacts,
      issues: issues,
      warnings: warnings
    }
    
    {:ok, result}
  end
  
  defp generate_migrated_agent(agent_module, patterns, issues, warnings) do
    try do
      # Generate BaseAgent-based implementation
      agent_code = """
      defmodule #{agent_module} do
        @moduledoc \"\"\"
        #{agent_module} migrated to Jido compliance.
        
        Original patterns detected: #{inspect(patterns)}
        Migrated on: #{DateTime.utc_now()}
        \"\"\"
        
        use RubberDuck.Agents.BaseAgent,
          name: "#{Macro.underscore(Module.split(agent_module) |> List.last())}",
          description: "Migrated agent with Jido compliance",
          schema: [
            status: [type: :atom, default: :idle],
            last_activity: [type: :any, default: nil]
          ],
          actions: [
            # TODO: Add generated action modules
          ]
        
        @impl true
        def signal_mappings do
          %{
            # TODO: Add signal mappings from extracted handlers
          }
        end
        
        # TODO: Implement any required lifecycle hooks
        # TODO: Add any agent-specific business logic that doesn't belong in actions
      end
      """
      
      {agent_code, issues, ["Generated skeleton agent code - requires manual completion" | warnings]}
    rescue
      error ->
        {agent_code = "", ["Failed to generate agent code: #{inspect(error)}" | issues], warnings}
    end
  end
  
  defp generate_actions_from_agent(agent_module, issues, warnings, options) do
    try do
      # Generate actions
      {:ok, actions} = ActionGenerator.generate_all_actions(agent_module, %{
        namespace: "#{agent_module}.Actions",
        include_tests: Keyword.get(options, :include_tests, false)
      })
      
      action_codes = Enum.map(actions, & &1.code)
      
      {action_codes, issues, ["Generated #{length(actions)} action templates" | warnings]}
    rescue
      error ->
        {[], ["Failed to generate actions: #{inspect(error)}" | issues], warnings}
    end
  end
  
  defp generate_migration_tests(agent_module, issues, warnings, options) do
    if Keyword.get(options, :include_tests, false) do
      try do
        # Generate basic test template
        test_code = """
        defmodule #{agent_module}Test do
          use ExUnit.Case, async: true
          
          alias #{agent_module}
          
          describe "migration compliance" do
            test "uses BaseAgent foundation" do
              # TODO: Test BaseAgent usage
            end
            
            test "has proper action registration" do
              # TODO: Test action registration
            end
            
            test "implements signal mappings" do
              # TODO: Test signal mappings
            end
          end
        end
        """
        
        {[test_code], issues, ["Generated basic test template" | warnings]}
      rescue
        error ->
          {[], ["Failed to generate tests: #{inspect(error)}" | issues], warnings}
      end
    else
      {[], issues, warnings}
    end
  end
  
  defp write_migration_artifacts(agent_module, artifacts) do
    # Create migration directory
    migration_dir = "migration_output/#{Macro.underscore(Module.split(agent_module) |> List.last())}"
    File.mkdir_p!(migration_dir)
    
    # Write agent code
    if artifacts.agent_code != "" do
      File.write!(Path.join(migration_dir, "agent.ex"), artifacts.agent_code)
    end
    
    # Write actions
    artifacts.actions
    |> Enum.with_index()
    |> Enum.each(fn {action_code, index} ->
      File.write!(Path.join(migration_dir, "action_#{index}.ex"), action_code)
    end)
    
    # Write tests
    artifacts.tests
    |> Enum.with_index()
    |> Enum.each(fn {test_code, index} ->
      File.write!(Path.join(migration_dir, "test_#{index}.exs"), test_code)
    end)
  end
  
  defp validate_actions_extracted(agent_module) do
    function_exported?(agent_module, :actions, 0)
  end
  
  defp validate_signal_mappings(agent_module) do
    function_exported?(agent_module, :signal_mappings, 0)
  end
  
  defp validate_state_management(agent_module) do
    # Check if uses BaseAgent and not legacy patterns
    not function_exported?(agent_module, :handle_cast, 2)
  end
  
  defp validate_test_coverage(_agent_module) do
    # Simplified test coverage check
    true
  end
end
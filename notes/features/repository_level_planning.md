# Repository-Level Planning System

**Status**: Implemented ✅  
**Branch**: `feature/repository-planning`  
**Section**: 7.5 - Repository-Level Planning  

## Overview

The Repository-Level Planning System provides sophisticated analysis and planning capabilities for multi-file changes across an entire Elixir repository. This system enables intelligent sequencing, impact analysis, and execution of complex changes that span multiple modules and dependencies.

## Key Features

### 1. Repository Analysis (`RepositoryAnalyzer`)
- **AST-based code analysis** using Sourceror for parsing Elixir code
- **Module dependency detection** through imports, aliases, and uses
- **Architectural pattern recognition** (Phoenix contexts, OTP applications, umbrella projects)
- **Project structure analysis** (Mix projects, dependencies, config files)
- **Test file association** mapping implementation files to their tests

### 2. Dependency Graph Management (`DependencyGraph`)
- **Directed graph construction** using `:digraph` for file dependencies
- **Topological sorting** for compilation order determination
- **Cycle detection** to identify circular dependencies
- **Transitive dependency analysis** for impact assessment
- **Graph metrics calculation** for complexity analysis
- **DOT format export** for visualization

### 3. Change Impact Analysis (`ChangeImpactAnalyzer`)
- **Multi-level impact assessment** (direct, transitive, test dependencies)
- **Risk assessment with confidence scoring** based on:
  - High complexity files
  - Number of dependents
  - Core module changes
  - Test coverage gaps
  - Breaking changes
- **Effort estimation** based on complexity and file count
- **Mitigation strategy suggestions** for high-risk changes
- **Change propagation simulation** showing step-by-step impact

### 4. Change Sequencing (`ChangeSequencer`)
- **Dependency-aware ordering** respecting compilation dependencies
- **Conflict detection and resolution** for overlapping changes
- **Parallel execution identification** for independent changes
- **Validation point planning** with configurable strategies (aggressive, conservative, minimal)
- **Rollback plan generation** with checkpoints and recovery procedures
- **Resource requirement analysis** for parallel execution

### 5. Repository Planning (`RepositoryPlanner`)
- **Unified planning interface** coordinating all analysis components
- **Execution plan conversion** to Ash Plan resources
- **ReAct framework integration** for intelligent execution
- **Change preview generation** with detailed impact summaries
- **Plan validation** with comprehensive checks
- **Optimization suggestions** for improved execution

## Architecture

```
RepositoryPlanner (Main Interface)
├── RepositoryAnalyzer (AST Analysis)
│   └── DependencyGraph (Graph Management)
├── ChangeImpactAnalyzer (Risk Assessment)
└── ChangeSequencer (Execution Planning)
```

## Integration Points

### With Existing Planning System
- Converts repository plans to standard Ash `Plan` resources
- Creates executable `Task` resources for each phase
- Integrates with existing validation and execution infrastructure

### With ReAct Execution Framework
- Provides intelligent plan execution through `PlanExecutor`
- Supports parallel execution for independent changes
- Enables dynamic plan adjustment based on execution results

## API Usage

### Creating a Repository Plan

```elixir
# Define changes to be made
changes = [
  %{
    id: "feature_auth",
    name: "Add authentication system",
    description: "Implement user authentication with sessions",
    files: ["lib/auth.ex", "lib/auth/session.ex"],
    type: :feature,
    priority: :high,
    dependencies: [],
    estimated_effort: 8.0,
    breaking: false,
    validation_required: true
  }
]

# Create repository plan
{:ok, plan} = RepositoryPlanner.create_plan(
  "/path/to/project",
  "Authentication Feature Implementation",
  changes,
  description: "Complete authentication system with sessions and security"
)
```

### Analyzing Change Impact

```elixir
# Analyze impact of changing specific files
{:ok, impact} = ChangeImpactAnalyzer.analyze_impact(
  repository_analysis,
  ["lib/core_module.ex"]
)

# Check risk assessment
case impact.risk_assessment.overall_risk do
  :critical -> "Implement extensive testing and staged rollout"
  :high -> "Increase test coverage and code review rigor"
  :medium -> "Standard testing procedures sufficient"
  :low -> "Minimal risk, proceed with normal workflow"
end
```

### Validating and Executing Plans

```elixir
# Validate plan before execution
case RepositoryPlanner.validate_plan(plan) do
  {:ok, validations} -> 
    # All validations passed
    {:ok, execution_plan} = RepositoryPlanner.convert_to_execution_plan(plan)
    {:ok, executor_pid} = RepositoryPlanner.execute_plan(execution_plan)
  
  {:error, {:validation_failed, errors}} ->
    # Handle validation errors
    IO.inspect(errors, label: "Validation Errors")
end
```

### Previewing Changes

```elixir
{:ok, preview} = RepositoryPlanner.preview_changes(plan)

IO.puts "Total changes: #{preview.summary.total_changes}"
IO.puts "Files affected: #{preview.summary.files_affected}"
IO.puts "Estimated effort: #{preview.estimated_effort.estimated_hours} hours"

# Show execution phases
Enum.each(preview.phases, fn phase ->
  IO.puts "Phase #{phase.phase}: #{phase.name}"
  IO.puts "  Files: #{Enum.join(phase.files, ", ")}"
  IO.puts "  Parallel: #{phase.can_parallel}"
end)
```

## Risk Assessment Factors

The system identifies and assesses various risk factors:

### High Complexity Files
- Files with many functions, modules, or lines of code
- **Mitigation**: Increase testing and code review rigor

### Many Dependents
- Changes affecting large numbers of dependent files
- **Mitigation**: Staged deployment, incremental rollout

### Core Module Changes
- Modifications to architectural components
- **Mitigation**: Comprehensive testing, documentation updates

### Test Coverage Gaps
- Changes to files with insufficient test coverage
- **Mitigation**: Add tests before implementing changes

### Breaking Changes
- API modifications that affect dependent code
- **Mitigation**: Backward compatibility layers, feature flags

## Validation Strategies

### Aggressive Validation
- Validates after every phase
- Maximum safety with higher execution time
- Recommended for critical systems

### Conservative Validation (Default)
- Validates at key checkpoints and phase boundaries
- Balances safety with execution efficiency
- Suitable for most production systems

### Minimal Validation
- Validates only at the end
- Fastest execution with minimal safety checks
- Appropriate for development environments

## Optimization Suggestions

The system provides intelligent optimization recommendations:

### Change Grouping
- Identifies opportunities to group related changes
- Reduces coordination overhead
- Improves execution efficiency

### Parallel Execution
- Detects independent changes that can run simultaneously
- Significantly reduces total execution time
- Considers resource requirements and conflicts

### Risk Mitigation
- Suggests specific strategies based on identified risks
- Provides implementation guidance
- Estimates effort and effectiveness

## Testing

Comprehensive test suite covers:

- **Repository analysis** with real project structures
- **Dependency graph construction** and operations
- **Impact analysis** with various risk scenarios
- **Change sequencing** with conflict resolution
- **Plan validation** and error detection
- **Integration testing** with mock Ash resources

Tests include edge cases like:
- Circular dependencies
- Parse errors in source files
- Missing files and broken dependencies
- Complex multi-file changes
- Resource conflicts in parallel execution

## Performance Considerations

### Memory Management
- Explicit cleanup of `:digraph` resources
- Efficient AST parsing with Sourceror
- Streaming analysis for large repositories

### Scalability
- Handles repositories with hundreds of files
- Efficient topological sorting algorithms
- Parallel analysis where possible

### Caching
- Repository analysis results can be cached
- Dependency graphs persist across planning sessions
- Impact analysis reuses computation where possible

## Future Enhancements

### Machine Learning Integration
- Learn from execution outcomes to improve risk assessment
- Predict effort estimates based on historical data
- Optimize sequencing based on past performance

### Advanced Conflict Resolution
- Intelligent merge strategies for overlapping changes
- Automated conflict resolution for common patterns
- Interactive conflict resolution UI

### IDE Integration
- Real-time impact analysis during development
- Live dependency visualization
- Integrated planning and execution tools

### Distributed Execution
- Support for distributed change execution
- Cross-service dependency management
- Microservice-aware planning

## Configuration

### Analysis Options
```elixir
opts = [
  patterns: ["**/*.ex", "**/*.exs"],           # File patterns to analyze
  exclude: ["_build/**", "deps/**"],          # Patterns to exclude
  validation_strategy: :conservative,         # Validation frequency
  max_parallel: 4                            # Maximum parallel execution
]
```

### Risk Thresholds
```elixir
risk_config = [
  complexity_threshold: :complex,             # Files above this are high-risk
  dependency_threshold: 20,                   # Max dependents before high-risk
  test_coverage_minimum: 0.6                 # Minimum test coverage ratio
]
```

## Troubleshooting

### Common Issues

**Parse Errors**: Files with syntax errors are handled gracefully, logged as warnings, and given minimal complexity scores.

**Missing Dependencies**: The system continues analysis when dependencies are missing, marking them as external dependencies.

**Circular Dependencies**: Detected and reported, but don't prevent plan creation. The system suggests resolution strategies.

**Resource Conflicts**: Parallel execution conflicts are detected and resolved through sequential ordering with clear explanations.

### Debugging

Enable detailed logging:
```elixir
Logger.configure(level: :debug)
```

Check validation results:
```elixir
{:ok, validations} = RepositoryPlanner.validate_plan(plan)
Enum.each(validations, &IO.inspect(&1, label: "Validation"))
```

## Conclusion

The Repository-Level Planning System provides a sophisticated foundation for managing complex, multi-file changes in Elixir projects. By combining static analysis, risk assessment, and intelligent sequencing, it enables safe and efficient execution of large-scale code modifications while maintaining system reliability and developer productivity.

The system's modular architecture allows for easy extension and customization, making it suitable for a wide range of development workflows and project requirements.
# Feature: Analysis Agent Migration to Jido Compliance (16.2.2)

## Overview
Migrate the AnalysisAgent from legacy `RubberDuck.Agents.Behavior` pattern to fully Jido-compliant `BaseAgent` architecture with action-based operations.

## Current State Analysis

### Current Implementation
- **Pattern**: Uses `RubberDuck.Agents.Behavior` (legacy)
- **Location**: `/lib/rubber_duck/agents/analysis_agent.ex`
- **Capabilities**: code_analysis, security_analysis, complexity_analysis, pattern_detection, style_checking
- **Task Types**: analyze_code, security_review, complexity_analysis, pattern_detection, style_check
- **Dependencies**: 
  - RubberDuck.Analysis.{Semantic, Style, Security}
  - RubberDuck.SelfCorrection.Engine

### Issues Identified
1. Uses legacy Behavior pattern instead of Jido.Agent
2. Direct task handling in `handle_task/3` callbacks
3. No action-based architecture
4. State management through GenServer patterns
5. No schema validation via NimbleOptions
6. Mixed business logic with agent infrastructure

## Migration Plan

### Phase 1: Create Analysis Actions (16.2.2.2)

#### CodeAnalysisAction
- **Purpose**: Comprehensive code analysis across multiple dimensions
- **Functionality**:
  - Semantic analysis
  - Style checking
  - Security scanning
  - Incremental analysis support
  - Cache management
  - Self-correction integration
- **Schema**:
  - file_path: [required]
  - analysis_types: [:semantic, :style, :security]
  - enable_cache: [default: true]
  - apply_self_correction: [default: true]

#### ComplexityAnalysisAction
- **Purpose**: Calculate and report code complexity metrics
- **Functionality**:
  - Cyclomatic complexity calculation
  - Cognitive complexity measurement
  - Halstead metrics
  - Module-level analysis
  - Threshold-based recommendations
- **Schema**:
  - module_path: [required]
  - metrics: [:cyclomatic, :cognitive, :halstead]
  - include_recommendations: [default: true]

#### PatternDetectionAction  
- **Purpose**: Identify code patterns and anti-patterns
- **Functionality**:
  - Positive pattern recognition (best practices)
  - Anti-pattern detection
  - Codebase-wide scanning
  - Pattern suggestions generation
  - Confidence scoring
- **Schema**:
  - codebase_path: [required]
  - pattern_types: [:all]
  - include_suggestions: [default: true]

#### SecurityReviewAction
- **Purpose**: Comprehensive security vulnerability detection
- **Functionality**:
  - Multi-file security scanning
  - Vulnerability categorization
  - Severity assessment
  - Security recommendations
  - Issue prioritization
- **Schema**:
  - file_paths: [required]
  - vulnerability_types: [:all]
  - severity_threshold: [:low]

#### StyleCheckAction
- **Purpose**: Code style and formatting verification
- **Functionality**:
  - Style rule enforcement
  - Auto-fixable violation detection
  - Multi-file checking
  - Violation summarization
  - Rule customization
- **Schema**:
  - file_paths: [required]
  - style_rules: [:default]
  - detect_auto_fixable: [default: true]

### Phase 2: Convert AnalysisAgent (16.2.2.1)

#### Agent Migration Steps
1. Replace `use RubberDuck.Agents.Behavior` with `use RubberDuck.Agents.BaseAgent`
2. Define proper NimbleOptions schema
3. Register all Analysis Actions
4. Remove direct handle_task callbacks
5. Implement signal-to-action mappings
6. Convert state management to Jido patterns

#### New Agent Structure
```elixir
defmodule RubberDuck.Agents.AnalysisAgent do
  use RubberDuck.Agents.BaseAgent,
    name: "analysis_agent",
    description: "Code analysis and quality assessment agent",
    schema: [
      analysis_cache: [type: :map, default: %{}],
      engines: [type: :map, default: %{}],
      metrics: [type: :map, default: %{}],
      last_activity: [type: :datetime],
      enable_self_correction: [type: :boolean, default: true],
      cache_ttl_seconds: [type: :integer, default: 3600]
    ],
    actions: [
      CodeAnalysisAction,
      ComplexityAnalysisAction,
      PatternDetectionAction,
      SecurityReviewAction,
      StyleCheckAction
    ]
end
```

### Phase 3: Testing and Validation

#### Test Coverage Requirements
1. Unit tests for each Action
2. Integration tests for AnalysisAgent workflows
3. Signal routing verification
4. Cache functionality tests
5. Self-correction integration tests
6. Performance benchmarks

#### Validation Checklist
- [ ] All task types converted to Actions
- [ ] No direct handle_task callbacks remain
- [ ] Schema validation working
- [ ] Signal routing functional
- [ ] Cache management preserved
- [ ] Self-correction still works
- [ ] Metrics collection operational
- [ ] Engine initialization correct

## Implementation Notes

### Action Design Principles
1. **Pure Functions**: Actions should be stateless and return tagged tuples
2. **Schema Validation**: All parameters validated via NimbleOptions
3. **Error Handling**: Comprehensive error handling with descriptive messages
4. **Logging**: Appropriate logging at info/debug/error levels
5. **Performance**: Efficient implementation with caching where appropriate

### State Management
- Analysis cache migrated to agent state
- Engine configuration in agent initialization
- Metrics tracked through action execution
- Last activity timestamp auto-updated

### Backward Compatibility
- No backward compatibility required (clean break approach)
- All consumers will need to use new signal-based interface
- Documentation updates required for API changes

## Success Metrics
1. All 5 Analysis Actions implemented and tested
2. AnalysisAgent fully migrated to BaseAgent
3. 100% test coverage for new components
4. Performance regression < 5%
5. Zero legacy Behavior patterns remaining

## Risk Mitigation
1. **Risk**: Breaking existing analysis workflows
   - **Mitigation**: Comprehensive integration testing
   
2. **Risk**: Performance degradation from action overhead
   - **Mitigation**: Performance benchmarks and optimization
   
3. **Risk**: Cache invalidation issues
   - **Mitigation**: TTL-based cache with proper key management

## Timeline
- Action Implementation: 2 hours
- Agent Migration: 1 hour  
- Testing: 1 hour
- Documentation: 30 minutes
- Total: ~4.5 hours

## Dependencies
- RubberDuck.Agents.BaseAgent (already compliant)
- Jido.Action framework
- NimbleOptions for schema validation
- Existing analysis engines (Semantic, Style, Security)

## Post-Migration Tasks
1. Update API documentation
2. Update consumer agents to use new signal interface
3. Remove deprecated Behavior module references
4. Performance monitoring in production
5. Mark section 16.2.2 as completed in planning document
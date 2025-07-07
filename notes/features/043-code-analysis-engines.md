# Feature: Code Analysis Engines

## Summary
Implement various analysis engines that can be composed into workflows for comprehensive code analysis. This includes semantic analysis (dead code, complexity metrics), style analysis (formatting, naming conventions, code smells), and security analysis (vulnerabilities, hardcoded secrets).

## Requirements
### Semantic Analysis Module
- [ ] Dead code detection using AST analysis
- [ ] Unused variable and function analysis
- [ ] Complexity metrics (cyclomatic, cognitive)
- [ ] Dependency analysis and cycle detection
- [ ] Module cohesion analysis

### Style Analysis Module
- [ ] Formatting violations detection
- [ ] Naming convention checks
- [ ] Code smell detection based on Elixir-specific patterns
- [ ] Best practice violations
- [ ] Function length and parameter list analysis

### Security Analysis Module
- [ ] SQL injection pattern detection
- [ ] XSS vulnerability scanning
- [ ] Hardcoded secrets and credentials detection
- [ ] Unsafe operations identification
- [ ] Dynamic atom creation detection

### Core Infrastructure
- [ ] Analysis result aggregation across engines
- [ ] Severity level classification system
- [ ] Fix suggestion generation
- [ ] Analysis caching layer
- [ ] Integration with existing AST parser

## Research Summary
### Existing Usage Rules Checked
- Ash Framework: Use resources for domain modeling, actions for business logic
- AST Module: Already provides parsing and traversal utilities
- Self-Correction: Existing pattern for strategy-based analysis

### Documentation Reviewed
- Elixir Code Smells Repository: https://github.com/lucasvegi/Elixir-Code-Smells
  - 33 documented Elixir-specific code smells
  - Categorized into Design-Related, Low-Level Concerns, and Traditional
  - Provides detection patterns and examples

### Existing Patterns Found
- Pattern 1: [lib/rubber_duck/self_correction/strategy.ex] - Strategy behavior for analysis
- Pattern 2: [lib/rubber_duck/analysis/ast/traversal.ex] - AST traversal utilities
- Pattern 3: [lib/rubber_duck/workspace/analysis_result.ex] - Storage for analysis results
- Pattern 4: [lib/rubber_duck/self_correction/strategies/] - Multiple strategy implementations

### Technical Approach
1. **Module Structure**:
   - `RubberDuck.Analysis.Engine` - Base behavior for all analysis engines
   - `RubberDuck.Analysis.Semantic` - Dead code, complexity, dependencies
   - `RubberDuck.Analysis.Style` - Code smells, formatting, naming
   - `RubberDuck.Analysis.Security` - Vulnerabilities, secrets, unsafe patterns
   - `RubberDuck.Analysis.Analyzer` - Orchestrates multiple engines

2. **Detection Strategies**:
   - AST-based pattern matching for structural issues
   - Metrics calculation for complexity and cohesion
   - Regular expressions for security patterns
   - Rule-based detection for style violations

3. **Integration Points**:
   - Use existing AST parser for code structure
   - Store results in AnalysisResult resource
   - Integrate with workflow system for orchestration
   - Cache analysis results by file hash

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| False positives in smell detection | High | Configurable sensitivity levels, whitelisting |
| Performance with large codebases | Medium | Incremental analysis, caching, parallel processing |
| Language-specific rules complexity | Medium | Start with Elixir, extensible architecture |
| Security pattern accuracy | High | Conservative detection, manual review suggestions |

## Implementation Checklist
### Phase 1: Core Infrastructure
- [ ] Create Analysis.Engine behavior
- [ ] Define common result types and severities
- [ ] Implement base analysis utilities
- [ ] Set up caching infrastructure
- [ ] Create fix suggestion system

### Phase 2: Semantic Analysis
- [ ] Implement dead code detection
- [ ] Add unused variable analysis
- [ ] Build complexity calculators
- [ ] Create dependency analyzer
- [ ] Add module cohesion metrics

### Phase 3: Style Analysis  
- [ ] Implement Elixir code smell detectors
- [ ] Add naming convention checks
- [ ] Create formatting violation detection
- [ ] Build function metric analyzers
- [ ] Add best practice checks

### Phase 4: Security Analysis
- [ ] Implement SQL injection detection
- [ ] Add hardcoded secret scanning
- [ ] Create unsafe operation detection
- [ ] Build dynamic atom detection
- [ ] Add vulnerability reporting

### Phase 5: Integration
- [ ] Create Analyzer coordinator
- [ ] Integrate with AST parser
- [ ] Add workflow integration
- [ ] Build comprehensive tests
- [ ] Create documentation

## Questions for Pascal
1. Should we prioritize certain code smells over others based on your experience?
2. Do you want real-time analysis during editing or batch analysis?
3. Should fix suggestions be automatically applicable or just descriptive?
4. What severity levels are most useful for your workflow?
5. Should we integrate with external tools like Credo or build everything custom?

## Log
- Created feature plan document
- Research completed on Elixir code smells
- Identified existing patterns and integration points
- Created feature branch: feature/4.3-code-analysis-engines
- Implemented all analysis engines following TDD approach
- Fixed syntax errors (Ruby-style return statements) in all modules
- All modules now compile successfully
- Tests created for comprehensive coverage

## Implementation Summary

Successfully implemented comprehensive code analysis engines with the following components:

1. **Core Infrastructure**:
   - `Analysis.Engine` behavior defining the interface for all engines
   - `Analysis.Common` module with shared utilities and Elixir code smell definitions
   - Severity levels: info, low, medium, high, critical
   - Fix suggestion system with auto-applicable flags

2. **Analysis Engines**:
   - **Semantic Analysis**: Dead code detection, complexity metrics, dependency analysis, unused variables, module cohesion
   - **Style Analysis**: Elixir-specific code smells, naming conventions, formatting, function organization, coupling metrics
   - **Security Analysis**: Dynamic atom detection, unsafe operations, SQL injection risks, XSS vulnerabilities, hardcoded secrets

3. **Key Features**:
   - AST-based analysis using existing parser infrastructure
   - Source-based fallback when AST is unavailable
   - Parallel engine execution for performance
   - Configurable rules and thresholds
   - Comprehensive issue reporting with location tracking
   - Actionable fix suggestions for common issues
   - Metrics calculation (complexity, security score, naming consistency)

4. **Analyzer Coordinator**:
   - Orchestrates multiple engines
   - Aggregates results across engines
   - Sorts issues by severity and location
   - Provides unified analysis interface
   - Supports file, source, and CodeFile resource analysis

5. **Testing**:
   - Comprehensive test coverage for all engines
   - Tests for issue detection, metrics, suggestions
   - Integration tests for the analyzer coordinator
   - Edge case handling (unparseable code, non-Elixir languages)
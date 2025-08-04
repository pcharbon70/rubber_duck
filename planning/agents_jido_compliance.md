# Agent Jido Compliance Migration Plan

## Phase 16: Complete Agent Jido Compliance Migration

**Goal:** Transform all RubberDuck agents to be fully compliant with Jido framework patterns, ensuring consistent signal handling, action-based architecture, and proper routing throughout the entire system.

### Current State Assessment

Based on comprehensive analysis of 90+ agent files:
- **Fully Compliant**: ~25 agents (28%) - Using `BaseAgent`, proper actions, Jido signals
- **Partially Compliant**: ~35 agents (39%) - Mixed patterns, some Jido features missing
- **Non-Compliant**: ~30 agents (33%) - Legacy patterns, no Jido integration

### Key Deviations Identified

1. **Legacy Behavior Pattern**: Using `RubberDuck.Agents.Behavior` instead of `Jido.Agent`
2. **Direct Signal Handling**: Using `handle_signal/2` callbacks instead of action-based routing
3. **Missing Action Architecture**: No Jido Actions for complex operations
4. **Manual Signal Emission**: Not using `Jido.Signal.Bus.publish` consistently
5. **Direct State Manipulation**: GenServer patterns instead of Jido lifecycle hooks
6. **Missing Schema Validation**: No NimbleOptions parameter validation

---

## 16.1 Foundation and Infrastructure 

### 16.1.1 Update Base Agent Architecture ✅ (Already Compliant)
- [x] `BaseAgent` - Properly uses Jido.Agent foundation
- [x] `BaseToolAgent` - Tool agent foundation with embedded Actions
- [x] Signal routing and lifecycle hooks working correctly
- [x] Schema validation and state management in place

### 16.1.2 Create Migration Utilities ✅
- [x] **16.1.2.1 Create Migration Helper Module**
  - [x] Implement `RubberDuck.Agents.Migration.Helpers`
  - [x] Add behavior pattern detection utilities
  - [x] Create action extraction helpers
  - [x] Implement signal mapping generators
  - [x] Add validation utilities

- [x] **16.1.2.2 Build Action Template Generator**
  - [x] Create `mix jido.gen.action` task
  - [x] Generate action modules from existing functions
  - [x] Add schema inference from function signatures
  - [x] Create test templates
  - [x] Add documentation templates

- [x] **16.1.2.3 Create Agent Migration Scripts**
  - [x] Build automated migration detection
  - [x] Create behavior-to-agent conversion
  - [x] Add signal handler extraction
  - [x] Implement schema generation
  - [x] Create validation and compliance checks

---

## 16.2 High Priority Migrations (Core System Agents)

### 16.2.1 Provider Agent Base Class Migration **CRITICAL** ✅
- [x] **16.2.1.1 Migrate ProviderAgent Base**
  - [x] Convert from custom patterns to `use Jido.Agent` (Already compliant via macro)
  - [x] Extract request handling into Actions (ProviderRequestAction exists)
  - [x] Implement proper signal routing (Already implemented)
  - [x] Add schema validation for provider config (Already implemented)
  - [x] Create lifecycle hooks for provider initialization (Already implemented)

- [x] **16.2.1.2 Create Provider Actions Library**
  - [x] `ProviderRequestAction` - Handle LLM requests (Already exists)
  - [x] `ProviderHealthCheckAction` - Monitor provider health with provider-specific metrics
  - [x] `ProviderConfigUpdateAction` - Update provider settings dynamically
  - [x] `ProviderRateLimitAction` - Handle rate limiting with auto-adjustment
  - [x] `ProviderFailoverAction` - Handle provider failures with intelligent recovery

### 16.2.2 Analysis Agent Migration **CRITICAL** ✅
- [x] **16.2.2.1 Convert AnalysisAgent from Behavior**
  - [x] Replace `use RubberDuck.Agents.Behavior` with `use RubberDuck.Agents.BaseAgent`
  - [x] Extract analysis logic into Jido Actions
  - [x] Implement signal-based request handling
  - [x] Add proper schema validation
  - [x] Create caching and state management

- [x] **16.2.2.2 Create Analysis Actions**
  - [x] `CodeAnalysisAction` - Semantic, style, security analysis
  - [x] `ComplexityAnalysisAction` - Code complexity metrics
  - [x] `PatternDetectionActionV2` - Code patterns and anti-patterns (enhanced)
  - [x] `SecurityReviewActionV2` - Security vulnerability detection (enhanced)
  - [x] `StyleCheckActionV2` - Code style verification (enhanced)

### 16.2.3 Generation Agent Migration **CRITICAL** ✅ COMPLETED
- [x] **16.2.3.1 Convert GenerationAgent from Behavior**
  - [x] Replace legacy behavior with `BaseAgent`
  - [x] Extract generation logic into Actions
  - [x] Implement streaming support through signals
  - [x] Add template management and versioning
  - [x] Create quality validation pipeline

- [x] **16.2.3.2 Create Generation Actions**
  - [x] `CodeGenerationAction` - Generate code from specifications
  - [x] `TemplateRenderAction` - Render code templates
  - [x] `QualityValidationAction` - Validate generated code
  - [x] `StreamingGenerationAction` - Streaming code generation
  - [x] `PostProcessingAction` - Format and optimize generated code

---

## 16.3 Medium Priority Migrations (Active Subsystems)

### 16.3.1 Memory and Context Agents ✅ **COMPLETED**
- [x] **16.3.1.1 Migrate ContextBuilderAgent**
  - [x] Remove direct `handle_signal/2` implementations
  - [x] Extract context building into Actions
  - [x] Implement priority-based context assembly
  - [x] Add compression and optimization Actions
  - [x] Create context validation pipeline

- [x] **16.3.1.2 Create Context Actions**
  - [x] `ContextAssemblyAction` - Assemble context from sources
  - [x] `ContextPrioritizationAction` - Prioritize context elements
  - [x] `ContextCompressionAction` - Compress context for size limits
  - [x] `ContextValidationAction` - Validate context quality
  - [x] `ContextCacheAction` - Cache and retrieve contexts
  - [x] `ContextSourceManagementAction` - Manage context sources
  - [x] `ContextConfigurationAction` - Configure priorities and limits

### 16.3.2 Provider Implementation Agents ✅ **COMPLETED**
- [x] **16.3.2.1 Migrate AnthropicProviderAgent**
  - [x] Convert from direct signal handling to Actions
  - [x] Implement Claude-specific features through Actions
  - [x] Add streaming and safety features (`ConfigureSafetyAction`, `VisionRequestAction`)
  - [x] Create context window management (`ContextWindowManagementAction`)
  - [x] Add usage tracking and billing (`UsageTrackingAction`)

- [x] **16.3.2.2 Migrate OpenAIProviderAgent**
  - [x] Convert to action-based architecture
  - [x] Extract model selection logic (`ModelSelectionAction`)
  - [x] Implement usage optimization
  - [x] Add function calling support (`ConfigureFunctionsAction`)
  - [x] Create batch processing capabilities (`BatchProcessingAction`, `StreamRequestAction`)

- [x] **16.3.2.3 Migrate LocalProviderAgent**
  - [x] Convert from GenServer patterns (removed `handle_info` callbacks)
  - [x] Extract model loading into Actions (`LoadModelAction`, `UnloadModelAction`)
  - [x] Implement resource management (`GetResourceStatusAction`)
  - [x] Add performance optimization (`PerformanceOptimizationAction`)
  - [x] Create model switching capabilities (`ModelSwitchingAction`, `ListAvailableModelsAction`)

### 16.3.3 Quality and Enhancement Agents ✅ COMPLETED
- [x] **16.3.3.1 Fix QualityImprovementAgent Mixed Patterns** ✅
  - [x] Remove GenServer callback mixing - Migrated to pure Jido.Agent
  - [x] Extract quality analysis into separate Actions - Created AnalyzeQualityAction
  - [x] Implement improvement strategy selection - Created ApplyImprovementAction
  - [x] Add metrics tracking and reporting - Created TrackMetricsAction & GenerateQualityReportAction
  - [x] Create validation and verification - Created EnforceStandardsAction
  - [x] Fixed typing violations - Removed unreachable error clauses

- [ ] **16.3.3.2 Fix CorrectionStrategyAgent** (Pending - needs separate implementation)
  - [ ] Implement missing Action architecture
  - [ ] Extract strategy selection logic
  - [ ] Add learning and adaptation mechanisms
  - [ ] Create strategy validation
  - [ ] Implement success tracking

---

## 16.4 Low Priority Migrations (Support Systems)

### 16.4.1 Memory Management Agents
- [ ] **16.4.1.1 Fix MemoryCoordinatorAgent**
  - [ ] Remove legacy signal handling
  - [ ] Extract memory operations into Actions
  - [ ] Implement distributed coordination
  - [ ] Add consistency and synchronization
  - [ ] Create memory optimization

- [ ] **16.4.1.2 Fix LongTermMemoryAgent**
  - [ ] Convert mixed patterns to pure Jido
  - [ ] Extract storage operations into Actions
  - [ ] Implement search and indexing
  - [ ] Add archival and compression
  - [ ] Create backup and recovery

### 16.4.2 Workflow and Legacy Agents
- [ ] **16.4.2.1 Migrate RetrievalAgent**
  - [ ] Convert from legacy architecture
  - [ ] Extract retrieval algorithms into Actions
  - [ ] Implement vector and keyword search
  - [ ] Add result ranking and filtering
  - [ ] Create caching and optimization

- [ ] **16.4.2.2 Migrate WorkflowAgent**
  - [ ] Convert from traditional GenServer
  - [ ] Extract workflow execution into Actions
  - [ ] Implement step coordination
  - [ ] Add progress tracking and recovery
  - [ ] Create workflow composition

---

## 16.5 Action Architecture Standardization

### 16.5.1 Create Standard Action Patterns
- [ ] **16.5.1.1 Define Action Categories**
  - [ ] **Request Actions**: Handle external requests with validation
  - [ ] **Processing Actions**: Perform core business logic
  - [ ] **Coordination Actions**: Manage multi-agent workflows
  - [ ] **Monitoring Actions**: Track metrics and health
  - [ ] **Utility Actions**: Common operations (caching, validation)

- [ ] **16.5.1.2 Create Action Base Modules**
  - [ ] `BaseRequestAction` - Common request handling patterns
  - [ ] `BaseProcessingAction` - Processing with error handling
  - [ ] `BaseCoordinationAction` - Multi-step coordination
  - [ ] `BaseMonitoringAction` - Metrics and health checks
  - [ ] `BaseUtilityAction` - Common utility operations

### 16.5.2 Implement Action Composition Patterns
- [ ] **16.5.2.1 Create Workflow Actions**
  - [ ] Sequential action execution
  - [ ] Parallel action execution  
  - [ ] Conditional action branching
  - [ ] Error handling and retry
  - [ ] Error handling and recovery

- [ ] **16.5.2.2 Add Action Middleware**
  - [ ] Logging and telemetry
  - [ ] Authentication and authorization
  - [ ] Rate limiting and throttling
  - [ ] Caching and memoization
  - [ ] Error tracking and recovery

---

## 16.6 Signal Architecture Standardization

### 16.6.1 Create Signal Taxonomy
- [ ] **16.6.1.1 Define Signal Categories**
  - [ ] **Request Signals**: External system requests
  - [ ] **Event Signals**: System state changes
  - [ ] **Command Signals**: Direct action commands
  - [ ] **Query Signals**: Information requests
  - [ ] **Notification Signals**: Status updates

- [ ] **16.6.1.2 Implement Signal Routing Rules**
  - [ ] Pattern-based routing
  - [ ] Priority-based delivery
  - [ ] Load balancing strategies
  - [ ] Failover and retry logic
  - [ ] Dead letter handling

### 16.6.2 Add Signal Processing Pipeline
- [ ] **16.6.2.1 Create Signal Transformers**
  - [ ] Format validation and normalization
  - [ ] Data enrichment and augmentation
  - [ ] Schema validation and enforcement
  - [ ] Security filtering and sanitization
  - [ ] Performance optimization

- [ ] **16.6.2.2 Implement Signal Monitoring**
  - [ ] Delivery tracking and confirmation
  - [ ] Latency and throughput metrics
  - [ ] Error rates and patterns
  - [ ] Queue depth and backpressure
  - [ ] Performance optimization

---

## 16.7 Detailed Agent Migration Analysis

### 16.7.1 Non-Compliant Agents (Require Complete Migration)

#### Legacy Behavior Pattern Agents
1. **`/lib/rubber_duck/agents/analysis_agent.ex`**
   - **Current State**: Uses `RubberDuck.Agents.Behavior`
   - **Issues**: No Jido Actions, no signal handling, traditional GenServer
   - **Migration**: Extract semantic/style/security analysis into Actions
   - **Priority**: CRITICAL (core analysis functionality)

2. **`/lib/rubber_duck/agents/generation_agent.ex`**
   - **Current State**: Uses `RubberDuck.Agents.Behavior`
   - **Issues**: No Jido Actions, no signal handling, traditional GenServer
   - **Migration**: Extract code generation into streaming Actions
   - **Priority**: CRITICAL (core generation functionality)

3. **`/lib/rubber_duck/agents/retrieval_agent.ex`**
   - **Current State**: Legacy architecture
   - **Issues**: No Jido integration, custom patterns
   - **Migration**: Extract retrieval algorithms into Actions
   - **Priority**: MEDIUM (RAG pipeline component)

4. **`/lib/rubber_duck/agents/workflow_agent.ex`**
   - **Current State**: Traditional GenServer
   - **Issues**: No action composition, direct state manipulation
   - **Migration**: Extract workflow execution into Actions
   - **Priority**: LOW (support functionality)

#### Provider Base Class (CRITICAL)
5. **`/lib/rubber_duck/agents/provider_agent.ex`**
   - **Current State**: Custom base without Jido
   - **Issues**: All provider agents inherit non-compliant patterns
   - **Migration**: Convert to `use Jido.Agent` with Actions
   - **Priority**: CRITICAL (affects all LLM providers)

### 16.7.2 Partially Compliant Agents (Need Fixes)

#### Mixed Pattern Agents
1. **`/lib/rubber_duck/agents/context_builder_agent.ex`**
   - **Current State**: Uses BaseAgent but direct signal handling
   - **Issues**: `handle_signal/2` instead of action routing
   - **Migration**: Extract context operations into Actions
   - **Priority**: MEDIUM

2. **`/lib/rubber_duck/agents/correction_strategy_agent.ex`**
   - **Current State**: Uses BaseAgent, missing actions
   - **Issues**: Strategy logic not in Actions
   - **Migration**: Extract strategy selection into Actions
   - **Priority**: MEDIUM

3. **`/lib/rubber_duck/agents/logic_correction_agent.ex`**
   - **Current State**: Uses BaseAgent with direct callbacks
   - **Issues**: Logic analysis not in Actions
   - **Migration**: Extract logic analysis into Actions
   - **Priority**: MEDIUM

4. **`/lib/rubber_duck/agents/quality_improvement_agent.ex`**
   - **Current State**: Mixed GenServer patterns
   - **Issues**: Quality analysis mixed with agent logic
   - **Migration**: Extract quality operations into Actions
   - **Priority**: MEDIUM

5. **`/lib/rubber_duck/agents/memory_coordinator_agent.ex`**
   - **Current State**: Uses BaseAgent but legacy signal handling
   - **Issues**: Memory operations not in Actions
   - **Migration**: Extract memory coordination into Actions
   - **Priority**: MEDIUM

6. **`/lib/rubber_duck/agents/long_term_memory_agent.ex`**
   - **Current State**: Mixed patterns
   - **Issues**: Storage operations not in Actions
   - **Migration**: Extract storage operations into Actions
   - **Priority**: MEDIUM

#### Provider Implementation Agents
7. **`/lib/rubber_duck/agents/anthropic_provider_agent.ex`**
   - **Current State**: Direct signal handling
   - **Issues**: Claude-specific logic not in Actions
   - **Migration**: Extract Claude operations into Actions
   - **Priority**: MEDIUM

8. **`/lib/rubber_duck/agents/openai_provider_agent.ex`**
   - **Current State**: Missing action routing
   - **Issues**: OpenAI logic not in Actions
   - **Migration**: Extract OpenAI operations into Actions
   - **Priority**: MEDIUM

9. **`/lib/rubber_duck/agents/local_provider_agent.ex`**
   - **Current State**: GenServer patterns mixed
   - **Issues**: Model management not in Actions
   - **Migration**: Extract model operations into Actions
   - **Priority**: MEDIUM

### 16.7.3 Fully Compliant Agents (Reference Examples)

#### Foundation Agents ✅
1. **`/lib/rubber_duck/agents/base_agent.ex`** - Perfect Jido compliance
2. **`/lib/rubber_duck/tools/agents/base_tool_agent.ex`** - Excellent action architecture
3. **`/lib/rubber_duck/jido/agents/example_agent.ex`** - Reference implementation

#### Router Agents ✅
4. **`/lib/rubber_duck/agents/llm_router_agent.ex`** - Full action-based routing
5. **`/lib/rubber_duck/agents/conversation_router_agent.ex`** - Proper signal delegation

#### Tool Agents ✅ (25+ agents)
6. **All agents using `BaseToolAgent`** - Properly compliant with embedded Actions

---

## 16.8 Migration Execution Strategy

### 16.8.1 Migration Phases
1. **Phase 1 (Week 1)**: Foundation and utilities
2. **Phase 2 (Week 2-3)**: Critical core agents (Provider, Analysis, Generation)  
3. **Phase 3 (Week 4)**: Active subsystem agents (Memory, Context, Quality)
4. **Phase 4 (Week 5)**: Support and legacy agents
5. **Phase 5 (Week 6)**: Standardization and optimization
6. **Phase 6 (Week 7)**: Validation and testing

### 16.8.2 Migration Process per Agent
- [ ] **16.8.2.1 Assessment and Planning**
  - [ ] Analyze current agent implementation
  - [ ] Identify complete replacement requirements
  - [ ] Plan action extraction strategy
  - [ ] Define signal mapping requirements
  - [ ] Create migration checklist

- [ ] **16.8.2.2 Complete Replacement**
  - [ ] Delete legacy behavior implementation
  - [ ] Extract business logic into Actions
  - [ ] Add schema validation and error handling
  - [ ] Implement proper tagged tuple returns
  - [ ] Create comprehensive test coverage

- [ ] **16.8.2.3 Jido Implementation**
  - [ ] Implement pure `BaseAgent` foundation
  - [ ] Implement action registration
  - [ ] Add signal-to-action routing
  - [ ] Implement Jido state management
  - [ ] Add lifecycle hooks

- [ ] **16.8.2.4 Signal Architecture**
  - [ ] Implement signal-to-action mappings
  - [ ] Add signal emission via Jido.Signal.Bus
  - [ ] Test signal routing and delivery
  - [ ] Validate end-to-end workflows
  - [ ] Remove all direct signal handlers

- [ ] **16.8.2.5 Validation and Testing**
  - [ ] Unit test all actions
  - [ ] Integration test agent workflows
  - [ ] Performance test signal handling
  - [ ] Validate Jido compliance checklist
  - [ ] Document complete migration

### 16.8.3 Migration Templates

#### Template: Legacy Behavior to BaseAgent
```elixir
# BEFORE (Legacy - TO BE DELETED)
defmodule RubberDuck.Agents.AnalysisAgent do
  use RubberDuck.Agents.Behavior
  
  def handle_cast({:analyze, params}, state) do
    result = perform_analysis(params)
    {:noreply, update_state(state, result)}
  end
end

# AFTER (Complete Jido Replacement)
defmodule RubberDuck.Agents.AnalysisAgent do
  use RubberDuck.Agents.BaseAgent,
    name: "analysis_agent",
    schema: [
      status: [type: :atom, default: :idle],
      analysis_cache: [type: :map, default: %{}]
    ],
    actions: [
      RubberDuck.Agents.AnalysisAgent.CodeAnalysisAction,
      RubberDuck.Agents.AnalysisAgent.SecurityAnalysisAction
    ]

  defmodule CodeAnalysisAction do
    use Jido.Action,
      name: "code_analysis",
      description: "Performs comprehensive code analysis",
      schema: [
        file_path: [type: :string, required: true],
        analysis_types: [type: {:list, :atom}, default: [:semantic, :style]]
      ]

    @impl true
    def run(params, context) do
      with {:ok, code} <- File.read(params.file_path),
           {:ok, results} <- perform_analysis(code, params.analysis_types) do
        {:ok, %{results: results, analyzed_at: DateTime.utc_now()}}
      end
    end
  end
end
```

#### Template: Direct Signal Handler to Action Routing
```elixir
# BEFORE (Legacy - TO BE DELETED)
def handle_signal(agent, %{"type" => "analysis.request"} = signal) do
  params = signal["data"]
  result = perform_analysis(params)
  emit_signal(agent, "analysis.complete", result)
  {:ok, agent}
end

# AFTER (Pure Jido Implementation)
def signal_mappings do
  %{
    "analysis.request" => {CodeAnalysisAction, :extract_analysis_params},
    "security.scan" => {SecurityAnalysisAction, :extract_security_params}
  }
end

def extract_analysis_params(%{"data" => data}) do
  %{
    file_path: data["file_path"],
    analysis_types: data["types"] || [:semantic, :style]
  }
end
```

---

## 16.9 Quality Assurance and Validation

### 16.9.1 Compliance Testing Framework
- [ ] **16.9.1.1 Create Compliance Checkers**
  - [ ] Agent compliance validator
  - [ ] Action pattern verifier
  - [ ] Signal routing tester
  - [ ] Schema validation checker
  - [ ] Performance benchmark suite

- [ ] **16.9.1.2 Automated Testing Pipeline**
  - [ ] Pre-migration compliance audit
  - [ ] Post-migration verification
  - [ ] Regression testing suite
  - [ ] Performance impact analysis
  - [ ] Documentation validation

### 16.9.2 Migration Success Metrics
- [ ] **16.9.2.1 Technical Metrics**
  - [ ] 100% agents using `BaseAgent` or `Jido.Agent`
  - [ ] 100% business logic extracted into Actions
  - [ ] 100% signal handling via action routing
  - [ ] 100% schema validation coverage
  - [ ] Zero direct signal handlers remaining

- [ ] **16.9.2.2 Quality Metrics**
  - [ ] Test coverage ≥ 95% for all migrated components
  - [ ] Performance regression < 5%
  - [ ] Zero breaking changes to external APIs
  - [ ] Complete documentation coverage
  - [ ] Zero lint/compliance violations

### 16.9.3 Compliance Checklist Template

#### Agent Compliance Checklist
- [ ] **Foundation**
  - [ ] Uses `use RubberDuck.Agents.BaseAgent` or `use Jido.Agent`
  - [ ] Has proper schema definition with NimbleOptions validation
  - [ ] Implements required callbacks
  - [ ] No direct GenServer callbacks

- [ ] **Actions**
  - [ ] All business logic extracted into Jido Actions
  - [ ] Actions use proper schemas with validation
  - [ ] Actions return tagged tuples (`{:ok, result}` or `{:error, reason}`)
  - [ ] Actions are pure functions where possible

- [ ] **Signals**
  - [ ] No direct `handle_signal/2` implementations
  - [ ] Uses signal-to-action mapping
  - [ ] Emits signals via `Jido.Signal.Bus.publish`
  - [ ] Proper signal routing configuration

- [ ] **State Management**
  - [ ] Uses Jido state management patterns
  - [ ] No direct state manipulation
  - [ ] Proper lifecycle hooks implementation
  - [ ] State validation and error handling

- [ ] **Testing**
  - [ ] Unit tests for all Actions
  - [ ] Integration tests for agent workflows
  - [ ] Signal routing tests
  - [ ] Performance benchmarks

---

## 16.10 Implementation Notes

### Architecture Benefits Post-Migration
- **Consistency**: All agents follow identical Jido patterns
- **Maintainability**: Standard action architecture across system
- **Testability**: Actions are pure functions, easily tested
- **Scalability**: Proper OTP supervision and signal routing
- **Observability**: Built-in metrics and monitoring through Jido
- **Composability**: Actions can be reused across agents

### Migration Strategy
- **Clean Break Approach**: Complete replacement of legacy patterns with Jido implementations
- **Aggressive Migration**: Replace entire agent implementations without legacy fallbacks
- **Breaking Changes Accepted**: Modernization takes priority over API preservation
- **Performance Monitoring**: Track metrics throughout migration
- **Documentation**: Complete before/after examples for all changes

### Success Criteria
1. All 90+ agents fully compliant with Jido patterns
2. Zero legacy `Behavior` or `GenServer` patterns remaining
3. 100% action-based business logic extraction
4. Comprehensive signal routing with no direct handlers
5. Complete test coverage with performance validation
6. Full documentation and migration runbooks

This migration will establish RubberDuck as a fully modern, Jido-compliant agent system with enterprise-grade reliability, maintainability, and scalability through complete modernization and elimination of legacy patterns.
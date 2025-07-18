# RubberDuck LLM Tool Definition System

## Declarative tool system empowers AI with safe, monitored execution

The LLM Tool Definition System, implemented in Phase 9 of RubberDuck, provides a comprehensive framework for defining, executing, and managing tools that can be safely invoked by language models. Built on Elixir's robust concurrency model and leveraging Spark DSL for declarative configuration, the system ensures secure, monitored execution while maintaining the flexibility needed for diverse tool implementations.

## Architecture leverages Spark DSL for declarative tool definitions

The tool system's foundation rests on **Spark DSL**, enabling developers to define tools declaratively with compile-time validation and automatic code generation. This approach ensures type safety, comprehensive documentation, and consistent behavior across all tools in the system.

**Core Components**: The architecture comprises several key modules working in concert:
- **Tool Definition DSL** (`RubberDuck.Tool`): Provides the declarative interface for tool specification
- **Registry** (`RubberDuck.Tool.Registry`): ETS-backed storage for high-performance tool discovery
- **Executor** (`RubberDuck.Tool.Executor`): Multi-layer execution pipeline with validation and sandboxing
- **Sandbox** (`RubberDuck.Tool.Sandbox`): Process-level isolation for secure execution
- **Result Processor** (`RubberDuck.Tool.ResultProcessor`): Output transformation and persistence pipeline

**Declarative Tool Structure**: Each tool definition includes four primary sections:
```elixir
defmodule MyApp.Tools.DataAnalyzer do
  use RubberDuck.Tool
  
  tool do
    # Metadata section
    name :data_analyzer
    description "Analyzes datasets and provides insights"
    category :analytics
    version "1.0.0"
    tags [:data, :statistics, :visualization]
    
    # Parameter definitions with JSON Schema generation
    parameter :dataset_path do
      type :string
      required true
      description "Path to the dataset file"
      constraints [
        pattern: "^[a-zA-Z0-9/_.-]+\\.csv$"
      ]
    end
    
    # Execution configuration
    execution do
      handler &MyApp.Tools.DataAnalyzer.analyze/2
      timeout 30_000
      async true
      retries 2
    end
    
    # Security configuration
    security do
      sandbox :balanced
      capabilities [:file_read, :computation]
      rate_limit 10 # per minute
    end
  end
end
```

## Multi-layer execution pipeline ensures safety and reliability

The execution system implements a sophisticated pipeline that validates, authorizes, executes, and processes tool invocations through multiple defensive layers.

**Execution Flow**: When a tool is invoked, the request passes through:
1. **Parameter Validation**: JSON Schema validation with custom constraints
2. **Authorization**: Capability-based access control with role checking
3. **Sandboxed Execution**: Process isolation with resource limits
4. **Result Processing**: Output formatting, caching, and persistence

**Validation Layer**: The validator ensures all parameters meet defined constraints before execution:
```elixir
# Automatic JSON Schema generation from DSL
schema = %{
  "type" => "object",
  "properties" => %{
    "dataset_path" => %{
      "type" => "string",
      "pattern" => "^[a-zA-Z0-9/_.-]+\\.csv$"
    }
  },
  "required" => ["dataset_path"]
}
```

**Authorization Layer**: Tools declare required capabilities, enforced at runtime:
- File system access levels (read, write, specific paths)
- Network access permissions
- Computation resource allocation
- External service integrations

## Process-level sandboxing provides robust security isolation

The sandbox system leverages BEAM's process isolation to create secure execution environments with configurable security levels.

**Security Levels**: Four pre-configured levels balance security and functionality:
- **Strict**: Minimal permissions, 5s timeout, 50MB memory, no network
- **Balanced**: Moderate permissions, 15s timeout, 75MB memory, restricted file access
- **Relaxed**: Extended permissions, 30s timeout, 150MB memory, network allowed
- **None**: Unrestricted execution (development only)

**Resource Enforcement**: The sandbox enforces multiple resource constraints:
```elixir
# Process-level memory limits
Process.flag(:max_heap_size, %{
  size: sandbox_config.memory_limit,
  kill: true,
  error_logger: true
})

# CPU time monitoring
monitor_cpu_usage(parent_pid, cpu_limit_seconds)

# File system restrictions
validate_file_access(path, allowed_paths)

# Environment variable filtering
filter_environment_variables(allowed_vars)
```

**Dangerous Operation Prevention**: The system maintains lists of dangerous modules and functions, preventing their invocation within sandboxed environments. This includes system commands, process spawning, and network operations based on the security level.

## Registry enables efficient tool discovery and management

The tool registry provides high-performance storage and retrieval using ETS with support for versioning, categorization, and hot reloading during development.

**Registry Features**:
- **Version Management**: Multiple versions of the same tool can coexist
- **Category-based Discovery**: Tools organized by functional categories
- **Tag-based Search**: Flexible tagging for cross-category discovery
- **Hot Reloading**: Development mode updates without restart

**Discovery Operations**:
```elixir
# Get latest version of a tool
{:ok, tool} = Registry.get(:data_analyzer)

# Get specific version
{:ok, tool} = Registry.get(:data_analyzer, "1.0.0")

# List tools by category
analytics_tools = Registry.list_by_category(:analytics)

# Search by tags
data_tools = Registry.list_by_tag(:data)
```

## Result processing pipeline handles diverse output formats

The result processor provides a comprehensive pipeline for transforming, formatting, caching, and persisting tool execution results.

**Processing Stages**:
1. **Validation**: Ensures result structure compliance
2. **Transformation**: Applies output transformations (sanitization, compression, encryption)
3. **Formatting**: Converts to requested format (JSON, XML, YAML, binary, plain text)
4. **Enrichment**: Adds metadata and processing information
5. **Caching**: Stores in ETS for fast retrieval
6. **Persistence**: Optional file system storage for audit trails

**Output Formats**: The system supports multiple output formats for different client needs:
```elixir
# Format selection in processing options
opts = [
  format: :json,        # For API responses
  cache: true,          # Enable result caching
  persist: true,        # Save to file system
  transform: :sanitize  # Remove sensitive data
]

{:ok, processed} = ResultProcessor.process_result(raw_result, tool_module, context, opts)
```

## Monitoring and telemetry provide comprehensive observability

The tool system includes extensive monitoring capabilities for tracking execution metrics, performance characteristics, and system health.

**Telemetry Events**: Standardized events emitted throughout execution:
- `[:rubber_duck, :tool, :execution, :start]` - Execution begins
- `[:rubber_duck, :tool, :execution, :stop]` - Successful completion
- `[:rubber_duck, :tool, :execution, :exception]` - Execution failure
- `[:rubber_duck, :tool, :sandbox, :violation]` - Security violation
- `[:rubber_duck, :tool, :cache, :hit/:miss]` - Cache operations

**Real-time Monitoring**: The monitoring system tracks:
- Execution counts and success rates per tool
- Response time percentiles (p50, p95, p99)
- Resource usage patterns
- Error rates and failure reasons
- Concurrent execution levels

**Health Checks**: Automated health monitoring ensures system reliability:
```elixir
health_status = %{
  total_tools: Registry.list() |> length(),
  active_executions: Monitoring.get_active_execution_count(),
  error_rate: Monitoring.get_error_rate(300), # Last 5 minutes
  avg_response_time: Monitoring.get_avg_response_time()
}
```

## Async execution supports long-running operations

The system provides comprehensive support for asynchronous tool execution with progress tracking, cancellation, and status monitoring.

**Async Execution Flow**:
```elixir
# Start async execution
{:ok, ref} = Executor.execute_async(MyTool, params, user)

# Check status
{:ok, status} = Executor.get_execution_status(ref)
# => %{status: :running, started_at: timestamp, tool: :my_tool}

# Cancel if needed
:ok = Executor.cancel_execution(ref)

# Receive results
receive do
  {^ref, {:ok, result}} -> process_result(result)
  {^ref, {:error, reason}} -> handle_error(reason)
end
```

**Concurrency Control**: The system enforces per-user concurrency limits to prevent resource exhaustion while maintaining responsive performance for all users.

## File system persistence enables audit trails and analytics

Tool results can be persisted to the file system for compliance, debugging, and analytics purposes.

**Storage Architecture**:
- **Directory Structure**: `priv/storage/results/{tool_name}/{execution_id}/{timestamp}`
- **Format**: JSON encoding for human readability
- **Key Encoding**: Base64 encoded paths for safety
- **Automatic Cleanup**: Age-based cleanup for storage management

**Use Cases**:
1. **Compliance**: Audit trails for regulated environments
2. **Debugging**: Historical execution analysis
3. **Analytics**: Usage patterns and performance metrics
4. **Testing**: Result replay for regression testing

## Integration patterns support diverse tool implementations

The tool system's flexibility supports various integration patterns for different tool types.

**File Processing Tools**:
```elixir
tool do
  name :document_processor
  
  parameter :file_path do
    type :string
    constraints [exists: true, readable: true]
  end
  
  security do
    sandbox :balanced
    file_access ["./uploads", "./temp"]
  end
end
```

**External API Tools**:
```elixir
tool do
  name :weather_service
  
  parameter :location do
    type :string
    required true
  end
  
  execution do
    handler &call_weather_api/2
    timeout 10_000
  end
  
  security do
    sandbox :relaxed
    network_access true
    capabilities [:http_client]
  end
end
```

**Computation Tools**:
```elixir
tool do
  name :data_transformer
  
  parameter :dataset do
    type :map
    required true
  end
  
  parameter :operations do
    type :list
    constraints [min_length: 1]
  end
  
  execution do
    handler &transform_data/2
    async true
  end
  
  security do
    sandbox :strict
    capabilities [:computation]
  end
end
```

## Future extensibility supports advanced features

The tool system's architecture provides clear extension points for future enhancements:

**Tool Composition**: Section 9.5 will add Reactor integration for complex tool workflows:
- Sequential tool chaining with data flow
- Parallel execution with result merging
- Conditional branching based on results
- Error handling and compensation strategies

**External Integration**: Section 9.3 will implement the Tool Integration Bridge:
- Automatic tool exposure to external services
- Bidirectional synchronization
- Capability advertisement
- Cross-system tool discovery

**MCP Protocol**: Section 9.7 will add Model Context Protocol support:
- WebSocket transport via Phoenix Channels
- Tool exposure to external LLMs
- Streaming response support
- Cross-platform interoperability

## Implementation showcases Elixir's strengths

The LLM Tool Definition System demonstrates how Elixir's unique features create a robust, scalable platform for AI tool execution:

**Concurrency**: Process isolation enables safe parallel execution without complex threading or locking mechanisms. Each tool runs in its own supervised process with independent resource limits.

**Fault Tolerance**: OTP supervision ensures failed tool executions don't compromise system stability. The registry, executor, and monitor all run under separate supervisors with appropriate restart strategies.

**Hot Code Loading**: Tool definitions can be updated during development without restarting the system, accelerating the development cycle and enabling rapid iteration.

**Pattern Matching**: The multi-layer execution pipeline uses pattern matching extensively for clean, maintainable code that clearly expresses business logic.

**Declarative Configuration**: Spark DSL provides a clean, intuitive interface for tool definition while generating efficient runtime code with compile-time guarantees.

The result is a tool system that's not just powerful and flexible, but also safe, monitored, and production-ready - embodying the best practices of modern Elixir development while providing the security and reliability required for AI-powered applications.
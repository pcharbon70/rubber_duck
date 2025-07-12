# Testing Guide for RubberDuck TUI

This document provides comprehensive information about testing the RubberDuck TUI, including the mock interface, unit tests, integration tests, and performance testing.

## Test Overview

The test suite is designed to validate:
- ✅ **Mock Interface Functionality**: Complete Phoenix channel simulation
- ✅ **UI Component Integration**: TUI components working with mock data  
- ✅ **Performance**: Response times and memory usage
- ✅ **Error Handling**: Various failure scenarios
- ✅ **Configuration**: Environment-based client selection
- ✅ **Compatibility**: Interface compliance between mock and real clients

## Quick Start

### Run All Tests
```bash
cd tui
./test_runner.sh
```

### Run Specific Test Suites
```bash
# Unit tests only
go test -v ./internal/phoenix
go test -v ./internal/ui

# Integration tests only
go test -v ./internal/phoenix -run Integration
go test -v ./internal/ui -run Integration

# Mock-specific tests
go test -v ./internal/phoenix -run Mock

# Performance benchmarks
go test -bench=. -benchmem ./internal/phoenix
```

## Test Structure

### 1. Unit Tests

#### Phoenix Interface Tests (`internal/phoenix/mock_test.go`)
- **Connection Management**: Connect, disconnect, channel operations
- **File Operations**: List, load, save, watch files
- **Analysis Operations**: File analysis, project analysis, streaming
- **Code Operations**: Generation, completion, refactoring
- **LLM Operations**: Provider management, status checking
- **Health Operations**: System health and metrics

```go
func TestMockClientFileOperations(t *testing.T) {
    mock := NewMockClient()
    setupMockClient(mock, t)
    
    // Test file listing
    cmd := mock.ListFiles(".")
    msg := cmd()
    // Verify response structure and content
}
```

#### Factory Tests (`internal/phoenix/factory_test.go`)
- **Client Selection Logic**: Environment-based mock/real selection
- **Configuration Handling**: URL, API keys, channel topics
- **Mode Switching**: Enable/disable mock mode
- **Environment Detection**: Development vs production

```go
func TestFactoryClientSelection(t *testing.T) {
    tests := []struct {
        name     string
        envVars  map[string]string
        wantMock bool
    }{
        // Test cases for different configurations
    }
    // Validate correct client type selection
}
```

### 2. Integration Tests

#### UI Integration Tests (`internal/ui/integration_test.go`)
- **Complete Workflows**: End-to-end user interactions
- **Component Integration**: File tree, editor, command palette
- **Phoenix Communication**: Mock client integration
- **Error Handling**: UI response to various error conditions
- **View Rendering**: UI rendering in different states

```go
func TestCompleteWorkflowIntegration(t *testing.T) {
    model := setupConnectedModel(t)
    
    // 1. Load file tree
    // 2. Select a file  
    // 3. Edit content
    // 4. Analyze file
    // 5. Generate code
    // Verify each step works correctly
}
```

### 3. Performance Tests

#### Benchmark Tests (`internal/phoenix/benchmark_test.go`)
- **Operation Speed**: File operations, analysis, code generation
- **Memory Usage**: Allocation patterns and efficiency
- **Concurrent Operations**: Multi-threaded performance
- **Network Simulation**: Different delay configurations

```go
func BenchmarkMockClientOperations(b *testing.B) {
    // Benchmark file operations
    b.Run("ListFiles", func(b *testing.B) {
        for i := 0; i < b.N; i++ {
            cmd := mock.ListFiles(".")
            cmd()
        }
    })
}
```

## Test Configuration

### Environment Variables

| Variable | Purpose | Test Values |
|----------|---------|-------------|
| `RUBBER_DUCK_CLIENT_TYPE` | Force client type | `mock`, `real` |
| `RUBBER_DUCK_USE_MOCK` | Enable mock mode | `true`, `false` |
| `RUBBER_DUCK_ENV` | Environment mode | `test`, `development`, `production` |
| `RUBBER_DUCK_SERVER_URL` | Server endpoint | `ws://localhost:5555/socket` |

### Mock Client Configuration

```go
// Create mock with custom settings
mock := NewMockClientWithOptions(MockOptions{
    NetworkDelay:   50 * time.Millisecond,  // Response delay
    ErrorRate:      0.1,                    // 10% error rate
    StreamingSpeed: 25 * time.Millisecond, // Streaming speed
})
```

### Test Helpers

```go
// Setup connected mock client
func setupMockClient(mock *MockClient, t *testing.T) {
    program := tea.NewProgram(nil)
    config := Config{URL: "ws://localhost:5555/socket"}
    
    connectCmd := mock.Connect(config, program)
    connectCmd()
    // ... setup complete
}
```

## Test Data

### Mock File Structure
The mock client simulates a realistic Go project:
```
project/
├── cmd/main.go              (Entry point)
├── internal/
│   ├── ui/                  (UI components)
│   └── phoenix/             (Phoenix client)
├── go.mod                   (Go module)
├── go.sum                   (Dependencies)
└── README.md               (Documentation)
```

### Mock Responses

#### File Content Generation
- **Go files**: Package declarations, imports, functions
- **Markdown**: Documentation with code examples
- **JSON**: Configuration with realistic structure
- **Generic**: Timestamped placeholder content

#### Analysis Results
- **Issues**: Style warnings, performance suggestions
- **Metrics**: Lines of code, complexity scores
- **Suggestions**: Refactoring recommendations

#### LLM Providers
- **Ollama**: Local provider with llama3.2, codellama models
- **OpenAI**: Remote provider with GPT models
- **Status**: Connection health, request metrics

## Test Patterns

### 1. State Validation Pattern
```go
func TestModelState(t *testing.T) {
    model := NewModel()
    
    // Initial state
    assert.False(t, model.connected)
    assert.Nil(t, model.phoenixClient)
    
    // After initialization
    model, _ = model.Update(InitiateConnectionMsg{})
    assert.NotNil(t, model.phoenixClient)
}
```

### 2. Message Flow Pattern
```go
func TestMessageFlow(t *testing.T) {
    model := setupConnectedModel(t)
    
    // Send message
    model, cmd := model.Update(FileSelectedMsg{Path: "main.go"})
    
    // Execute command
    if cmd != nil {
        msg := cmd()
        model, _ = model.Update(msg)
    }
    
    // Verify state change
    assert.Contains(t, model.statusBar, "main.go")
}
```

### 3. Error Simulation Pattern
```go
func TestErrorHandling(t *testing.T) {
    mock := NewMockClient()
    mock.SetErrorRate(1.0) // 100% errors
    
    cmd := mock.ListFiles(".")
    msg := cmd()
    
    // Should receive error message
    assert.IsType(t, ErrorMsg{}, msg)
}
```

## Coverage Targets

| Component | Target Coverage | Current |
|-----------|----------------|---------|
| Phoenix Interface | 95% | ✅ |
| Mock Client | 90% | ✅ |
| Factory | 95% | ✅ |
| UI Components | 80% | ✅ |
| Integration | 70% | ✅ |

## Running Tests

### Development Workflow
1. **Write tests first**: Follow TDD when adding features
2. **Run focused tests**: Use `-run TestName` for specific tests
3. **Check coverage**: Generate coverage reports regularly
4. **Profile performance**: Run benchmarks for critical paths

### Continuous Integration
```bash
# CI pipeline commands
go test -v ./...                    # All tests
go test -race ./...                 # Race detection
go test -coverprofile=coverage.out  # Coverage
go test -bench=. -benchmem          # Performance
```

### Manual Testing
```bash
# Test with mock client
export RUBBER_DUCK_CLIENT_TYPE=mock
go run ./cmd/rubber_duck_tui

# Test build
go build ./cmd/rubber_duck_tui
./rubber_duck_tui
```

## Debugging Tests

### Verbose Output
```bash
go test -v ./internal/phoenix -run TestSpecificFunction
```

### Debug Specific Test
```go
func TestDebugExample(t *testing.T) {
    t.Log("Debug info here")
    
    // Add debug prints
    fmt.Printf("State: %+v\n", model)
    
    // Use test helpers
    if testing.Verbose() {
        // Detailed output
    }
}
```

### Race Detection
```bash
go test -race ./...
```

## Test Best Practices

### 1. Isolation
- Each test should be independent
- Use setup/teardown functions
- Clean up environment variables

### 2. Clarity
- Descriptive test names: `TestFileLoadingWithValidPath`
- Clear assertions with helpful messages
- Document complex test scenarios

### 3. Coverage
- Test both success and error paths
- Cover edge cases and boundary conditions
- Validate error messages and types

### 4. Performance
- Keep tests fast (< 100ms each)
- Use mock delays sparingly
- Parallel tests where possible

### 5. Maintainability
- Extract common setup to helpers
- Use table-driven tests for multiple scenarios
- Keep tests close to the code they test

## Troubleshooting

### Common Issues

1. **Tests timeout**: Reduce mock network delays
2. **Race conditions**: Use proper synchronization
3. **Environment conflicts**: Clean up env vars
4. **Flaky tests**: Check for random behavior

### Debug Commands
```bash
# Run single test with verbose output
go test -v -run TestName ./internal/phoenix

# Show test coverage
go test -cover ./...

# Profile tests
go test -cpuprofile=cpu.prof -memprofile=mem.prof

# Check for race conditions
go test -race -count=100 ./...
```

## Adding New Tests

### 1. Unit Test Template
```go
func TestNewFeature(t *testing.T) {
    // Setup
    mock := NewMockClient()
    
    // Test cases
    tests := []struct {
        name string
        input string
        want string
    }{
        // Test cases here
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // Test implementation
        })
    }
}
```

### 2. Integration Test Template
```go
func TestNewWorkflow(t *testing.T) {
    phoenix.EnableMockMode()
    defer phoenix.DisableMockMode()
    
    model := setupConnectedModel(t)
    
    // Simulate user workflow
    // Verify expected behavior
}
```

### 3. Benchmark Template
```go
func BenchmarkNewOperation(b *testing.B) {
    mock := NewMockClient()
    mock.SetNetworkDelay(1 * time.Microsecond)
    
    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        // Operation to benchmark
    }
}
```

This comprehensive test suite ensures the mock interface works correctly and provides a solid foundation for TUI development and testing! 🧪✅
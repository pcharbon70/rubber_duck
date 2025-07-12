# Mock Phoenix Interface for RubberDuck TUI

This document describes the mock interface created for the RubberDuck TUI that simulates Phoenix channel communication during development and testing.

## Overview

The mock interface provides a complete simulation of the Phoenix WebSocket communication without requiring a running Phoenix server. This enables:

- **Offline development**: Work on the TUI without a backend server
- **Predictable testing**: Consistent mock data for testing UI components
- **Performance testing**: Simulate different network conditions and error rates
- **Rapid prototyping**: Quick iteration on UI features

## Architecture

The mock system consists of several key components:

### 1. Interface Definition (`interface.go`)

```go
type PhoenixClient interface {
    // Connection management
    Connect(config Config, program *tea.Program) tea.Cmd
    Disconnect() tea.Cmd
    IsConnected() bool
    
    // File operations
    ListFiles(path string) tea.Cmd
    LoadFile(path string) tea.Cmd
    SaveFile(path string, content string) tea.Cmd
    
    // Analysis operations
    AnalyzeFile(path string, analysisType string) tea.Cmd
    AnalyzeProject(rootPath string, options map[string]any) tea.Cmd
    
    // Code operations
    GenerateCode(prompt string, context map[string]any) tea.Cmd
    CompleteCode(content string, position int, language string) tea.Cmd
    RefactorCode(content string, instruction string, options map[string]any) tea.Cmd
    
    // LLM operations
    ListProviders() tea.Cmd
    GetProviderStatus(provider string) tea.Cmd
    SetActiveProvider(provider string) tea.Cmd
    
    // Health operations
    GetHealthStatus() tea.Cmd
}
```

### 2. Mock Implementation (`mock.go` + `mock_helpers.go`)

The `MockClient` provides:
- Simulated network delays
- Configurable error rates
- Streaming response simulation
- Rich mock data generation
- File system simulation

### 3. Real Implementation (`real_client.go`)

The `RealClient` provides actual Phoenix WebSocket communication for production use.

### 4. Factory (`factory.go`)

Automatic client selection based on environment:
- Development: Uses mock by default
- Production: Uses real client
- Configurable via environment variables

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RUBBER_DUCK_CLIENT_TYPE` | auto | `mock`, `real`, or auto-detect |
| `RUBBER_DUCK_USE_MOCK` | auto | `true` to force mock mode |
| `RUBBER_DUCK_ENV` | development | `development`, `production` |
| `RUBBER_DUCK_SERVER_URL` | `ws://localhost:5555/socket` | Phoenix server URL |
| `RUBBER_DUCK_API_KEY` | - | API key for authentication |
| `RUBBER_DUCK_CHANNEL_TOPIC` | `cli:commands` | Phoenix channel topic |

### Development Setup

1. **Use provided configuration**:
   ```bash
   cp dev-config.env .env
   source .env
   ./rubber_duck_tui
   ```

2. **Manual configuration**:
   ```bash
   export RUBBER_DUCK_CLIENT_TYPE=mock
   ./rubber_duck_tui
   ```

3. **Programmatic configuration**:
   ```go
   phoenix.EnableMockMode()
   client := phoenix.NewPhoenixClient()
   ```

## Mock Features

### File System Simulation

The mock client simulates a complete project structure:

```
project/
├── cmd/
│   └── main.go
├── internal/
│   ├── ui/
│   │   ├── model.go
│   │   ├── view.go
│   │   └── update.go
│   └── phoenix/
│       ├── client.go
│       └── mock.go
├── go.mod
├── go.sum
└── README.md
```

### Code Generation

Mock responses include:
- Generated Go functions
- Code completions with confidence scores
- Refactoring suggestions
- Test generation templates

### Analysis Simulation

Provides realistic analysis results:
- Code metrics (lines, functions, complexity)
- Issues with severity levels
- Performance suggestions
- Style recommendations

### LLM Provider Simulation

Simulates multiple LLM providers:
- **Ollama**: Local provider with models like llama3.2, codellama
- **OpenAI**: Remote provider with GPT models
- Provider status and health metrics
- Switchable active provider

### Streaming Support

Realistic streaming simulation:
- Progressive analysis output
- Code generation streaming
- Configurable streaming speed
- Proper start/data/end message flow

## Customization

### Mock Client Options

```go
mock := phoenix.NewMockClientWithOptions(phoenix.MockOptions{
    NetworkDelay:   50 * time.Millisecond,  // Response delay
    ErrorRate:      0.1,                    // 10% error rate
    StreamingSpeed: 25 * time.Millisecond, // Streaming speed
})
```

### Custom Mock Data

Override default responses by modifying the mock client:

```go
mock := phoenix.NewMockClient()
if mockClient, ok := mock.(*phoenix.MockClient); ok {
    // Customize behavior
    mockClient.SetErrorRate(0.2) // 20% errors for testing
    mockClient.SetNetworkDelay(500 * time.Millisecond) // Slow network
}
```

## Testing

### Unit Tests

```go
func TestWithMockClient(t *testing.T) {
    client := phoenix.NewMockClient()
    
    // Test file operations
    cmd := client.ListFiles(".")
    msg := cmd()
    
    // Verify response type
    if _, ok := msg.(phoenix.StreamStartMsg); !ok {
        t.Error("Expected StreamStartMsg")
    }
}
```

### Integration Tests

```go
func TestUIWithMock(t *testing.T) {
    phoenix.EnableMockMode()
    
    model := ui.NewModel()
    program := tea.NewProgram(model)
    
    // Test UI interactions with mock data
    // ...
}
```

## Production Deployment

For production, ensure real client is used:

```bash
export RUBBER_DUCK_CLIENT_TYPE=real
export RUBBER_DUCK_USE_MOCK=false
export RUBBER_DUCK_ENV=production
export RUBBER_DUCK_SERVER_URL=wss://your-server.com/socket
export RUBBER_DUCK_API_KEY=your-production-key
```

## API Reference

### Response Types

All operations return structured responses:

```go
// File operations
type FileListResponse struct {
    Files []FileInfo `json:"files"`
    Path  string     `json:"path"`
}

type FileContentResponse struct {
    Path     string `json:"path"`
    Content  string `json:"content"`
    Language string `json:"language"`
    Size     int64  `json:"size"`
}

// Analysis operations
type AnalysisResponse struct {
    ID          string                 `json:"id"`
    Type        string                 `json:"type"`
    Status      string                 `json:"status"`
    Results     map[string]any         `json:"results"`
    Issues      []AnalysisIssue        `json:"issues"`
    Suggestions []AnalysisSuggestion   `json:"suggestions"`
}

// And more...
```

### Error Handling

The mock client simulates various error conditions:
- Network timeouts
- Invalid requests
- Server errors
- Channel disconnections

## Benefits

1. **Development Speed**: No backend dependency for UI development
2. **Testing Reliability**: Consistent mock data for automated tests
3. **Offline Work**: Full functionality without internet connection
4. **Performance Testing**: Simulate various network conditions
5. **Error Testing**: Predictable error scenarios
6. **Onboarding**: New developers can start immediately
7. **Documentation**: Living examples of API usage

## Future Enhancements

- Dynamic mock data generation based on project analysis
- Record/replay mode for capturing real server interactions
- Mock data persistence across sessions
- GraphQL mock support for future API evolution
- Performance profiling integration
- Custom scenario scripting

This mock interface provides a solid foundation for TUI development and testing while maintaining compatibility with the real Phoenix communication layer.
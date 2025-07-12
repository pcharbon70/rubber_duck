package phoenix

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// Event handlers for different message types

func (m *MockClient) handleFileEvent(event string, payload map[string]any) tea.Msg {
	switch event {
	case "file:list":
		path, _ := payload["path"].(string)
		if path == "" {
			path = "."
		}
		
		files := m.generateFileList(path)
		response := FileListResponse{
			Files: files,
			Path:  path,
		}
		
		data, _ := json.Marshal(response)
		return ChannelResponseMsg{
			Event:   "file_list",
			Payload: data,
		}
		
	case "file:load":
		path, _ := payload["path"].(string)
		return m.LoadFile(path)()
		
	case "file:save":
		path, _ := payload["path"].(string)
		content, _ := payload["content"].(string)
		return m.SaveFile(path, content)()
		
	default:
		return ErrorMsg{
			Err:       fmt.Errorf("unknown file event: %s", event),
			Component: "File Handler",
		}
	}
}

func (m *MockClient) handleAnalysisEvent(event string, payload map[string]any) tea.Msg {
	switch event {
	case "analyze:file":
		path, _ := payload["path"].(string)
		analysisType, _ := payload["type"].(string)
		if analysisType == "" {
			analysisType = "full"
		}
		return m.AnalyzeFile(path, analysisType)()
		
	case "analyze:project":
		rootPath, _ := payload["root_path"].(string)
		options, _ := payload["options"].(map[string]any)
		return m.AnalyzeProject(rootPath, options)()
		
	default:
		return ErrorMsg{
			Err:       fmt.Errorf("unknown analysis event: %s", event),
			Component: "Analysis Handler",
		}
	}
}

func (m *MockClient) handleGenerationEvent(event string, payload map[string]any) tea.Msg {
	switch event {
	case "generate:code":
		prompt, _ := payload["prompt"].(string)
		context, _ := payload["context"].(map[string]any)
		return m.GenerateCode(prompt, context)()
		
	case "generate:completion":
		content, _ := payload["content"].(string)
		position, _ := payload["position"].(float64)
		language, _ := payload["language"].(string)
		return m.CompleteCode(content, int(position), language)()
		
	case "generate:refactor":
		content, _ := payload["content"].(string)
		instruction, _ := payload["instruction"].(string)
		options, _ := payload["options"].(map[string]any)
		return m.RefactorCode(content, instruction, options)()
		
	case "generate:tests":
		filePath, _ := payload["file_path"].(string)
		testType, _ := payload["test_type"].(string)
		return m.GenerateTests(filePath, testType)()
		
	default:
		return ErrorMsg{
			Err:       fmt.Errorf("unknown generation event: %s", event),
			Component: "Generation Handler",
		}
	}
}

func (m *MockClient) handleLLMEvent(event string, payload map[string]any) tea.Msg {
	switch event {
	case "llm:list_providers":
		return m.ListProviders()()
		
	case "llm:provider_status":
		provider, _ := payload["provider"].(string)
		return m.GetProviderStatus(provider)()
		
	case "llm:set_provider":
		provider, _ := payload["provider"].(string)
		return m.SetActiveProvider(provider)()
		
	default:
		return ErrorMsg{
			Err:       fmt.Errorf("unknown LLM event: %s", event),
			Component: "LLM Handler",
		}
	}
}

// Mock data generators

func (m *MockClient) generateFileList(path string) []FileInfo {
	// Simulate a project structure
	if path == "." || path == "" {
		return []FileInfo{
			{
				Name:  "cmd",
				Path:  "cmd",
				IsDir: true,
				Children: []FileInfo{
					{Name: "main.go", Path: "cmd/main.go", IsDir: false, Size: 245},
				},
			},
			{
				Name:  "internal",
				Path:  "internal",
				IsDir: true,
				Children: []FileInfo{
					{
						Name:  "ui",
						Path:  "internal/ui",
						IsDir: true,
						Children: []FileInfo{
							{Name: "model.go", Path: "internal/ui/model.go", IsDir: false, Size: 1234},
							{Name: "view.go", Path: "internal/ui/view.go", IsDir: false, Size: 2156},
							{Name: "update.go", Path: "internal/ui/update.go", IsDir: false, Size: 3421},
						},
					},
					{
						Name:  "phoenix",
						Path:  "internal/phoenix",
						IsDir: true,
						Children: []FileInfo{
							{Name: "client.go", Path: "internal/phoenix/client.go", IsDir: false, Size: 4567},
							{Name: "mock.go", Path: "internal/phoenix/mock.go", IsDir: false, Size: 8901},
						},
					},
				},
			},
			{Name: "go.mod", Path: "go.mod", IsDir: false, Size: 456},
			{Name: "go.sum", Path: "go.sum", IsDir: false, Size: 12345},
			{Name: "README.md", Path: "README.md", IsDir: false, Size: 789},
		}
	}
	
	// For other paths, return empty or basic structure
	return []FileInfo{}
}

func (m *MockClient) generateFileContent(path string) string {
	ext := filepath.Ext(path)
	base := filepath.Base(path)
	
	switch ext {
	case ".go":
		return fmt.Sprintf(`package main

import (
	"fmt"
	"time"
)

// %s contains example Go code
func main() {
	fmt.Printf("File: %s\n")
	fmt.Printf("Generated at: %s\n")
	
	// TODO: Add actual implementation
	example()
}

func example() {
	// Example function implementation
	data := []string{"hello", "world", "from", "mock"}
	for i, item := range data {
		fmt.Printf("%d: %s\n", i+1, item)
	}
}
`, base, path, time.Now().Format("2006-01-02 15:04:05"))
		
	case ".md":
		return fmt.Sprintf(`# %s

This file was generated by the mock Phoenix client for testing purposes.

## Generated Content

- File: %s
- Generated: %s
- Type: Markdown Documentation

## Features

- [x] Mock file generation
- [x] Content simulation
- [ ] Real integration
- [ ] Advanced features

## Code Example

%s%s
func example() {
    fmt.Println("Hello from mock!")
}
%s%s
`, strings.TrimSuffix(base, ext), path, time.Now().Format("2006-01-02 15:04:05"), "```go", "```")
		
	case ".json":
		return fmt.Sprintf(`{
  "name": "%s",
  "version": "1.0.0",
  "description": "Mock JSON file generated for testing",
  "generated_at": "%s",
  "mock_data": {
    "enabled": true,
    "features": ["file_browser", "code_editor", "analysis"],
    "providers": ["ollama", "openai"],
    "settings": {
      "theme": "dark",
      "font_size": 14,
      "show_line_numbers": true
    }
  }
}`, base, time.Now().Format(time.RFC3339))
		
	default:
		return fmt.Sprintf("# %s\n\nThis is mock content for: %s\nGenerated at: %s\n\nContent would be loaded from the actual file in a real implementation.",
			base, path, time.Now().Format("2006-01-02 15:04:05"))
	}
}

func (m *MockClient) detectLanguage(path string) string {
	ext := filepath.Ext(path)
	switch ext {
	case ".go":
		return "go"
	case ".js", ".jsx":
		return "javascript"
	case ".ts", ".tsx":
		return "typescript"
	case ".py":
		return "python"
	case ".rs":
		return "rust"
	case ".ex", ".exs":
		return "elixir"
	case ".rb":
		return "ruby"
	case ".java":
		return "java"
	case ".cpp", ".cc", ".cxx":
		return "cpp"
	case ".c":
		return "c"
	case ".h", ".hpp":
		return "c"
	case ".sh":
		return "bash"
	case ".md":
		return "markdown"
	case ".json":
		return "json"
	case ".yaml", ".yml":
		return "yaml"
	case ".toml":
		return "toml"
	case ".xml":
		return "xml"
	case ".html":
		return "html"
	case ".css":
		return "css"
	default:
		return "text"
	}
}

func (m *MockClient) simulateStreamingAnalysis(path string, analysisType string, isProject bool) tea.Cmd {
	return func() tea.Msg {
		analysisId := fmt.Sprintf("analysis_%d", rand.Intn(10000))
		
		// Send start message
		go func() {
			time.Sleep(m.networkDelay)
			m.program.Send(StreamStartMsg{ID: analysisId})
			
			// Simulate streaming analysis data
			steps := []string{
				"Starting analysis...",
				"Parsing source files...",
				"Running syntax checks...",
				"Analyzing code patterns...",
				"Checking for issues...",
				"Generating suggestions...",
				"Analysis complete!",
			}
			
			for i, step := range steps {
				time.Sleep(m.streamingSpeed)
				m.program.Send(StreamDataMsg{
					ID:   analysisId,
					Data: fmt.Sprintf("[%d/%d] %s\n", i+1, len(steps), step),
				})
			}
			
			// Send final result
			time.Sleep(m.streamingSpeed)
			result := m.generateAnalysisResult(analysisId)
			data, _ := json.Marshal(result)
			m.program.Send(ChannelResponseMsg{
				Event:   "analysis_result",
				Payload: data,
			})
			
			m.program.Send(StreamEndMsg{ID: analysisId})
		}()
		
		return StreamStartMsg{ID: analysisId}
	}
}

func (m *MockClient) simulateStreamingGeneration(prompt string, context map[string]any) tea.Cmd {
	return func() tea.Msg {
		generationId := fmt.Sprintf("gen_%d", rand.Intn(10000))
		
		// Send start message
		go func() {
			time.Sleep(m.networkDelay)
			m.program.Send(StreamStartMsg{ID: generationId})
			
			// Simulate code generation streaming
			codeChunks := []string{
				"func ",
				"ExampleFunction",
				"() {\n",
				"    // Generated code based on: ",
				prompt,
				"\n    fmt.Println(",
				"\"Hello from generated code!\"",
				")\n",
				"    \n    // TODO: Implement actual logic",
				"\n    return nil",
				"\n}",
			}
			
			for _, chunk := range codeChunks {
				time.Sleep(m.streamingSpeed)
				m.program.Send(StreamDataMsg{
					ID:   generationId,
					Data: chunk,
				})
			}
			
			time.Sleep(m.streamingSpeed)
			m.program.Send(StreamEndMsg{ID: generationId})
		}()
		
		return StreamStartMsg{ID: generationId}
	}
}

func (m *MockClient) generateAnalysisResult(analysisId string) AnalysisResponse {
	now := time.Now()
	completed := now.Add(time.Second * 5)
	
	return AnalysisResponse{
		ID:     analysisId,
		Type:   "full_analysis",
		Status: "completed",
		Results: map[string]any{
			"lines_of_code":    rand.Intn(10000),
			"functions":        rand.Intn(100),
			"complexity_score": rand.Float64() * 10,
			"maintainability":  rand.Float64() * 100,
		},
		Issues: []AnalysisIssue{
			{
				Type:        "style",
				Severity:    "warning",
				Message:     "Consider using more descriptive variable names",
				File:        "main.go",
				Line:        15,
				Column:      8,
				Rule:        "variable_naming",
				Suggestion:  "Replace 'x' with 'userCount' or similar",
			},
			{
				Type:        "performance",
				Severity:    "info",
				Message:     "Consider using string builder for string concatenation",
				File:        "utils.go",
				Line:        42,
				Column:      12,
				Rule:        "string_concatenation",
				Suggestion:  "Use strings.Builder for better performance",
			},
		},
		Suggestions: []AnalysisSuggestion{
			{
				Type:        "refactor",
				Description: "Extract common functionality into utility function",
				File:        "main.go",
				StartLine:   20,
				EndLine:     35,
				Confidence:  0.85,
			},
		},
		StartedAt:   now,
		CompletedAt: &completed,
	}
}

func (m *MockClient) generateCodeCompletions(content string, position int, language string) []CodeCompletion {
	// Simple mock completions based on context
	completions := []CodeCompletion{
		{
			Text:        "fmt.Println",
			Description: "Print to standard output",
			Type:        "function",
			Confidence:  0.9,
			StartPos:    position,
			EndPos:      position,
		},
		{
			Text:        "fmt.Printf",
			Description: "Formatted print to standard output",
			Type:        "function",
			Confidence:  0.85,
			StartPos:    position,
			EndPos:      position,
		},
		{
			Text:        "if err != nil",
			Description: "Error handling pattern",
			Type:        "snippet",
			Confidence:  0.8,
			StartPos:    position,
			EndPos:      position,
		},
	}
	
	return completions
}

func (m *MockClient) generateRefactorResult(content string, instruction string) RefactorResponse {
	return RefactorResponse{
		ID:          fmt.Sprintf("refactor_%d", rand.Intn(10000)),
		Status:      "completed",
		Description: fmt.Sprintf("Applied refactoring: %s", instruction),
		Changes: []RefactorChange{
			{
				File:        "main.go",
				StartLine:   10,
				EndLine:     15,
				StartCol:    1,
				EndCol:      20,
				OldContent:  "// Original code here",
				NewContent:  "// Refactored code here\n// Applied: " + instruction,
				Description: "Refactored according to instruction",
			},
		},
		Preview: "// Preview of refactored code\n" + content[:min(200, len(content))] + "...",
	}
}

func (m *MockClient) generateHealthStatus() HealthResponse {
	return HealthResponse{
		Status: "healthy",
		Components: map[string]ComponentHealth{
			"database": {
				Status:  "healthy",
				Message: "All connections active",
				Details: map[string]any{
					"connections": rand.Intn(10) + 5,
					"query_time":  rand.Intn(100),
				},
			},
			"llm_providers": {
				Status:  "healthy",
				Message: fmt.Sprintf("Active provider: %s", m.activeProvider),
				Details: map[string]any{
					"active":    m.activeProvider,
					"available": len(m.providers),
				},
			},
			"memory": {
				Status:  "healthy",
				Message: "Memory usage normal",
				Details: map[string]any{
					"used_mb":  rand.Intn(500) + 100,
					"total_mb": 1024,
				},
			},
		},
		Uptime:    time.Hour * 24 * 7, // 1 week uptime
		Version:   "1.0.0-mock",
		Timestamp: time.Now(),
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
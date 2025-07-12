package phoenix

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// BenchmarkMockClientOperations benchmarks various mock client operations
func BenchmarkMockClientOperations(b *testing.B) {
	mock := NewMockClient()
	mock.SetNetworkDelay(1 * time.Microsecond) // Minimal delay for benchmarking
	mock.SetErrorRate(0) // No errors for clean benchmarking
	
	program := tea.NewProgram(nil)
	config := Config{
		URL:       "ws://localhost:5555/socket",
		APIKey:    "test-key",
		ChannelID: "test:commands",
	}
	
	// Connect once for all benchmarks
	connectCmd := mock.Connect(config, program)
	connectCmd()
	joinCmd := mock.JoinChannel(config.ChannelID)
	joinCmd()
	
	b.Run("ListFiles", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			cmd := mock.ListFiles(".")
			cmd()
		}
	})
	
	b.Run("LoadFile", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			cmd := mock.LoadFile("main.go")
			cmd()
		}
	})
	
	b.Run("SaveFile", func(b *testing.B) {
		content := "package main\n\nfunc main() {}\n"
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			cmd := mock.SaveFile("test.go", content)
			cmd()
		}
	})
	
	b.Run("AnalyzeFile", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			cmd := mock.AnalyzeFile("main.go", "full")
			cmd()
		}
	})
	
	b.Run("GenerateCode", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			cmd := mock.GenerateCode("Create a hello world function", nil)
			cmd()
		}
	})
	
	b.Run("CompleteCode", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			cmd := mock.CompleteCode("func main() {", 14, "go")
			cmd()
		}
	})
	
	b.Run("ListProviders", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			cmd := mock.ListProviders()
			cmd()
		}
	})
	
	b.Run("GetHealthStatus", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			cmd := mock.GetHealthStatus()
			cmd()
		}
	})
}

// BenchmarkFactoryClientCreation benchmarks client creation through factory
func BenchmarkFactoryClientCreation(b *testing.B) {
	// Save original environment
	originalClientType := os.Getenv("RUBBER_DUCK_CLIENT_TYPE")
	defer func() {
		if originalClientType == "" {
			os.Unsetenv("RUBBER_DUCK_CLIENT_TYPE")
		} else {
			os.Setenv("RUBBER_DUCK_CLIENT_TYPE", originalClientType)
		}
	}()
	
	b.Run("CreateMockClient", func(b *testing.B) {
		os.Setenv("RUBBER_DUCK_CLIENT_TYPE", "mock")
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			client := NewPhoenixClient()
			_ = client
		}
	})
	
	b.Run("CreateRealClient", func(b *testing.B) {
		os.Setenv("RUBBER_DUCK_CLIENT_TYPE", "real")
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			client := NewPhoenixClient()
			_ = client
		}
	})
}

// BenchmarkResponseParsing benchmarks JSON response parsing
func BenchmarkResponseParsing(b *testing.B) {
	mock := NewMockClient()
	mock.SetNetworkDelay(0) // No delay for pure parsing benchmark
	
	b.Run("FileListResponseParsing", func(b *testing.B) {
		cmd := mock.ListFiles(".")
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				var response FileListResponse
				json.Unmarshal(respMsg.Payload, &response)
			}
		}
	})
	
	b.Run("AnalysisResponseParsing", func(b *testing.B) {
		cmd := mock.GetAnalysisResult("test_analysis")
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				var response AnalysisResponse
				json.Unmarshal(respMsg.Payload, &response)
			}
		}
	})
	
	b.Run("ProvidersResponseParsing", func(b *testing.B) {
		cmd := mock.ListProviders()
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				var response ProvidersResponse
				json.Unmarshal(respMsg.Payload, &response)
			}
		}
	})
}

// BenchmarkMockDataGeneration benchmarks mock data generation
func BenchmarkMockDataGeneration(b *testing.B) {
	mock := NewMockClient()
	
	b.Run("GenerateFileContent", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			content := mock.generateFileContent("main.go")
			_ = content
		}
	})
	
	b.Run("GenerateFileList", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			files := mock.generateFileList(".")
			_ = files
		}
	})
	
	b.Run("GenerateAnalysisResult", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			result := mock.generateAnalysisResult("test_analysis")
			_ = result
		}
	})
	
	b.Run("GenerateCodeCompletions", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			completions := mock.generateCodeCompletions("func main() {", 14, "go")
			_ = completions
		}
	})
}

// BenchmarkNetworkDelaySimulation benchmarks different network delay settings
func BenchmarkNetworkDelaySimulation(b *testing.B) {
	delays := []time.Duration{
		0,
		1 * time.Millisecond,
		10 * time.Millisecond,
		50 * time.Millisecond,
		100 * time.Millisecond,
	}
	
	for _, delay := range delays {
		b.Run(fmt.Sprintf("Delay_%v", delay), func(b *testing.B) {
			mock := NewMockClient()
			mock.SetNetworkDelay(delay)
			mock.SetErrorRate(0)
			
			program := tea.NewProgram(nil)
			config := Config{
				URL:       "ws://localhost:5555/socket",
				APIKey:    "test-key",
				ChannelID: "test:commands",
			}
			
			connectCmd := mock.Connect(config, program)
			connectCmd()
			
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				cmd := mock.ListFiles(".")
				cmd()
			}
		})
	}
}

// BenchmarkConcurrentOperations benchmarks concurrent mock client operations
func BenchmarkConcurrentOperations(b *testing.B) {
	mock := NewMockClient()
	mock.SetNetworkDelay(1 * time.Microsecond)
	mock.SetErrorRate(0)
	
	program := tea.NewProgram(nil)
	config := Config{
		URL:       "ws://localhost:5555/socket",
		APIKey:    "test-key",
		ChannelID: "test:commands",
	}
	
	connectCmd := mock.Connect(config, program)
	connectCmd()
	joinCmd := mock.JoinChannel(config.ChannelID)
	joinCmd()
	
	b.Run("ConcurrentFileOperations", func(b *testing.B) {
		b.ResetTimer()
		b.RunParallel(func(pb *testing.PB) {
			for pb.Next() {
				cmd := mock.ListFiles(".")
				cmd()
			}
		})
	})
	
	b.Run("ConcurrentAnalysis", func(b *testing.B) {
		b.ResetTimer()
		b.RunParallel(func(pb *testing.PB) {
			for pb.Next() {
				cmd := mock.AnalyzeFile("main.go", "full")
				cmd()
			}
		})
	})
	
	b.Run("ConcurrentCodeGeneration", func(b *testing.B) {
		b.ResetTimer()
		b.RunParallel(func(pb *testing.PB) {
			for pb.Next() {
				cmd := mock.GenerateCode("Hello world function", nil)
				cmd()
			}
		})
	})
}

// BenchmarkMemoryUsage measures memory allocation patterns
func BenchmarkMemoryUsage(b *testing.B) {
	mock := NewMockClient()
	mock.SetNetworkDelay(0)
	mock.SetErrorRate(0)
	
	b.Run("FileOperationsMemory", func(b *testing.B) {
		b.ReportAllocs()
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			cmd := mock.LoadFile("main.go")
			msg := cmd()
			_ = msg
		}
	})
	
	b.Run("AnalysisMemory", func(b *testing.B) {
		b.ReportAllocs()
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			cmd := mock.GetAnalysisResult("test")
			msg := cmd()
			_ = msg
		}
	})
	
	b.Run("ClientCreationMemory", func(b *testing.B) {
		b.ReportAllocs()
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			client := NewMockClient()
			_ = client
		}
	})
}
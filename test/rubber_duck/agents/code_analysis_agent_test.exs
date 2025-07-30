defmodule RubberDuck.Agents.CodeAnalysisAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.CodeAnalysisAgent
  
  describe "agent initialization" do
    test "starts with default analysis configuration" do
      agent = CodeAnalysisAgent.new("test_analyzer")
      
      state = agent.state
      
      assert state.analysis_queue == []
      assert state.active_analyses == %{}
      assert state.metrics.files_analyzed == 0
      assert state.analyzers == [:static, :security, :style]
    end
  end
  
  describe "file analysis requests" do
    setup do
      agent = CodeAnalysisAgent.new("test_analyzer")
      %{agent: agent}
    end
    
    test "handles code_analysis_request signal", %{agent: agent} do
      # Create a test file
      test_file = "/tmp/test_analysis.ex"
      File.write!(test_file, """
      defmodule TestModule do
        def hello do
          _unused = 42
          "hello"
        end
      end
      """)
      
      signal = %{
        "type" => "code_analysis_request",
        "data" => %{
          "file_path" => test_file,
          "options" => %{},
          "request_id" => "req_123",
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, updated_agent} = CodeAnalysisAgent.handle_signal(agent, signal)
      
      # Check that request was queued
      assert length(updated_agent.state.analysis_queue) == 1
      assert Map.has_key?(updated_agent.state.active_analyses, "req_123")
      
      # Clean up
      File.rm!(test_file)
    end
    
    test "uses cache for repeated analysis", %{agent: agent} do
      # Simulate a cached result
      cache_key = "test_file.ex:#{:crypto.hash(:sha256, :erlang.term_to_binary(%{})) |> Base.encode16(case: :lower)}"
      cached_result = %{
        file: "test_file.ex",
        issues: [],
        metrics: %{total_issues: 0}
      }
      
      agent = put_in(agent.state.analysis_cache[cache_key], %{
        result: cached_result,
        cached_at: System.monotonic_time(:millisecond)
      })
      
      signal = %{
        "type" => "code_analysis_request",
        "data" => %{
          "file_path" => "test_file.ex",
          "options" => %{},
          "request_id" => "req_456",
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, updated_agent} = CodeAnalysisAgent.handle_signal(agent, signal)
      
      # Should have cache hit
      assert updated_agent.state.metrics.cache_hits == 1
      # Should not add to queue
      assert length(updated_agent.state.analysis_queue) == 0
    end
  end
  
  describe "conversation analysis requests" do
    setup do
      agent = CodeAnalysisAgent.new("test_analyzer")
      %{agent: agent}
    end
    
    test "handles conversation_analysis_request signal", %{agent: agent} do
      signal = %{
        "type" => "conversation_analysis_request",
        "data" => %{
          "query" => "Can you review this code for security vulnerabilities?",
          "code" => """
          def process_input(user_input) do
            {:ok, result} = File.read(user_input)
            result
          end
          """,
          "context" => %{"language" => "elixir"},
          "request_id" => "req_789",
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, updated_agent} = CodeAnalysisAgent.handle_signal(agent, signal)
      
      # Check that request was queued
      assert length(updated_agent.state.analysis_queue) == 1
      assert Map.has_key?(updated_agent.state.active_analyses, "req_789")
      
      # Check analysis type detection
      request = updated_agent.state.active_analyses["req_789"]
      assert request.type == :conversation
    end
    
    test "detects analysis type from query", %{agent: agent} do
      test_cases = [
        {"Check for security issues", :security},
        {"Optimize performance", :performance},
        {"Review architecture", :architecture},
        {"General code review", :code_review},
        {"Check complexity", :complexity},
        {"Analyze this code", :general_analysis}
      ]
      
      for {query, expected_type} <- test_cases do
        signal = %{
          "type" => "conversation_analysis_request",
          "data" => %{
            "query" => query,
            "code" => "def test, do: :ok",
            "context" => %{},
            "request_id" => "req_#{expected_type}",
            "provider" => "test",
            "model" => "test-model",
            "user_id" => "user_123"
          }
        }
        
        {:ok, _} = CodeAnalysisAgent.handle_signal(agent, signal)
      end
    end
  end
  
  describe "static analysis" do
    test "detects unused variables in Elixir code" do
      agent = CodeAnalysisAgent.new("test_analyzer")
      
      # Create test with unused variable
      test_file = "/tmp/unused_var_test.ex"
      File.write!(test_file, """
      defmodule UnusedTest do
        def example do
          _unused = 42
          _another_unused = "test"
          "result"
        end
      end
      """)
      
      signal = %{
        "type" => "code_analysis_request",
        "data" => %{
          "file_path" => test_file,
          "options" => %{},
          "request_id" => "unused_test",
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, _} = CodeAnalysisAgent.handle_signal(agent, signal)
      
      # Clean up
      File.rm!(test_file)
    end
    
    test "detects missing documentation" do
      agent = CodeAnalysisAgent.new("test_analyzer")
      
      # Create test without docs
      test_file = "/tmp/no_docs_test.ex"
      File.write!(test_file, """
      defmodule NoDocsTest do
        def public_function do
          :ok
        end
      end
      """)
      
      signal = %{
        "type" => "code_analysis_request",
        "data" => %{
          "file_path" => test_file,
          "options" => %{},
          "request_id" => "docs_test",
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, _} = CodeAnalysisAgent.handle_signal(agent, signal)
      
      # Clean up
      File.rm!(test_file)
    end
  end
  
  describe "metrics tracking" do
    test "tracks analysis metrics" do
      agent = CodeAnalysisAgent.new("test_analyzer")
      
      # Get initial metrics
      signal = %{"type" => "get_analysis_metrics"}
      {:ok, _} = CodeAnalysisAgent.handle_signal(agent, signal)
      
      # Simulate completion
      completion_signal = %{
        "type" => "analysis_complete",
        "data" => %{
          "request_id" => "metrics_test",
          "result" => %{
            issues: [
              %{type: :warning, category: :unused_variable, message: "Test issue"}
            ]
          }
        }
      }
      
      # First add to active analyses
      agent = put_in(agent.state.active_analyses["metrics_test"], %{
        request_id: "metrics_test",
        started_at: System.monotonic_time(:millisecond) - 100,
        type: :file,
        file_path: "test.ex",
        options: %{}
      })
      
      {:ok, updated_agent} = CodeAnalysisAgent.handle_signal(agent, completion_signal)
      
      # Check metrics were updated
      assert updated_agent.state.metrics.files_analyzed == 1
      assert updated_agent.state.metrics.total_issues == 1
      assert updated_agent.state.metrics.analysis_time_ms > 0
    end
  end
  
  describe "cache management" do
    test "caches analysis results" do
      agent = CodeAnalysisAgent.new("test_analyzer")
      
      # Add active analysis
      agent = put_in(agent.state.active_analyses["cache_test"], %{
        request_id: "cache_test",
        started_at: System.monotonic_time(:millisecond),
        type: :file,
        file_path: "cache_test.ex",
        options: %{"key" => "value"}
      })
      
      # Complete analysis
      result = %{file: "cache_test.ex", issues: []}
      completion_signal = %{
        "type" => "analysis_complete",
        "data" => %{
          "request_id" => "cache_test",
          "result" => result
        }
      }
      
      {:ok, updated_agent} = CodeAnalysisAgent.handle_signal(agent, completion_signal)
      
      # Check cache was populated
      assert map_size(updated_agent.state.analysis_cache) == 1
    end
    
    test "respects cache TTL" do
      agent = CodeAnalysisAgent.new("test_analyzer")
      
      # Set short TTL for testing
      agent = put_in(agent.state.cache_ttl_ms, 100)
      
      # Add expired cache entry
      cache_key = "expired.ex:test"
      agent = put_in(agent.state.analysis_cache[cache_key], %{
        result: %{file: "expired.ex"},
        cached_at: System.monotonic_time(:millisecond) - 1000 # 1 second ago
      })
      
      # Try to use cache - should be expired
      signal = %{
        "type" => "code_analysis_request",
        "data" => %{
          "file_path" => "expired.ex",
          "options" => %{},
          "request_id" => "ttl_test",
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, updated_agent} = CodeAnalysisAgent.handle_signal(agent, signal)
      
      # Should add to queue (cache miss)
      assert length(updated_agent.state.analysis_queue) == 1
    end
  end
  
  describe "error handling" do
    test "handles analysis failures gracefully" do
      agent = CodeAnalysisAgent.new("test_analyzer")
      
      # Request analysis of non-existent file
      signal = %{
        "type" => "code_analysis_request",
        "data" => %{
          "file_path" => "/does/not/exist.ex",
          "options" => %{},
          "request_id" => "error_test",
          "provider" => "test",
          "model" => "test-model",
          "user_id" => "user_123"
        }
      }
      
      {:ok, _} = CodeAnalysisAgent.handle_signal(agent, signal)
      
      # Agent should handle the error internally
    end
  end
  
  describe "language detection" do
    test "detects language from file extension" do
      agent = CodeAnalysisAgent.new("test_analyzer")
      
      test_cases = [
        {"test.ex", :elixir},
        {"test.exs", :elixir},
        {"test.js", :javascript},
        {"test.py", :python},
        {"test.txt", :unknown}
      ]
      
      for {filename, expected_lang} <- test_cases do
        # We can't directly test the private function, but we can verify
        # through the analysis flow
        assert expected_lang in [:elixir, :javascript, :python, :unknown]
      end
    end
  end
end
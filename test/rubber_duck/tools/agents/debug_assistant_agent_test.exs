defmodule RubberDuck.Tools.Agents.DebugAssistantAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.DebugAssistantAgent
  
  setup do
    # Mock the tool executor
    Mox.defmock(RubberDuck.ToolSystem.ExecutorMock, for: RubberDuck.ToolSystem.Executor.Behaviour)
    
    # Create agent instance
    {:ok, agent} = DebugAssistantAgent.start()
    
    on_exit(fn ->
      if Process.alive?(agent.pid) do
        GenServer.stop(agent.pid)
      end
    end)
    
    {:ok, agent: agent}
  end
  
  describe "analyze_error signal" do
    test "analyzes error with comprehensive analysis", %{agent: agent} do
      # Setup executor mock
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :debug_assistant, params ->
        assert params.error_message =~ "UndefinedFunctionError"
        assert params.analysis_depth == "comprehensive"
        assert params.include_examples == true
        
        {:ok, %{
          "error_type" => "undefined_function",
          "likely_causes" => [
            "Function doesn't exist or module not loaded",
            "Typo in function name or wrong arity"
          ],
          "debugging_steps" => [
            "Check the error message and identify the failing function",
            "Verify the data being passed matches expected types"
          ],
          "suggested_fixes" => [
            "Check module is properly aliased",
            "Verify function name spelling"
          ],
          "code_examples" => ["alias MyModule", "import MyModule"],
          "additional_resources" => ["HexDocs documentation"],
          "confidence" => 85
        }}
      end)
      
      # Send analyze_error signal
      signal = %{
        "type" => "analyze_error",
        "data" => %{
          "error_message" => "** (UndefinedFunctionError) function MyModule.my_func/2 is undefined",
          "stack_trace" => "    (myapp 0.1.0) lib/my_module.ex:42: MyModule.my_func/2",
          "code_context" => "def some_function do\n  MyModule.my_func(1, 2)\nend",
          "request_id" => "debug_123"
        }
      }
      
      {:ok, _updated_agent} = DebugAssistantAgent.handle_signal(agent, signal)
      
      # Should receive progress signal
      assert_receive {:signal, "debug_progress", progress_data}
      assert progress_data["status"] == "analyzing_error"
      assert progress_data["error_type"] == "undefined_function"
      
      # Wait for async execution
      Process.sleep(100)
      
      # Should receive error_analyzed signal
      assert_receive {:signal, "error_analyzed", result_data}
      assert result_data["request_id"] == "debug_123"
      assert result_data["error_type"] == "undefined_function"
      assert result_data["confidence"] == 85
      assert length(result_data["likely_causes"]) == 2
      assert length(result_data["debugging_steps"]) == 2
    end
    
    test "includes relevant error history in analysis", %{agent: agent} do
      # Add some error history
      history_entry = %{
        error_message: "Another UndefinedFunctionError",
        error_type: "undefined_function",
        resolved: true,
        analyzed_at: DateTime.utc_now()
      }
      agent = put_in(agent.state.error_history, [history_entry])
      
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :debug_assistant, params ->
        # Should include relevant history
        assert length(params.error_history) == 1
        assert hd(params.error_history) =~ "resolved: true"
        
        {:ok, %{
          "error_type" => "undefined_function",
          "likely_causes" => ["Function not found"],
          "debugging_steps" => ["Check function exists"],
          "suggested_fixes" => ["Fix function name"],
          "confidence" => 90
        }}
      end)
      
      signal = %{
        "type" => "analyze_error",
        "data" => %{
          "error_message" => "** (UndefinedFunctionError) function Test.func/0 is undefined"
        }
      }
      
      {:ok, _agent} = DebugAssistantAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, "error_analyzed", _}
    end
  end
  
  describe "start_debug_session signal" do
    test "starts a new debugging session", %{agent: agent} do
      session_signal = %{
        "type" => "start_debug_session",
        "data" => %{
          "name" => "Phoenix Controller Bug",
          "context" => %{"domain" => "web", "framework" => "phoenix"},
          "strategy" => "systematic"
        }
      }
      
      {:ok, agent} = DebugAssistantAgent.handle_signal(agent, session_signal)
      
      assert_receive {:signal, "debug_session_started", session_data}
      assert session_data["name"] == "Phoenix Controller Bug"
      assert session_data["strategy"] == "systematic"
      
      # Verify session in state
      session_id = session_data["session_id"]
      session = agent.state.debug_sessions[session_id]
      assert session.name == "Phoenix Controller Bug"
      assert session.status == "active"
      assert agent.state.active_session == session_id
    end
    
    test "starts session with initial error analysis", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :debug_assistant, params ->
        assert params.analysis_depth == "step_by_step"
        {:ok, %{
          "error_type" => "function_clause",
          "likely_causes" => ["Pattern match failed"],
          "debugging_steps" => ["Check function clauses"],
          "suggested_fixes" => ["Add catch-all clause"],
          "confidence" => 80
        }}
      end)
      
      session_signal = %{
        "type" => "start_debug_session",
        "data" => %{
          "name" => "Function Clause Issue",
          "initial_error" => %{
            "error_message" => "** (FunctionClauseError) no function clause matching"
          }
        }
      }
      
      {:ok, _agent} = DebugAssistantAgent.handle_signal(agent, session_signal)
      
      assert_receive {:signal, "debug_session_started", _}
      Process.sleep(100)
      assert_receive {:signal, "error_analyzed", _}
    end
  end
  
  describe "add_debug_context signal" do
    test "adds context to existing session", %{agent: agent} do
      # Start a session first
      session_id = "test_session"
      agent = put_in(agent.state.debug_sessions[session_id], %{
        id: session_id,
        context: %{"initial" => "data"},
        errors: []
      })
      agent = put_in(agent.state.active_session, session_id)
      
      context_signal = %{
        "type" => "add_debug_context",
        "data" => %{
          "session_id" => session_id,
          "context" => %{
            "code" => "def problematic_function, do: :ok",
            "runtime" => %{"elixir_version" => "1.14"}
          }
        }
      }
      
      {:ok, agent} = DebugAssistantAgent.handle_signal(agent, context_signal)
      
      assert_receive {:signal, "debug_context_added", context_data}
      assert context_data["session_id"] == session_id
      assert "code" in context_data["context_keys"]
      
      # Verify context merged
      session = agent.state.debug_sessions[session_id]
      assert session.context["initial"] == "data"
      assert session.context["code"] =~ "problematic_function"
    end
    
    test "reanalyzes with new context when requested", %{agent: agent} do
      # Setup session with existing error
      session_id = "reanalyze_session"
      existing_error = %{
        "error_message" => "Some error",
        "code_context" => "old context"
      }
      
      agent = put_in(agent.state.debug_sessions[session_id], %{
        id: session_id,
        context: %{},
        errors: [existing_error]
      })
      
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :debug_assistant, params ->
        assert params.code_context == "new context"
        {:ok, %{
          "error_type" => "generic",
          "likely_causes" => ["Updated analysis"],
          "debugging_steps" => ["New steps"],
          "suggested_fixes" => ["New fixes"],
          "confidence" => 75
        }}
      end)
      
      context_signal = %{
        "type" => "add_debug_context",
        "data" => %{
          "session_id" => session_id,
          "context" => %{"code" => "new context"},
          "reanalyze" => true
        }
      }
      
      {:ok, _agent} = DebugAssistantAgent.handle_signal(agent, context_signal)
      
      Process.sleep(100)
      assert_receive {:signal, "error_analyzed", _}
    end
  end
  
  describe "suggest_debugging_steps signal" do
    test "suggests contextual debugging steps", %{agent: agent} do
      steps_signal = %{
        "type" => "suggest_debugging_steps",
        "data" => %{
          "error_type" => "function_clause",
          "context" => %{"domain" => "web"}
        }
      }
      
      {:ok, _agent} = DebugAssistantAgent.handle_signal(agent, steps_signal)
      
      assert_receive {:signal, "debugging_steps", steps_data}
      assert steps_data["error_type"] == "function_clause"
      assert is_list(steps_data["steps"])
      assert steps_data["estimated_time"] != nil
      assert steps_data["difficulty"] != nil
      
      # Should include web-specific steps
      steps_text = Enum.join(steps_data["steps"], " ")
      assert steps_text =~ "request" or steps_text =~ "controller"
    end
    
    test "includes successful solutions in suggestions", %{agent: agent} do
      # Add successful solution
      agent = put_in(agent.state.successful_solutions["function_clause"], [
        {"Check pattern matching", "Verify function heads match input"}
      ])
      
      steps_signal = %{
        "type" => "suggest_debugging_steps",
        "data" => %{
          "error_type" => "function_clause"
        }
      }
      
      {:ok, _agent} = DebugAssistantAgent.handle_signal(agent, steps_signal)
      
      assert_receive {:signal, "debugging_steps", steps_data}
      
      # Should include successful approach
      steps_text = Enum.join(steps_data["steps"], " ")
      assert steps_text =~ "previously successful" or steps_text =~ "Check pattern matching"
    end
  end
  
  describe "track_debug_attempt signal" do
    test "tracks successful debugging attempt", %{agent: agent} do
      attempt_signal = %{
        "type" => "track_debug_attempt",
        "data" => %{
          "description" => "Added proper pattern matching",
          "approach" => "Pattern matching fix",
          "outcome" => "success",
          "error_type" => "function_clause",
          "time_spent_minutes" => 15
        }
      }
      
      {:ok, agent} = DebugAssistantAgent.handle_signal(agent, attempt_signal)
      
      assert_receive {:signal, "debug_attempt_tracked", attempt_data}
      assert attempt_data["outcome"] == "success"
      assert attempt_data["learning_updated"] == true
      
      # Verify successful solution learned
      solutions = agent.state.successful_solutions["function_clause"]
      assert length(solutions) == 1
      assert {"Pattern matching fix", "Added proper pattern matching"} in solutions
    end
    
    test "tracks failed debugging attempt", %{agent: agent} do
      attempt_signal = %{
        "type" => "track_debug_attempt",
        "data" => %{
          "description" => "Tried random changes",
          "approach" => "Random approach",
          "outcome" => "failure",
          "error_type" => "timeout"
        }
      }
      
      {:ok, agent} = DebugAssistantAgent.handle_signal(agent, attempt_signal)
      
      assert_receive {:signal, "debug_attempt_tracked", attempt_data}
      assert attempt_data["outcome"] == "failure"
      
      # Verify failed attempt recorded
      failures = agent.state.failed_attempts["timeout"]
      assert length(failures) == 1
    end
    
    test "adds attempt to active session", %{agent: agent} do
      # Setup session
      session_id = "attempt_session"
      agent = put_in(agent.state.debug_sessions[session_id], %{
        id: session_id,
        attempts: []
      })
      agent = put_in(agent.state.active_session, session_id)
      
      attempt_signal = %{
        "type" => "track_debug_attempt",
        "data" => %{
          "description" => "Checked logs",
          "approach" => "Log analysis",
          "outcome" => "partial"
        }
      }
      
      {:ok, agent} = DebugAssistantAgent.handle_signal(agent, attempt_signal)
      
      # Verify attempt added to session
      session = agent.state.debug_sessions[session_id]
      assert length(session.attempts) == 1
      assert hd(session.attempts).approach == "Log analysis"
    end
  end
  
  describe "get_similar_errors signal" do
    test "finds similar errors from history", %{agent: agent} do
      # Add error history
      similar_error = %{
        error_message: "UndefinedFunctionError function missing",
        error_type: "undefined_function",
        resolution: "Fixed import statement",
        analyzed_at: DateTime.utc_now()
      }
      
      different_error = %{
        error_message: "Database connection timeout",
        error_type: "timeout",
        resolution: "Increased timeout",
        analyzed_at: DateTime.utc_now()
      }
      
      agent = put_in(agent.state.error_history, [similar_error, different_error])
      
      # Add successful solution
      agent = put_in(agent.state.successful_solutions["undefined_function"], [
        {"Check imports", "Verify all modules are imported"}
      ])
      
      similar_signal = %{
        "type" => "get_similar_errors",
        "data" => %{
          "error_message" => "UndefinedFunctionError function not found",
          "similarity_threshold" => 0.5
        }
      }
      
      {:ok, _agent} = DebugAssistantAgent.handle_signal(agent, similar_signal)
      
      assert_receive {:signal, "similar_errors_found", similar_data}
      assert similar_data["total_found"] == 1
      assert length(similar_data["similar_errors"]) == 1
      assert length(similar_data["successful_solutions"]) == 1
      
      similar_error_found = hd(similar_data["similar_errors"])
      assert similar_error_found.error_type == "undefined_function"
      assert similar_error_found.similarity > 0.5
    end
  end
  
  describe "create_debug_report signal" do
    test "generates comprehensive debug report", %{agent: agent} do
      # Setup completed session
      session_id = "report_session"
      start_time = DateTime.add(DateTime.utc_now(), -3600, :second)  # 1 hour ago
      
      session = %{
        id: session_id,
        name: "Complex Bug Session",
        started_at: start_time,
        status: "active",
        errors: [
          %{
            error_type: "function_clause",
            analysis: %{
              "likely_causes" => ["Pattern mismatch"],
              "confidence" => 85
            }
          }
        ],
        attempts: [
          %{outcome: "failure", approach: "Guess and check"},
          %{outcome: "success", approach: "Systematic debugging", notes: "Found the issue"}
        ]
      }
      
      agent = put_in(agent.state.debug_sessions[session_id], session)
      
      report_signal = %{
        "type" => "create_debug_report",
        "data" => %{
          "session_id" => session_id
        }
      }
      
      {:ok, agent} = DebugAssistantAgent.handle_signal(agent, report_signal)
      
      assert_receive {:signal, "debug_report_generated", report}
      assert report["session_id"] == session_id
      assert report["session_name"] == "Complex Bug Session"
      assert report["duration"] > 0
      assert report["errors_analyzed"] == 1
      assert report["attempts_made"] == 2
      assert report["resolution_status"] == "resolved"
      assert is_list(report["key_findings"])
      assert is_list(report["lessons_learned"])
      assert is_list(report["recommendations"])
      
      # Session should be marked as completed
      updated_session = agent.state.debug_sessions[session_id]
      assert updated_session.status == "completed"
    end
  end
  
  describe "error history management" do
    test "maintains error history with size limit", %{agent: agent} do
      # Set small limit for testing
      agent = put_in(agent.state.max_history_size, 3)
      
      # Mock multiple error analyses
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 5, fn :debug_assistant, _params ->
        {:ok, %{
          "error_type" => "generic",
          "likely_causes" => ["Unknown"],
          "debugging_steps" => ["Debug"],
          "suggested_fixes" => ["Fix"],
          "confidence" => 50
        }}
      end)
      
      # Analyze 5 errors
      for i <- 1..5 do
        signal = %{
          "type" => "analyze_error",
          "data" => %{
            "error_message" => "Error #{i}",
            "request_id" => "hist_#{i}"
          }
        }
        
        {:ok, agent} = DebugAssistantAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Should only keep 3 most recent
      assert length(agent.state.error_history) == 3
      
      # Most recent should be first
      [first | _] = agent.state.error_history
      assert first.id == "hist_5"
    end
  end
  
  describe "statistics tracking" do
    test "tracks debugging statistics", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :debug_assistant, _params ->
        {:ok, %{
          "error_type" => "function_clause",
          "likely_causes" => ["Pattern issue"],
          "debugging_steps" => ["Check patterns"],
          "suggested_fixes" => ["Fix patterns"],
          "confidence" => 80
        }}
      end)
      
      # Analyze two errors
      for i <- 1..2 do
        signal = %{
          "type" => "analyze_error",
          "data" => %{
            "error_message" => "FunctionClauseError #{i}"
          }
        }
        
        {:ok, agent} = DebugAssistantAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check statistics
      stats = agent.state.debug_stats
      assert stats.total_errors_analyzed == 2
      assert stats.by_error_type["function_clause"] == 2
      assert stats.by_severity["medium"] == 2
    end
  end
  
  describe "error pattern learning" do
    test "learns error patterns from analyses", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :debug_assistant, _params ->
        {:ok, %{
          "error_type" => "key_error",
          "likely_causes" => ["Missing key", "Wrong data structure"],
          "debugging_steps" => ["Check keys"],
          "suggested_fixes" => ["Add key"],
          "confidence" => 75
        }}
      end)
      
      signal = %{
        "type" => "analyze_error",
        "data" => %{
          "error_message" => "KeyError: key not found"
        }
      }
      
      {:ok, agent} = DebugAssistantAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      # Should learn patterns
      patterns = agent.state.error_patterns["key_error"]
      assert patterns["Missing key"] == 1
      assert patterns["Wrong data structure"] == 1
    end
  end
end
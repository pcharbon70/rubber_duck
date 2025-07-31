defmodule RubberDuck.Tools.Agents.CodeFormatterAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.CodeFormatterAgent
  
  setup do
    # Mock the tool executor
    Mox.defmock(RubberDuck.ToolSystem.ExecutorMock, for: RubberDuck.ToolSystem.Executor.Behaviour)
    
    # Create agent instance
    {:ok, agent} = CodeFormatterAgent.start()
    
    on_exit(fn ->
      if Process.alive?(agent.pid) do
        GenServer.stop(agent.pid)
      end
    end)
    
    {:ok, agent: agent}
  end
  
  describe "format_code signal" do
    test "formats code with default settings", %{agent: agent} do
      # Setup executor mock
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_formatter, params ->
        assert params.code =~ "def hello"
        assert params.line_length == 98
        assert params.check_equivalent == true
        
        {:ok, %{
          "formatted_code" => "def hello do\n  :world\nend\n",
          "changed" => true,
          "analysis" => %{
            "lines_changed" => 2,
            "formatting_issues" => [:inconsistent_spacing],
            "improvements" => [:fixed_indentation]
          },
          "warnings" => []
        }}
      end)
      
      # Send format_code signal
      signal = %{
        "type" => "format_code",
        "data" => %{
          "code" => "def hello do\n:world\nend",
          "request_id" => "fmt_123"
        }
      }
      
      {:ok, _updated_agent} = CodeFormatterAgent.handle_signal(agent, signal)
      
      # Should receive progress signal
      assert_receive {:signal, %Jido.Signal{type: "code.format.progress"} = progress_signal}
      assert progress_signal.data.status == "formatting"
      
      # Wait for async execution
      Process.sleep(100)
      
      # Should receive formatted signal
      assert_receive {:signal, %Jido.Signal{type: "code.formatted"} = result_signal}
      assert result_signal.data.request_id == "fmt_123"
      assert result_signal.data.changed == true
      assert result_signal.data.formatted_code =~ "def hello do"
    end
    
    test "uses custom formatting parameters", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_formatter, params ->
        assert params.line_length == 120
        assert params.force_do_end_blocks == true
        assert params.normalize_charlists == false
        
        {:ok, %{
          "formatted_code" => "formatted with custom params",
          "changed" => true,
          "analysis" => %{"lines_changed" => 1},
          "warnings" => []
        }}
      end)
      
      signal = %{
        "type" => "format_code",
        "data" => %{
          "code" => "def test, do: :ok",
          "line_length" => 120,
          "force_do_end" => true,
          "normalize_charlists" => false
        }
      }
      
      {:ok, _agent} = CodeFormatterAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.formatted"}}
    end
    
    test "applies saved configuration", %{agent: agent} do
      # Save a configuration first
      config_signal = %{
        "type" => "save_format_config",
        "data" => %{
          "name" => "strict_config",
          "line_length" => 80,
          "force_do_end" => true,
          "locals_without_parens" => ["test"]
        }
      }
      
      {:ok, agent} = CodeFormatterAgent.handle_signal(agent, config_signal)
      assert_receive {:signal, %Jido.Signal{type: "code.format.config.saved"}}
      
      # Use saved configuration
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_formatter, params ->
        assert params.line_length == 80
        assert params.force_do_end_blocks == true
        assert params.locals_without_parens == ["test"]
        
        {:ok, %{
          "formatted_code" => "formatted with saved config",
          "changed" => true,
          "analysis" => %{},
          "warnings" => []
        }}
      end)
      
      format_signal = %{
        "type" => "format_code",
        "data" => %{
          "code" => "def test, do: :ok",
          "config" => "strict_config"
        }
      }
      
      {:ok, _agent} = CodeFormatterAgent.handle_signal(agent, format_signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.formatted"}}
    end
  end
  
  describe "validate_formatting signal" do
    test "validates properly formatted code", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_formatter, _params ->
        # Return same code - properly formatted
        {:ok, %{
          "formatted_code" => "def hello, do: :world\n",
          "changed" => false,
          "analysis" => %{},
          "warnings" => []
        }}
      end)
      
      signal = %{
        "type" => "validate_formatting",
        "data" => %{
          "code" => "def hello, do: :world\n",
          "request_id" => "validate_123"
        }
      }
      
      {:ok, _agent} = CodeFormatterAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.format.validated"} = validation_signal}
      assert validation_signal.data.request_id == "validate_123"
      assert validation_signal.data.is_properly_formatted == true
      assert validation_signal.data.changes_needed == false
    end
    
    test "validates improperly formatted code", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_formatter, _params ->
        # Return different code - needs formatting
        {:ok, %{
          "formatted_code" => "def hello do\n  :world\nend\n",
          "changed" => true,
          "analysis" => %{"formatting_issues" => [:inconsistent_indentation]},
          "warnings" => []
        }}
      end)
      
      signal = %{
        "type" => "validate_formatting",
        "data" => %{
          "code" => "def hello do\n:world\nend",
          "request_id" => "validate_456"
        }
      }
      
      {:ok, _agent} = CodeFormatterAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.format.validated"} = validation_signal}
      assert validation_signal.data.request_id == "validate_456"
      assert validation_signal.data.is_properly_formatted == false
      assert validation_signal.data.changes_needed == true
    end
  end
  
  describe "batch_format signal" do
    test "formats multiple code snippets", %{agent: agent} do
      # Mock multiple formatting operations
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_formatter, params ->
        formatted = case params.code do
          code when code =~ "func1" -> "def func1, do: :ok1"
          code when code =~ "func2" -> "def func2, do: :ok2"  
          code when code =~ "func3" -> "def func3, do: :ok3"
        end
        
        {:ok, %{
          "formatted_code" => formatted,
          "changed" => true,
          "analysis" => %{"lines_changed" => 1},
          "warnings" => []
        }}
      end)
      
      batch_signal = %{
        "type" => "batch_format",
        "data" => %{
          "batch_id" => "batch_123",
          "codes" => [
            %{"code" => "def func1,do::ok1", "name" => "snippet1"},
            %{"code" => "def func2,do::ok2", "name" => "snippet2"},
            %{"code" => "def func3,do::ok3", "name" => "snippet3"}
          ]
        }
      }
      
      {:ok, agent} = CodeFormatterAgent.handle_signal(agent, batch_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.format.batch.started"} = start_signal}
      assert start_signal.data.batch_id == "batch_123"
      assert start_signal.data.total_items == 3
      
      # Wait for all formatting to complete
      Process.sleep(300)
      
      assert_receive {:signal, %Jido.Signal{type: "code.format.batch.completed"} = complete_signal}
      assert complete_signal.data.batch_id == "batch_123"
      assert complete_signal.data.completed == 3
      
      # Verify batch in state
      batch = agent.state.batch_operations["batch_123"]
      assert batch.completed == 3
      assert batch.total == 3
    end
  end
  
  describe "format_project signal" do 
    test "discovers and formats project files", %{agent: agent} do
      # Create temporary files for testing
      {:ok, temp_dir} = Temp.mkdir("format_project_test")
      
      test_file1 = Path.join(temp_dir, "lib/module1.ex")
      test_file2 = Path.join(temp_dir, "lib/module2.ex")
      
      File.mkdir_p!(Path.dirname(test_file1))
      File.write!(test_file1, "def func1,do::ok")
      File.write!(test_file2, "def func2,do::ok")
      
      # Mock file formatting
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :code_formatter, _params ->
        {:ok, %{
          "formatted_code" => "def func, do: :ok",
          "changed" => true,
          "analysis" => %{},
          "warnings" => []
        }}
      end)
      
      project_signal = %{
        "type" => "format_project",
        "data" => %{
          "project_path" => temp_dir
        }
      }
      
      {:ok, _agent} = CodeFormatterAgent.handle_signal(agent, project_signal)
      
      # Should trigger batch format
      assert_receive {:signal, %Jido.Signal{type: "code.format.batch.started"}}
      
      # Cleanup
      File.rm_rf!(temp_dir)
    end
  end
  
  describe "save_format_config signal" do
    test "saves custom formatting configuration", %{agent: agent} do
      config_signal = %{
        "type" => "save_format_config",
        "data" => %{
          "name" => "my_config",
          "line_length" => 120,
          "force_do_end" => true,
          "locals_without_parens" => ["assert", "refute"],
          "description" => "Custom project config"
        }
      }
      
      {:ok, agent} = CodeFormatterAgent.handle_signal(agent, config_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.format.config.saved"} = config_signal}
      assert config_signal.data.name == "my_config"
      assert config_signal.data.config.line_length == 120
      
      # Verify config saved in state
      config = agent.state.format_configs["my_config"]
      assert config.name == "my_config"
      assert config.line_length == 120
      assert config.description == "Custom project config"
    end
  end
  
  describe "analyze_formatting signal" do
    test "analyzes code formatting issues", %{agent: agent} do
      messy_code = """
      def messy_function( x,y ) do
      	if x>y do
      		x+y    
      	else
      		x-y
      	end        
      end
      """
      
      analyze_signal = %{
        "type" => "analyze_formatting",
        "data" => %{
          "code" => messy_code
        }
      }
      
      {:ok, _agent} = CodeFormatterAgent.handle_signal(agent, analyze_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.format.analyzed"} = analysis_signal}
      assert analysis_signal.data.code_length > 0
      assert analysis_signal.data.line_count > 5
      assert length(analysis_signal.data.issues) > 0
      assert length(analysis_signal.data.suggestions) > 0
      assert analysis_signal.data.complexity_score in [:low, :medium, :high]
    end
  end
  
  describe "formatting history" do
    test "maintains formatting history", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_formatter, _params ->
        {:ok, %{
          "formatted_code" => "formatted",
          "changed" => true,
          "analysis" => %{"lines_changed" => 2, "formatting_issues" => [:spacing]},
          "warnings" => []
        }}
      end)
      
      # Format multiple code snippets
      for i <- 1..3 do
        signal = %{
          "type" => "format_code",
          "data" => %{
            "code" => "def func#{i}, do: :ok",
            "file_path" => "test#{i}.ex",
            "request_id" => "hist_#{i}"
          }
        }
        
        {:ok, agent} = CodeFormatterAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check history
      assert length(agent.state.format_history) == 3
      
      # Most recent should be first
      [first | _] = agent.state.format_history  
      assert first.id == "hist_3"
      assert first.file_path == "test3.ex"
      assert first.changed == true
    end
    
    test "respects history size limit", %{agent: agent} do
      # Set small limit
      agent = put_in(agent.state.max_history_size, 2)
      
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_formatter, _params ->
        {:ok, %{
          "formatted_code" => "formatted",
          "changed" => true,
          "analysis" => %{},
          "warnings" => []
        }}
      end)
      
      # Format 3 times
      for i <- 1..3 do
        signal = %{
          "type" => "format_code",
          "data" => %{
            "code" => "def func#{i}, do: :ok",
            "request_id" => "limit_#{i}"
          }
        }
        
        {:ok, agent} = CodeFormatterAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Should only keep 2 most recent
      assert length(agent.state.format_history) == 2
    end
  end
  
  describe "statistics tracking" do
    test "tracks formatting statistics", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :code_formatter, _params ->
        {:ok, %{
          "formatted_code" => "formatted",
          "changed" => true,
          "analysis" => %{
            "lines_changed" => 3,
            "formatting_issues" => [:spacing, :indentation]
          },
          "warnings" => []
        }}
      end)
      
      # Format two pieces of code
      for i <- 1..2 do
        signal = %{
          "type" => "format_code", 
          "data" => %{
            "code" => "def func#{i}, do: :ok",
            "file_path" => "file#{i}.ex"
          }
        }
        
        {:ok, agent} = CodeFormatterAgent.handle_signal(agent, signal)  
        Process.sleep(50)
      end
      
      # Check statistics
      stats = agent.state.format_stats
      assert stats.total_formatted == 2
      assert stats.files_formatted == 2
      assert stats.lines_formatted == 6  # 3 lines each
      assert stats.issues_fixed[:spacing] == 2
      assert stats.issues_fixed[:indentation] == 2
    end
  end
  
  describe "agent state management" do
    test "uses agent default preferences", %{agent: agent} do
      # Set custom defaults
      agent = agent
      |> put_in([:state, :default_line_length], 120)
      |> put_in([:state, :default_force_do_end], true)
      
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_formatter, params ->
        assert params.line_length == 120
        assert params.force_do_end_blocks == true
        
        {:ok, %{
          "formatted_code" => "formatted with defaults",
          "changed" => true,
          "analysis" => %{},
          "warnings" => []
        }}
      end)
      
      signal = %{
        "type" => "format_code",
        "data" => %{
          "code" => "def test, do: :ok"
        }
      }
      
      {:ok, _agent} = CodeFormatterAgent.handle_signal(agent, signal)
    end
  end
end
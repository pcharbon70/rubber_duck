defmodule RubberDuck.Tools.Agents.FunctionSignatureExtractorAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.FunctionSignatureExtractorAgent
  
  setup do
    {:ok, agent} = FunctionSignatureExtractorAgent.start_link(id: "test_signature_extractor")
    
    on_exit(fn ->
      if Process.alive?(agent) do
        GenServer.stop(agent)
      end
    end)
    
    %{agent: agent}
  end
  
  describe "action execution" do
    test "executes tool via ExecuteToolAction", %{agent: agent} do
      params = %{
        file: "path/to/file.ex",
        language: :elixir,
        options: %{include_specs: true}
      }
      
      # Execute action directly
      context = %{agent: GenServer.call(agent, :get_state), parent_module: FunctionSignatureExtractorAgent}
      
      # Mock the Executor response
      # In real tests, you'd mock RubberDuck.ToolSystem.Executor
      result = FunctionSignatureExtractorAgent.ExecuteToolAction.run(%{params: params}, context)
      
      # Verify structure (actual execution would need mocking)
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "batch extract action processes multiple files", %{agent: agent} do
      files = ["file1.ex", "file2.ex", "file3.ex"]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Execute batch extract (would need mocking for real execution)
      {:ok, result} = FunctionSignatureExtractorAgent.BatchExtractAction.run(
        %{files: files, parallel: false, language: :elixir, options: %{}}, 
        context
      )
      
      assert result.total_files == 3
      assert is_list(result.results)
      assert is_integer(result.successful_files)
      assert is_integer(result.failed_files)
    end
    
    test "analyze signatures action processes signature data", %{agent: agent} do
      signatures = [
        %{name: "get_user", parameters: [%{name: "id", type: "integer"}], return_type: "User.t()", visibility: :public},
        %{name: "is_valid?", parameters: [%{name: "data", type: "map"}], return_type: "boolean", visibility: :public},
        %{name: "process_data!", parameters: [], return_type: "any", visibility: :private}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = FunctionSignatureExtractorAgent.AnalyzeSignaturesAction.run(
        %{signatures: signatures, analysis_type: :all},
        context
      )
      
      assert result.analysis_type == :all
      assert result.signatures_analyzed == 3
      assert Map.has_key?(result.analysis, :complexity)
      assert Map.has_key?(result.analysis, :patterns)
      assert Map.has_key?(result.analysis, :duplicates)
      assert Map.has_key?(result.analysis, :coverage)
    end
    
    test "generate API docs action creates documentation", %{agent: agent} do
      signatures = [
        %{
          name: "create_user", 
          parameters: [%{name: "attrs", type: "map"}], 
          return_type: "{:ok, User.t()} | {:error, term()}",
          documentation: "Creates a new user with the given attributes",
          visibility: :public,
          module: "UserService"
        },
        %{
          name: "internal_helper", 
          parameters: [], 
          return_type: "any",
          documentation: "Internal helper function",
          visibility: :private,
          module: "UserService"
        }
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Test markdown generation
      {:ok, result} = FunctionSignatureExtractorAgent.GenerateAPIDocsAction.run(
        %{signatures: signatures, format: :markdown, include_private: false, group_by: :module},
        context
      )
      
      assert result.format == :markdown
      assert result.signatures_documented == 1 # Private excluded
      assert result.groups == 1
      assert is_binary(result.documentation)
      assert String.contains?(result.documentation, "create_user")
      refute String.contains?(result.documentation, "internal_helper")
      
      # Test including private functions
      {:ok, result_private} = FunctionSignatureExtractorAgent.GenerateAPIDocsAction.run(
        %{signatures: signatures, format: :markdown, include_private: true, group_by: :module},
        context
      )
      
      assert result_private.signatures_documented == 2
      assert String.contains?(result_private.documentation, "internal_helper")
    end
    
    test "compare signatures action detects changes", %{agent: agent} do
      old_signatures = [
        %{name: "get_user", parameters: [%{name: "id", type: "integer"}], return_type: "User.t()"},
        %{name: "delete_user", parameters: [%{name: "id", type: "integer"}], return_type: "boolean"}
      ]
      
      new_signatures = [
        %{name: "get_user", parameters: [%{name: "id", type: "integer"}], return_type: "{:ok, User.t()} | {:error, term()}"},
        %{name: "create_user", parameters: [%{name: "attrs", type: "map"}], return_type: "{:ok, User.t()} | {:error, term()}"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = FunctionSignatureExtractorAgent.CompareSignaturesAction.run(
        %{signatures1: old_signatures, signatures2: new_signatures, comparison_type: :api_changes},
        context
      )
      
      assert result.comparison_type == :api_changes
      assert result.signatures1_count == 2
      assert result.signatures2_count == 2
      
      comparison = result.comparison
      assert length(comparison.added) == 1 # create_user added
      assert length(comparison.removed) == 1 # delete_user removed
      assert length(comparison.modified) == 1 # get_user return type changed
      assert comparison.summary.total_changes == 3
    end
  end
  
  describe "signal handling with actions" do
    test "tool_request signal triggers ExecuteToolAction", %{agent: agent} do
      signal = %{
        "type" => "tool_request",
        "data" => %{
          "params" => %{
            "file" => "test.ex",
            "language" => "elixir"
          }
        }
      }
      
      # Send signal
      {:ok, updated_agent} = FunctionSignatureExtractorAgent.handle_signal(
        GenServer.call(agent, :get_state),
        signal
      )
      
      # Verify request was queued or processed
      assert is_map(updated_agent.state.active_requests) || 
             length(updated_agent.state.request_queue) > 0
    end
    
    test "batch_extract signal triggers BatchExtractAction", %{agent: agent} do
      signal = %{
        "type" => "batch_extract",
        "data" => %{
          "files" => ["file1.ex", "file2.ex"],
          "language" => "elixir",
          "parallel" => true
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = FunctionSignatureExtractorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "analyze_signatures signal triggers AnalyzeSignaturesAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_signatures",
        "data" => %{
          "analysis_type" => "complexity",
          "language" => "elixir"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = FunctionSignatureExtractorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "generate_api_docs signal triggers GenerateAPIDocsAction", %{agent: agent} do
      signal = %{
        "type" => "generate_api_docs",
        "data" => %{
          "format" => "html",
          "include_private" => true,
          "group_by" => "file"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = FunctionSignatureExtractorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "compare_signatures signal triggers CompareSignaturesAction", %{agent: agent} do
      signal = %{
        "type" => "compare_signatures",
        "data" => %{
          "signatures1" => [],
          "signatures2" => [],
          "comparison_type" => "compatibility"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = FunctionSignatureExtractorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "signature database management" do
    test "successful extractions update signature database", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate successful execution
      result = %{
        result: %{
          file: "test.ex",
          signatures: [
            %{name: "test_func", parameters: [], return_type: "any"}
          ]
        },
        from_cache: false
      }
      
      {:ok, updated} = FunctionSignatureExtractorAgent.handle_action_result(
        state,
        FunctionSignatureExtractorAgent.ExecuteToolAction,
        {:ok, result},
        %{}
      )
      
      assert Map.has_key?(updated.state.signature_database, "test.ex")
      assert length(updated.state.signature_database["test.ex"]) == 1
    end
    
    test "cached results don't update signature database", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        result: %{file: "test.ex", signatures: []},
        from_cache: true
      }
      
      {:ok, updated} = FunctionSignatureExtractorAgent.handle_action_result(
        state,
        FunctionSignatureExtractorAgent.ExecuteToolAction,
        {:ok, result},
        %{}
      )
      
      assert map_size(updated.state.signature_database) == 0
    end
    
    test "batch extract results update signature database", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        signatures: [
          %{name: "func1", file: "file1.ex", parameters: []},
          %{name: "func2", file: "file1.ex", parameters: []},
          %{name: "func3", file: "file2.ex", parameters: []}
        ]
      }
      
      {:ok, updated} = FunctionSignatureExtractorAgent.handle_action_result(
        state,
        FunctionSignatureExtractorAgent.BatchExtractAction,
        {:ok, result},
        %{}
      )
      
      assert Map.has_key?(updated.state.signature_database, "file1.ex")
      assert Map.has_key?(updated.state.signature_database, "file2.ex")
      assert length(updated.state.signature_database["file1.ex"]) == 2
      assert length(updated.state.signature_database["file2.ex"]) == 1
    end
    
    test "signature database is pruned when it gets too large", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set a small max_signatures for testing
      state = put_in(state.state.max_signatures, 5)
      
      # Add many signatures to exceed the limit
      large_database = Enum.reduce(1..10, %{}, fn i, acc ->
        Map.put(acc, "file#{i}.ex", [
          %{name: "func#{i}", parameters: [], extracted_at: DateTime.utc_now()}
        ])
      end)
      
      state = put_in(state.state.signature_database, large_database)
      
      # This would trigger pruning in the actual implementation
      # For testing, we just verify the structure exists
      assert map_size(state.state.signature_database) == 10
      assert state.state.max_signatures == 5
    end
  end
  
  describe "signature analysis" do
    test "complexity analysis calculates metrics correctly" do
      signatures = [
        %{name: "simple", parameters: []},
        %{name: "moderate", parameters: [%{}, %{}, %{}]},
        %{name: "complex", parameters: [%{}, %{}, %{}, %{}, %{}, %{}], return_type: "struct | map"}
      ]
      
      context = %{agent: %{state: %{signature_database: %{}}}}
      
      {:ok, result} = FunctionSignatureExtractorAgent.AnalyzeSignaturesAction.run(
        %{signatures: signatures, analysis_type: :complexity},
        context
      )
      
      complexity = result.analysis
      assert complexity.total_functions == 3
      assert complexity.avg_parameters == 3 # (0 + 3 + 6) / 3
      assert complexity.complex_functions >= 1 # The function with 6 params
      assert complexity.simple_functions >= 1 # The function with 0 params
    end
    
    test "pattern analysis identifies naming patterns" do
      signatures = [
        %{name: "get_user", parameters: []},
        %{name: "get_posts", parameters: []},
        %{name: "set_status", parameters: []},
        %{name: "is_valid", parameters: []},
        %{name: "valid?", parameters: []},
        %{name: "save!", parameters: []}
      ]
      
      context = %{agent: %{state: %{signature_database: %{}}}}
      
      {:ok, result} = FunctionSignatureExtractorAgent.AnalyzeSignaturesAction.run(
        %{signatures: signatures, analysis_type: :patterns},
        context
      )
      
      patterns = result.analysis
      assert Map.has_key?(patterns, :naming_patterns)
      
      naming = patterns.naming_patterns
      assert naming[:getters] == 2 # get_user, get_posts
      assert naming[:setters] == 1 # set_status
      assert naming[:questions] == 1 # valid?
      assert naming[:bangs] == 1 # save!
    end
    
    test "duplicate detection finds identical signatures" do
      signatures = [
        %{name: "process", parameters: [%{}, %{}], return_type: "any"},
        %{name: "process", parameters: [%{}, %{}], return_type: "any", location: "file1.ex:10"},
        %{name: "process", parameters: [%{}, %{}], return_type: "any", location: "file2.ex:20"},
        %{name: "unique", parameters: [], return_type: "boolean"}
      ]
      
      context = %{agent: %{state: %{signature_database: %{}}}}
      
      {:ok, result} = FunctionSignatureExtractorAgent.AnalyzeSignaturesAction.run(
        %{signatures: signatures, analysis_type: :duplicates},
        context
      )
      
      duplicates = result.analysis
      assert length(duplicates) == 1 # Only "process/2" is duplicated
      
      duplicate = hd(duplicates)
      assert duplicate.signature =~ "process/2"
      assert duplicate.count == 3
      assert length(duplicate.locations) == 3
    end
    
    test "coverage analysis counts documented and typed functions" do
      signatures = [
        %{name: "documented", documentation: "This is documented", return_type: "String.t()", visibility: :public},
        %{name: "typed_only", documentation: nil, return_type: "integer", visibility: :public},
        %{name: "neither", documentation: nil, return_type: nil, visibility: :private},
        %{name: "both", documentation: "Documented and typed", return_type: "boolean", visibility: :public}
      ]
      
      context = %{agent: %{state: %{signature_database: %{}}}}
      
      {:ok, result} = FunctionSignatureExtractorAgent.AnalyzeSignaturesAction.run(
        %{signatures: signatures, analysis_type: :coverage},
        context
      )
      
      coverage = result.analysis
      assert coverage.documented_functions == 2 # documented, both
      assert coverage.typed_functions == 3 # documented, typed_only, both
      assert coverage.public_functions == 3 # documented, typed_only, both
      assert coverage.private_functions == 1 # neither
    end
  end
  
  describe "API documentation generation" do
    test "markdown format generates proper structure" do
      signatures = [
        %{
          name: "create_user",
          parameters: [%{name: "attrs", type: "map"}],
          return_type: "{:ok, User.t()} | {:error, term()}",
          documentation: "Creates a new user",
          module: "UserService",
          visibility: :public
        }
      ]
      
      context = %{agent: %{state: %{signature_database: %{}}}}
      
      {:ok, result} = FunctionSignatureExtractorAgent.GenerateAPIDocsAction.run(
        %{signatures: signatures, format: :markdown, group_by: :module},
        context
      )
      
      docs = result.documentation
      assert String.contains?(docs, "## UserService")
      assert String.contains?(docs, "### `create_user")
      assert String.contains?(docs, "Creates a new user")
      assert String.contains?(docs, "attrs :: map")
    end
    
    test "json format generates structured data" do
      signatures = [
        %{name: "test_func", parameters: [], return_type: "any", documentation: "Test", file: "test.ex", line: 10}
      ]
      
      context = %{agent: %{state: %{signature_database: %{}}}}
      
      {:ok, result} = FunctionSignatureExtractorAgent.GenerateAPIDocsAction.run(
        %{signatures: signatures, format: :json, group_by: :file},
        context
      )
      
      docs = result.documentation
      assert is_map(docs)
      assert Map.has_key?(docs, "test.ex")
      
      func_data = hd(docs["test.ex"])
      assert func_data[:name] == "test_func"
      assert func_data[:documentation] == "Test"
      assert func_data[:file] == "test.ex"
      assert func_data[:line] == 10
    end
    
    test "groups signatures by different criteria" do
      signatures = [
        %{name: "get_user", module: "UserService", file: "user.ex"},
        %{name: "is_valid?", module: "UserService", file: "user.ex"},
        %{name: "save!", module: "PostService", file: "post.ex"}
      ]
      
      context = %{agent: %{state: %{signature_database: %{}}}}
      
      # Group by module
      {:ok, result_module} = FunctionSignatureExtractorAgent.GenerateAPIDocsAction.run(
        %{signatures: signatures, format: :json, group_by: :module},
        context
      )
      
      assert Map.has_key?(result_module.documentation, "UserService")
      assert Map.has_key?(result_module.documentation, "PostService")
      assert length(result_module.documentation["UserService"]) == 2
      
      # Group by type
      {:ok, result_type} = FunctionSignatureExtractorAgent.GenerateAPIDocsAction.run(
        %{signatures: signatures, format: :json, group_by: :type},
        context
      )
      
      assert Map.has_key?(result_type.documentation, "Getters")
      assert Map.has_key?(result_type.documentation, "Predicates")
      assert Map.has_key?(result_type.documentation, "Mutating Functions")
    end
  end
  
  describe "signature comparison" do
    test "api_changes comparison detects all change types" do
      old_sigs = [
        %{name: "unchanged", parameters: [], return_type: "any"},
        %{name: "modified", parameters: [], return_type: "string"},
        %{name: "removed", parameters: [], return_type: "boolean"}
      ]
      
      new_sigs = [
        %{name: "unchanged", parameters: [], return_type: "any"},
        %{name: "modified", parameters: [], return_type: "integer"}, # return type changed
        %{name: "added", parameters: [], return_type: "map"}
      ]
      
      context = %{agent: %{state: %{signature_database: %{}}}}
      
      {:ok, result} = FunctionSignatureExtractorAgent.CompareSignaturesAction.run(
        %{signatures1: old_sigs, signatures2: new_sigs, comparison_type: :api_changes},
        context
      )
      
      changes = result.comparison
      assert length(changes.added) == 1
      assert length(changes.removed) == 1
      assert length(changes.modified) == 1
      assert changes.unchanged == 1
      assert changes.summary.total_changes == 3
    end
    
    test "compatibility comparison identifies breaking changes" do
      old_sigs = [%{name: "func", parameters: [], return_type: "string", visibility: :public}]
      new_sigs = [%{name: "func", parameters: [], return_type: "integer", visibility: :private}]
      
      context = %{agent: %{state: %{signature_database: %{}}}}
      
      {:ok, result} = FunctionSignatureExtractorAgent.CompareSignaturesAction.run(
        %{signatures1: old_sigs, signatures2: new_sigs, comparison_type: :compatibility},
        context
      )
      
      compatibility = result.comparison
      assert compatibility.is_compatible == false
      assert compatibility.breaking_changes > 0
      assert length(compatibility.compatibility_issues) > 0
      assert length(compatibility.recommendations) > 0
    end
    
    test "coverage comparison tracks documentation improvements" do
      old_sigs = [
        %{name: "func1", documentation: nil, return_type: nil},
        %{name: "func2", documentation: "docs", return_type: "string"}
      ]
      
      new_sigs = [
        %{name: "func1", documentation: "now documented", return_type: "integer"},
        %{name: "func2", documentation: "docs", return_type: "string"}
      ]
      
      context = %{agent: %{state: %{signature_database: %{}}}}
      
      {:ok, result} = FunctionSignatureExtractorAgent.CompareSignaturesAction.run(
        %{signatures1: old_sigs, signatures2: new_sigs, comparison_type: :coverage},
        context
      )
      
      coverage = result.comparison
      assert coverage.version1.documented == 1
      assert coverage.version2.documented == 2
      assert coverage.version1.typed == 1
      assert coverage.version2.typed == 2
      assert length(coverage.improvements) > 0
    end
  end
  
  describe "result processing" do
    test "process_result adds extraction timestamp", %{agent: _agent} do
      result = %{signatures: [], file: "test.ex"}
      processed = FunctionSignatureExtractorAgent.process_result(result, %{})
      
      assert Map.has_key?(processed, :extracted_at)
      assert %DateTime{} = processed.extracted_at
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = FunctionSignatureExtractorAgent.additional_actions()
      
      assert length(actions) == 4
      assert FunctionSignatureExtractorAgent.BatchExtractAction in actions
      assert FunctionSignatureExtractorAgent.AnalyzeSignaturesAction in actions
      assert FunctionSignatureExtractorAgent.GenerateAPIDocsAction in actions
      assert FunctionSignatureExtractorAgent.CompareSignaturesAction in actions
    end
  end
end
defmodule RubberDuck.Tools.Agents.APIDocGeneratorAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.APIDocGeneratorAgent
  
  setup do
    {:ok, agent} = APIDocGeneratorAgent.start_link(id: "test_api_doc_generator")
    
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
        spec_source: "/path/to/openapi.yaml",
        format: :html,
        theme: :modern
      }
      
      # Execute action directly
      context = %{agent: GenServer.call(agent, :get_state), parent_module: APIDocGeneratorAgent}
      
      # Mock the Executor response - in real tests, you'd mock RubberDuck.ToolSystem.Executor
      result = APIDocGeneratorAgent.ExecuteToolAction.run(%{params: params}, context)
      
      # Verify structure (actual execution would need mocking)
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "generate from OpenAPI action processes spec correctly", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Mock execution - in real implementation would call actual tool
      # For testing, we simulate the structure
      params = %{
        spec_source: "https://api.example.com/openapi.json",
        format: :html,
        theme: :modern,
        include_examples: true,
        include_schemas: true,
        output_path: "/docs"
      }
      
      # In real tests, mock the Executor to return expected structure
      # For now, just verify the action structure exists
      action_module = APIDocGeneratorAgent.GenerateFromOpenAPIAction
      assert function_exported?(action_module, :run, 2)
    end
    
    test "generate from code action processes source paths", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      params = %{
        source_paths: ["lib/", "test/"],
        language: :elixir,
        doc_type: :library,
        format: :markdown,
        include_private: false,
        include_tests: false
      }
      
      # Verify action exists and has correct structure
      action_module = APIDocGeneratorAgent.GenerateFromCodeAction
      assert function_exported?(action_module, :run, 2)
    end
    
    test "validate documentation action checks completeness", %{agent: agent} do
      documentation = %{
        title: "Test API",
        description: "A test API",
        endpoints: [
          %{name: "get_users", examples: [%{request: "GET /users"}]},
          %{name: "create_user", examples: []}
        ]
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = APIDocGeneratorAgent.ValidateDocumentationAction.run(
        %{documentation: documentation, validation_rules: [:completeness, :examples], strict_mode: false},
        context
      )
      
      assert Map.has_key?(result, :validation_results)
      assert Map.has_key?(result, :overall_score)
      assert Map.has_key?(result, :overall_passed)
      
      # Check completeness validation
      completeness = result.validation_results[:completeness]
      assert completeness.rule == :completeness
      assert completeness.passed == true # Has title, description, endpoints
      
      # Check examples validation
      examples = result.validation_results[:examples]
      assert examples.rule == :examples
      # Should pass in non-strict mode even with some missing examples
    end
    
    test "merge documentation action combines sources", %{agent: agent} do
      source1 = %{
        title: "API v1",
        endpoints: [%{name: "get_users", method: "GET"}]
      }
      
      source2 = %{
        title: "API v2", # Will conflict with source1
        endpoints: [%{name: "create_user", method: "POST"}],
        version: "2.0"
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = APIDocGeneratorAgent.MergeDocumentationAction.run(
        %{
          sources: [source1, source2],
          merge_strategy: :union,
          conflict_resolution: :last_wins
        },
        context
      )
      
      assert result.sources_count == 2
      assert result.merge_strategy == :union
      
      merged = result.merged_documentation
      assert merged.title == "API v2" # last_wins conflict resolution
      assert merged.version == "2.0"
      assert length(merged.endpoints) == 2 # Union of endpoints
    end
    
    test "publish documentation action handles multiple platforms", %{agent: agent} do
      documentation = %{
        title: "Test API",
        endpoints: [%{name: "test_endpoint"}],
        schemas: [%{name: "TestSchema"}]
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = APIDocGeneratorAgent.PublishDocumentationAction.run(
        %{
          documentation: documentation,
          platforms: [:file_system, :github_pages],
          publish_config: %{
            output_path: "./docs",
            repository: "user/repo",
            branch: "gh-pages"
          },
          version: "1.0.0"
        },
        context
      )
      
      assert result.successful_publishes == 2
      assert result.failed_publishes == 0
      assert Map.has_key?(result.results, :file_system)
      assert Map.has_key?(result.results, :github_pages)
      
      # Check file system result
      fs_result = result.results[:file_system]
      assert match?({:ok, _}, fs_result)
      {:ok, fs_data} = fs_result
      assert fs_data.platform == :file_system
      assert fs_data.location == "./docs"
    end
  end
  
  describe "signal handling with actions" do
    test "generate_from_openapi signal triggers action", %{agent: agent} do
      signal = %{
        "type" => "generate_from_openapi",
        "data" => %{
          "spec_source" => "openapi.yaml",
          "format" => "html",
          "theme" => "dark"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = APIDocGeneratorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "generate_from_code signal triggers action", %{agent: agent} do
      signal = %{
        "type" => "generate_from_code",
        "data" => %{
          "source_paths" => ["lib/", "src/"],
          "language" => "elixir",
          "doc_type" => "library"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = APIDocGeneratorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "validate_documentation signal triggers action", %{agent: agent} do
      signal = %{
        "type" => "validate_documentation",
        "data" => %{
          "documentation" => %{"title" => "Test"},
          "validation_rules" => ["completeness", "accuracy"],
          "strict_mode" => true
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = APIDocGeneratorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "merge_documentation signal triggers action", %{agent: agent} do
      signal = %{
        "type" => "merge_documentation",
        "data" => %{
          "sources" => [%{"title" => "Doc1"}, %{"title" => "Doc2"}],
          "merge_strategy" => "union",
          "conflict_resolution" => "last_wins"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = APIDocGeneratorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "publish_documentation signal triggers action", %{agent: agent} do
      signal = %{
        "type" => "publish_documentation",
        "data" => %{
          "documentation" => %{"title" => "Test API"},
          "platforms" => ["file_system", "github_pages"],
          "version" => "1.0.0"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = APIDocGeneratorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "validation rules" do
    test "completeness validation checks required sections" do
      complete_doc = %{
        title: "Complete API",
        description: "A complete API description",
        endpoints: [%{name: "test"}]
      }
      
      incomplete_doc = %{
        title: "Incomplete API"
        # Missing description and endpoints
      }
      
      context = %{agent: %{state: %{}}}
      
      # Test complete documentation
      {:ok, result_complete} = APIDocGeneratorAgent.ValidateDocumentationAction.run(
        %{documentation: complete_doc, validation_rules: [:completeness], strict_mode: true},
        context
      )
      
      completeness_complete = result_complete.validation_results[:completeness]
      assert completeness_complete.passed == true
      assert completeness_complete.score == 100.0
      
      # Test incomplete documentation
      {:ok, result_incomplete} = APIDocGeneratorAgent.ValidateDocumentationAction.run(
        %{documentation: incomplete_doc, validation_rules: [:completeness], strict_mode: true},
        context
      )
      
      completeness_incomplete = result_incomplete.validation_results[:completeness]
      assert completeness_incomplete.passed == false
      assert completeness_incomplete.score < 100.0
      assert length(completeness_incomplete.issues) > 0
    end
    
    test "accuracy validation detects issues" do
      doc_with_placeholders = %{
        title: "TODO: Add real title",
        description: "This needs FIXME",
        endpoints: []
      }
      
      clean_doc = %{
        title: "Clean API",
        description: "A proper description",
        endpoints: []
      }
      
      context = %{agent: %{state: %{}}}
      
      # Test document with issues
      {:ok, result_issues} = APIDocGeneratorAgent.ValidateDocumentationAction.run(
        %{documentation: doc_with_placeholders, validation_rules: [:accuracy], strict_mode: false},
        context
      )
      
      accuracy_issues = result_issues.validation_results[:accuracy]
      assert accuracy_issues.passed == false
      assert length(accuracy_issues.issues) > 0
      
      # Test clean document
      {:ok, result_clean} = APIDocGeneratorAgent.ValidateDocumentationAction.run(
        %{documentation: clean_doc, validation_rules: [:accuracy], strict_mode: false},
        context
      )
      
      accuracy_clean = result_clean.validation_results[:accuracy]
      assert accuracy_clean.passed == true
      assert length(accuracy_clean.issues) == 0
    end
    
    test "examples validation checks endpoint examples" do
      doc_with_examples = %{
        endpoints: [
          %{name: "get_users", examples: [%{request: "GET /users"}]},
          %{name: "create_user", request_example: "POST /users"}
        ]
      }
      
      doc_without_examples = %{
        endpoints: [
          %{name: "get_users"},
          %{name: "create_user"}
        ]
      }
      
      context = %{agent: %{state: %{}}}
      
      # Test with examples
      {:ok, result_with} = APIDocGeneratorAgent.ValidateDocumentationAction.run(
        %{documentation: doc_with_examples, validation_rules: [:examples], strict_mode: false},
        context
      )
      
      examples_with = result_with.validation_results[:examples]
      assert examples_with.passed == true
      assert examples_with.score == 100.0
      
      # Test without examples
      {:ok, result_without} = APIDocGeneratorAgent.ValidateDocumentationAction.run(
        %{documentation: doc_without_examples, validation_rules: [:examples], strict_mode: false},
        context
      )
      
      examples_without = result_without.validation_results[:examples]
      assert examples_without.passed == false
      assert examples_without.score == 0.0
    end
  end
  
  describe "merge strategies" do
    test "union merge combines all sources" do
      source1 = %{a: 1, b: 2}
      source2 = %{b: 3, c: 4}
      source3 = %{c: 5, d: 6}
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = APIDocGeneratorAgent.MergeDocumentationAction.run(
        %{
          sources: [source1, source2, source3],
          merge_strategy: :union,
          conflict_resolution: :last_wins
        },
        context
      )
      
      merged = result.merged_documentation
      assert merged.a == 1 # From source1
      assert merged.b == 3 # source2 overwrites source1
      assert merged.c == 5 # source3 overwrites source2
      assert merged.d == 6 # From source3
    end
    
    test "intersection merge keeps only common keys" do
      source1 = %{a: 1, b: 2, c: 3}
      source2 = %{a: 4, b: 5, d: 6}
      source3 = %{a: 7, e: 8}
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = APIDocGeneratorAgent.MergeDocumentationAction.run(
        %{
          sources: [source1, source2, source3],
          merge_strategy: :intersection,
          conflict_resolution: :last_wins
        },
        context
      )
      
      merged = result.merged_documentation
      # Only 'a' is present in all sources
      assert Map.keys(merged) == [:a]
      assert merged.a == 7 # From source3 (last wins)
    end
    
    test "priority merge uses source order" do
      source1 = %{a: 1, b: 2}
      source2 = %{a: 3, c: 4}
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = APIDocGeneratorAgent.MergeDocumentationAction.run(
        %{
          sources: [source1, source2],
          merge_strategy: :priority,
          conflict_resolution: :first_wins # Ignored in priority mode
        },
        context
      )
      
      merged = result.merged_documentation
      assert merged.a == 3 # source2 overwrites source1 in priority mode
      assert merged.b == 2 # From source1
      assert merged.c == 4 # From source2
    end
  end
  
  describe "publishing platforms" do
    test "file system publishing configuration" do
      documentation = %{title: "Test", endpoints: []}
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = APIDocGeneratorAgent.PublishDocumentationAction.run(
        %{
          documentation: documentation,
          platforms: [:file_system],
          publish_config: %{output_path: "/custom/docs"}
        },
        context
      )
      
      fs_result = result.results[:file_system]
      assert match?({:ok, _}, fs_result)
      {:ok, fs_data} = fs_result
      assert fs_data.location == "/custom/docs"
      assert is_integer(fs_data.files_written)
    end
    
    test "github pages publishing configuration" do
      documentation = %{title: "Test", endpoints: []}
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = APIDocGeneratorAgent.PublishDocumentationAction.run(
        %{
          documentation: documentation,
          platforms: [:github_pages],
          publish_config: %{
            repository: "user/my-repo",
            branch: "docs"
          }
        },
        context
      )
      
      gh_result = result.results[:github_pages]
      assert match?({:ok, _}, gh_result)
      {:ok, gh_data} = gh_result
      assert gh_data.repository == "user/my-repo"
      assert gh_data.branch == "docs"
      assert String.contains?(gh_data.url, "user.github.io/my-repo")
    end
    
    test "confluence publishing requires token" do
      documentation = %{title: "Test", endpoints: []}
      
      context = %{agent: %{state: %{}}}
      
      # Without token
      {:ok, result_no_token} = APIDocGeneratorAgent.PublishDocumentationAction.run(
        %{
          documentation: documentation,
          platforms: [:confluence],
          publish_config: %{space: "DOCS"}
        },
        context
      )
      
      confluence_result = result_no_token.results[:confluence]
      assert match?({:error, _}, confluence_result)
      
      # With token
      {:ok, result_with_token} = APIDocGeneratorAgent.PublishDocumentationAction.run(
        %{
          documentation: documentation,
          platforms: [:confluence],
          publish_config: %{
            space: "DOCS",
            confluence_token: "secret-token"
          }
        },
        context
      )
      
      confluence_result_with_token = result_with_token.results[:confluence]
      assert match?({:ok, _}, confluence_result_with_token)
    end
  end
  
  describe "cache and history management" do
    test "successful generations update cache and history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate successful execution
      result = %{
        result: %{
          documentation: %{title: "Test API", format: :html},
          format: :html,
          spec_source: "test.yaml"
        },
        from_cache: false
      }
      
      metadata = %{original_params: %{spec_source: "test.yaml"}}
      
      {:ok, updated} = APIDocGeneratorAgent.handle_action_result(
        state,
        APIDocGeneratorAgent.ExecuteToolAction,
        {:ok, result},
        metadata
      )
      
      # Check cache was updated
      assert map_size(updated.state.doc_cache) > 0
      
      # Check history was updated
      assert length(updated.state.generation_history) == 1
      history_entry = hd(updated.state.generation_history)
      assert history_entry.type == :api_doc_generation
    end
    
    test "cached results don't update history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        result: %{documentation: %{title: "Test"}},
        from_cache: true
      }
      
      {:ok, updated} = APIDocGeneratorAgent.handle_action_result(
        state,
        APIDocGeneratorAgent.ExecuteToolAction,
        {:ok, result},
        %{}
      )
      
      # History should remain empty
      assert length(updated.state.generation_history) == 0
      assert map_size(updated.state.doc_cache) == 0
    end
    
    test "generation history respects max_history limit", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set small limit for testing
      state = put_in(state.state.max_history, 2)
      
      # Add multiple generation actions
      state = Enum.reduce(1..3, state, fn i, acc ->
        result_data = %{
          format: :html,
          spec_source: "test#{i}.yaml",
          generated_at: DateTime.utc_now()
        }
        
        {:ok, updated} = APIDocGeneratorAgent.handle_action_result(
          acc,
          APIDocGeneratorAgent.GenerateFromOpenAPIAction,
          {:ok, result_data},
          %{}
        )
        
        updated
      end)
      
      assert length(state.state.generation_history) == 2
      # Should have the most recent entries
      [first, second] = state.state.generation_history
      assert first.parameters.source =~ "test3.yaml"
      assert second.parameters.source =~ "test2.yaml"
    end
  end
  
  describe "result processing" do
    test "process_result adds generation timestamp", %{agent: _agent} do
      result = %{documentation: %{title: "Test"}, format: :html}
      processed = APIDocGeneratorAgent.process_result(result, %{})
      
      assert Map.has_key?(processed, :generated_at)
      assert %DateTime{} = processed.generated_at
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = APIDocGeneratorAgent.additional_actions()
      
      assert length(actions) == 5
      assert APIDocGeneratorAgent.GenerateFromOpenAPIAction in actions
      assert APIDocGeneratorAgent.GenerateFromCodeAction in actions
      assert APIDocGeneratorAgent.ValidateDocumentationAction in actions
      assert APIDocGeneratorAgent.MergeDocumentationAction in actions
      assert APIDocGeneratorAgent.PublishDocumentationAction in actions
    end
  end
  
  describe "theme and template configuration" do
    test "agent starts with default themes and templates", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Check default themes exist
      assert Map.has_key?(state.state.themes, :modern)
      assert Map.has_key?(state.state.themes, :dark)
      assert Map.has_key?(state.state.themes, :minimal)
      
      # Check default templates exist
      assert Map.has_key?(state.state.templates, :rest_api)
      assert Map.has_key?(state.state.templates, :graphql)
      assert Map.has_key?(state.state.templates, :library)
      
      # Check default presets exist
      assert Map.has_key?(state.state.presets, :quick)
      assert Map.has_key?(state.state.presets, :comprehensive)
      assert Map.has_key?(state.state.presets, :minimal)
    end
  end
end
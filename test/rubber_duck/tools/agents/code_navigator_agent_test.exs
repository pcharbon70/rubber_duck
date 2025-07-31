defmodule RubberDuck.Tools.Agents.CodeNavigatorAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.CodeNavigatorAgent
  
  setup do
    # Mock the tool executor
    Mox.defmock(RubberDuck.ToolSystem.ExecutorMock, for: RubberDuck.ToolSystem.Executor.Behaviour)
    
    # Create agent instance
    {:ok, agent} = CodeNavigatorAgent.start()
    
    on_exit(fn ->
      if Process.alive?(agent.pid) do
        GenServer.stop(agent.pid)
      end
    end)
    
    {:ok, agent: agent}
  end
  
  describe "navigate_to_symbol signal" do
    test "navigates to symbol with default settings", %{agent: agent} do
      # Setup executor mock
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_navigator, params ->
        assert params.symbol == "MyModule.my_function"
        assert params.search_type == "comprehensive"
        assert params.scope == "project"
        assert params.case_sensitive == true
        assert params.include_tests == true
        assert params.max_results == 100
        
        {:ok, %{
          "results" => [
            %{
              "file" => "lib/my_module.ex",
              "line" => 42,
              "column" => 3,
              "match_type" => "definition",
              "context" => "def my_function(arg) do",
              "symbol" => "MyModule.my_function"
            },
            %{
              "file" => "test/my_module_test.exs",
              "line" => 15,
              "column" => 8,
              "match_type" => "call",
              "context" => "assert MyModule.my_function(:test) == :ok"
            }
          ],
          "summary" => %{
            "total_matches" => 2,
            "files_searched" => 50,
            "definition_count" => 1,
            "reference_count" => 1,
            "call_count" => 1
          },
          "navigation" => %{
            "primary_definition" => %{
              "file" => "lib/my_module.ex",
              "line" => 42,
              "column" => 3,
              "symbol" => "MyModule.my_function"
            },
            "related_symbols" => ["MyModule", "my_function/1"],
            "usage_patterns" => %{"test_calls" => 1}
          },
          "metadata" => %{
            "search_type" => "comprehensive",
            "scope" => "project",
            "files_searched" => 50
          }
        }}
      end)
      
      # Send navigate_to_symbol signal
      signal = %{
        "type" => "navigate_to_symbol",
        "data" => %{
          "symbol" => "MyModule.my_function",
          "request_id" => "nav_123"
        }
      }
      
      {:ok, _updated_agent} = CodeNavigatorAgent.handle_signal(agent, signal)
      
      # Should receive progress signal
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.progress"} = progress_signal}
      assert progress_signal.data.status == "searching"
      assert progress_signal.data.symbol == "MyModule.my_function"
      
      # Wait for async execution
      Process.sleep(100)
      
      # Should receive navigation completed signal
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.completed"} = result_signal}
      assert result_signal.data.request_id == "nav_123"
      assert length(result_signal.data.results) == 2
      assert result_signal.data.summary.total_matches == 2
      assert result_signal.data.navigation.primary_definition.line == 42
    end
    
    test "uses custom navigation parameters", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_navigator, params ->
        assert params.search_type == "definitions"
        assert params.scope == "module"
        assert params.case_sensitive == false
        assert params.include_tests == false
        assert params.max_results == 50
        
        {:ok, %{
          "results" => [],
          "summary" => %{"total_matches" => 0},
          "navigation" => %{},
          "metadata" => %{}
        }}
      end)
      
      signal = %{
        "type" => "navigate_to_symbol",
        "data" => %{
          "symbol" => "test_function",
          "search_type" => "definitions",
          "scope" => "module",
          "case_sensitive" => false,
          "include_tests" => false,
          "max_results" => 50
        }
      }
      
      {:ok, _agent} = CodeNavigatorAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.completed"}}
    end
    
    test "returns cached results on second request", %{agent: agent} do
      symbol = "CachedModule.cached_function"
      
      # First request - should call executor
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_navigator, _params ->
        {:ok, %{
          "results" => [%{"file" => "lib/cached.ex", "line" => 10}],
          "summary" => %{"total_matches" => 1},
          "navigation" => %{
            "primary_definition" => %{"file" => "lib/cached.ex", "line" => 10}
          },
          "metadata" => %{}
        }}
      end)
      
      signal = %{
        "type" => "navigate_to_symbol",
        "data" => %{
          "symbol" => symbol,
          "request_id" => "cache_test_1"
        }
      }
      
      {:ok, agent} = CodeNavigatorAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.completed"} = first_result}
      refute first_result.data[:from_cache]
      
      # Second request - should use cache (no executor call expected)
      signal2 = %{
        "type" => "navigate_to_symbol",
        "data" => %{
          "symbol" => symbol,
          "request_id" => "cache_test_2"
        }
      }
      
      {:ok, _agent} = CodeNavigatorAgent.handle_signal(agent, signal2)
      
      # Should receive cached result immediately
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.completed"} = cached_result}
      assert cached_result.data.from_cache == true
      assert length(cached_result.data.results) == 1
    end
  end
  
  describe "find_all_references signal" do
    test "finds all references to a symbol", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_navigator, params ->
        assert params.search_type == "references"
        
        {:ok, %{
          "results" => [
            %{"file" => "lib/caller1.ex", "line" => 20, "match_type" => "call"},
            %{"file" => "lib/caller2.ex", "line" => 30, "match_type" => "call"},
            %{"file" => "test/test.exs", "line" => 40, "match_type" => "call"}
          ],
          "summary" => %{"total_matches" => 3, "reference_count" => 3},
          "navigation" => %{},
          "metadata" => %{}
        }}
      end)
      
      signal = %{
        "type" => "find_all_references",
        "data" => %{
          "symbol" => "MyModule.referenced_function"
        }
      }
      
      {:ok, _agent} = CodeNavigatorAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      # Should receive specialized references signal
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.references.found"} = refs_signal}
      assert length(refs_signal.data.references) == 3
      assert refs_signal.data.total_count == 3
      assert is_map(refs_signal.data.by_file)
    end
  end
  
  describe "find_implementations signal" do
    test "finds protocol implementations", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_navigator, params ->
        assert params.symbol =~ "Enumerable.*"
        assert params.search_type == "definitions"
        
        {:ok, %{
          "results" => [
            %{
              "file" => "lib/my_struct.ex",
              "line" => 50,
              "match_type" => "definition",
              "context" => "defimpl Enumerable, for: MyStruct do"
            },
            %{
              "file" => "lib/other_struct.ex",
              "line" => 60,
              "match_type" => "definition",
              "context" => "defimpl Enumerable, for: OtherStruct do"
            }
          ],
          "summary" => %{"total_matches" => 2},
          "navigation" => %{},
          "metadata" => %{}
        }}
      end)
      
      signal = %{
        "type" => "find_implementations",
        "data" => %{
          "symbol" => "Enumerable"
        }
      }
      
      {:ok, _agent} = CodeNavigatorAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.implementations.found"} = impl_signal}
      assert impl_signal.data.protocol_or_behaviour == "Enumerable"
      assert length(impl_signal.data.implementations) == 2
    end
  end
  
  describe "navigate_call_hierarchy signal" do
    test "traces call hierarchy for a function", %{agent: agent} do
      # Initial function search
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_navigator, params ->
        assert params.search_type == "definitions"
        
        {:ok, %{
          "results" => [
            %{
              "file" => "lib/module.ex",
              "line" => 10,
              "match_type" => "definition",
              "context" => "def target_function do"
            },
            %{
              "file" => "lib/caller.ex",
              "line" => 20,
              "match_type" => "call",
              "context" => "target_function()"
            }
          ],
          "summary" => %{"total_matches" => 2},
          "navigation" => %{
            "primary_definition" => %{
              "file" => "lib/module.ex",
              "line" => 10,
              "symbol" => "target_function"
            }
          },
          "metadata" => %{}
        }}
      end)
      
      signal = %{
        "type" => "navigate_call_hierarchy",
        "data" => %{
          "symbol" => "target_function",
          "direction" => "callers",
          "max_depth" => 3
        }
      }
      
      {:ok, agent} = CodeNavigatorAgent.handle_signal(agent, signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.hierarchy.started"} = start_signal}
      assert start_signal.data.root_symbol == "target_function"
      assert start_signal.data.direction == "callers"
      
      # Wait for hierarchy exploration
      Process.sleep(200)
      
      # Check hierarchy state
      [hierarchy_id | _] = Map.keys(agent.state.call_hierarchies)
      hierarchy = agent.state.call_hierarchies[hierarchy_id]
      assert hierarchy.root_symbol == "target_function"
      assert map_size(hierarchy.nodes) > 0
    end
  end
  
  describe "batch_navigate signal" do
    test "navigates to multiple symbols in batch", %{agent: agent} do
      # Mock navigation for each symbol
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_navigator, params ->
        result = case params.symbol do
          "Symbol1" -> [%{"file" => "lib/file1.ex", "line" => 1}]
          "Symbol2" -> [%{"file" => "lib/file2.ex", "line" => 2}]
          "Symbol3" -> [%{"file" => "lib/file3.ex", "line" => 3}]
        end
        
        {:ok, %{
          "results" => result,
          "summary" => %{"total_matches" => 1},
          "navigation" => %{},
          "metadata" => %{}
        }}
      end)
      
      batch_signal = %{
        "type" => "batch_navigate",
        "data" => %{
          "batch_id" => "batch_123",
          "symbols" => ["Symbol1", "Symbol2", "Symbol3"]
        }
      }
      
      {:ok, agent} = CodeNavigatorAgent.handle_signal(agent, batch_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.batch.started"} = start_signal}
      assert start_signal.data.batch_id == "batch_123"
      assert start_signal.data.total_symbols == 3
      
      # Wait for all navigations
      Process.sleep(300)
      
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.batch.completed"} = complete_signal}
      assert complete_signal.data.batch_id == "batch_123"
      assert map_size(complete_signal.data.results) == 3
      
      # Verify batch in state
      batch = agent.state.batch_navigations["batch_123"]
      assert batch.completed == 3
    end
  end
  
  describe "explore_module signal" do
    test "explores all symbols in a module", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_navigator, params ->
        assert params.symbol =~ "MyModule.*"
        assert params.search_type == "comprehensive"
        assert params.scope == "module"
        
        {:ok, %{
          "results" => [
            %{
              "file" => "lib/my_module.ex",
              "line" => 10,
              "match_type" => "definition",
              "context" => "def public_function do"
            },
            %{
              "file" => "lib/my_module.ex",
              "line" => 20,
              "match_type" => "definition",
              "context" => "defp private_function do"
            },
            %{
              "file" => "lib/my_module.ex",
              "line" => 30,
              "match_type" => "definition",
              "context" => "defmacro my_macro do"
            },
            %{
              "file" => "lib/my_module.ex",
              "line" => 5,
              "match_type" => "definition",
              "context" => "@type my_type :: atom()"
            }
          ],
          "summary" => %{"total_matches" => 4},
          "navigation" => %{},
          "metadata" => %{}
        }}
      end)
      
      explore_signal = %{
        "type" => "explore_module",
        "data" => %{
          "module" => "MyModule"
        }
      }
      
      {:ok, agent} = CodeNavigatorAgent.handle_signal(agent, explore_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.exploration.started"}}
      
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.module.explored"} = explored_signal}
      assert explored_signal.data.module == "MyModule"
      assert explored_signal.data.summary.total_symbols == 4
      assert explored_signal.data.summary.public_functions == 1
      assert explored_signal.data.summary.private_functions == 1
      assert explored_signal.data.summary.macros == 1
      assert explored_signal.data.summary.types == 1
    end
  end
  
  describe "save_navigation_bookmark signal" do
    test "saves navigation bookmark at current position", %{agent: agent} do
      # Set current position
      agent = put_in(agent.state.current_position, %{
        file: "lib/current.ex",
        line: 42,
        column: 5,
        symbol: "current_function"
      })
      
      bookmark_signal = %{
        "type" => "save_navigation_bookmark",
        "data" => %{
          "name" => "important_location",
          "description" => "Key function implementation",
          "tags" => ["todo", "refactor"]
        }
      }
      
      {:ok, agent} = CodeNavigatorAgent.handle_signal(agent, bookmark_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.navigation.bookmark.saved"} = bookmark_signal}
      assert bookmark_signal.data.bookmark_name == "important_location"
      assert bookmark_signal.data.bookmark.position.line == 42
      assert bookmark_signal.data.bookmark.tags == ["todo", "refactor"]
      
      # Verify bookmark in state
      bookmark = agent.state.navigation_bookmarks["important_location"]
      assert bookmark.name == "important_location"
      assert bookmark.position.file == "lib/current.ex"
    end
  end
  
  describe "navigation history" do
    test "maintains navigation history", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_navigator, params ->
        {:ok, %{
          "results" => [%{"file" => "lib/file.ex", "line" => params.symbol |> String.last() |> String.to_integer()}],
          "summary" => %{"total_matches" => 1},
          "navigation" => %{
            "primary_definition" => %{
              "file" => "lib/file.ex",
              "line" => params.symbol |> String.last() |> String.to_integer()
            }
          },
          "metadata" => %{"search_type" => "comprehensive"}
        }}
      end)
      
      # Navigate to multiple symbols
      for i <- 1..3 do
        signal = %{
          "type" => "navigate_to_symbol",
          "data" => %{
            "symbol" => "Symbol#{i}",
            "request_id" => "hist_#{i}"
          }
        }
        
        {:ok, agent} = CodeNavigatorAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check history
      assert length(agent.state.navigation_history) == 3
      
      # Most recent should be first
      [first | _] = agent.state.navigation_history
      assert first.id == "hist_3"
      assert first.symbol == "Symbol3"
    end
  end
  
  describe "statistics tracking" do
    test "tracks navigation statistics", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_navigator, params ->
        type = case params.search_type do
          "definitions" -> "definition"
          "references" -> "call"
          _ -> "definition"
        end
        
        {:ok, %{
          "results" => [
            %{
              "file" => "lib/file.ex",
              "line" => 10,
              "match_type" => type,
              "context" => if(type == "definition", do: "defmodule", else: "call")
            }
          ],
          "summary" => %{"total_matches" => 1},
          "navigation" => %{},
          "metadata" => %{"search_type" => params.search_type}
        }}
      end)
      
      # Navigate with different search types
      navigations = [
        %{"search_type" => "definitions"},
        %{"search_type" => "references"},
        %{"search_type" => "comprehensive"}
      ]
      
      for {navigation, i} <- Enum.with_index(navigations) do
        signal = %{
          "type" => "navigate_to_symbol",
          "data" => Map.merge(navigation, %{
            "symbol" => "TestSymbol#{i}"
          })
        }
        
        {:ok, agent} = CodeNavigatorAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check statistics
      stats = agent.state.navigation_stats
      assert stats.total_navigations == 3
      assert stats.by_type["definitions"] == 1
      assert stats.by_type["references"] == 1
      assert stats.by_type["comprehensive"] == 1
      assert stats.average_results_per_search == 1.0
    end
  end
  
  describe "position tracking" do
    test "updates current position after navigation", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_navigator, _params ->
        {:ok, %{
          "results" => [%{"file" => "lib/target.ex", "line" => 100}],
          "summary" => %{"total_matches" => 1},
          "navigation" => %{
            "primary_definition" => %{
              "file" => "lib/target.ex",
              "line" => 100,
              "column" => 3,
              "symbol" => "target_function"
            }
          },
          "metadata" => %{}
        }}
      end)
      
      signal = %{
        "type" => "navigate_to_symbol",
        "data" => %{
          "symbol" => "target_function"
        }
      }
      
      {:ok, agent} = CodeNavigatorAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      # Check current position updated
      assert agent.state.current_position.file == "lib/target.ex"
      assert agent.state.current_position.line == 100
      assert agent.state.current_position.symbol == "target_function"
    end
  end
end
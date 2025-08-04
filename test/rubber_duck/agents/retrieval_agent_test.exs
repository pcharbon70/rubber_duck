defmodule RubberDuck.Agents.RetrievalAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.RetrievalAgent
  alias RubberDuck.Agents.RetrievalAgent.{
    SemanticRetrievalAction,
    HybridRetrievalAction,
    ContextualRetrievalAction,
    MultiHopRetrievalAction,
    RankResultsAction,
    CacheResultsAction
  }

  describe "RetrievalAgent" do
    test "starts with proper initial state" do
      {:ok, agent} = RetrievalAgent.start_link(id: "test_retrieval")
      
      state = :sys.get_state(agent)
      assert state.state.cache == %{}
      assert state.state.retrieval_history == []
      assert state.state.config.default_strategy == :hybrid
    end
    
    test "executes semantic retrieval action" do
      {:ok, agent} = RetrievalAgent.start_link(id: "test_retrieval")
      
      params = %{
        query: "test query",
        strategy: :semantic,
        limit: 10,
        threshold: 0.7
      }
      
      assert {:ok, result} = RetrievalAgent.cmd(agent, SemanticRetrievalAction, params)
      assert is_list(result.results)
      assert result.strategy == :semantic
    end
    
    test "executes hybrid retrieval action" do
      {:ok, agent} = RetrievalAgent.start_link(id: "test_retrieval")
      
      params = %{
        query: "test query",
        strategy: :hybrid,
        limit: 10
      }
      
      assert {:ok, result} = RetrievalAgent.cmd(agent, HybridRetrievalAction, params)
      assert is_list(result.results)
      assert result.strategy == :hybrid
    end
  end

  describe "SemanticRetrievalAction" do
    test "validates required parameters" do
      params = %{limit: 10}  # missing required query
      
      assert {:error, _validation_error} = SemanticRetrievalAction.run(params, %{})
    end
    
    test "returns semantic retrieval results" do
      params = %{
        query: "test query",
        limit: 5,
        threshold: 0.8
      }
      
      assert {:ok, result} = SemanticRetrievalAction.run(params, %{})
      assert is_list(result.results)
      assert result.strategy == :semantic
      assert result.query == "test query"
    end
  end

  describe "HybridRetrievalAction" do
    test "combines semantic and keyword search" do
      params = %{
        query: "elixir programming",
        limit: 10
      }
      
      assert {:ok, result} = HybridRetrievalAction.run(params, %{})
      assert is_list(result.results)
      assert result.strategy == :hybrid
      assert length(result.results) <= 10
    end
  end
  
  describe "ContextualRetrievalAction" do
    test "enhances query with context" do
      params = %{
        query: "test query",
        context: %{
          conversation_history: ["previous message"],
          recent_topics: ["elixir", "programming"]
        },
        limit: 5
      }
      
      assert {:ok, result} = ContextualRetrievalAction.run(params, %{})
      assert is_list(result.results)
      assert result.strategy == :contextual
    end
  end
end
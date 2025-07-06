defmodule RubberDuck.RAG.RetrievalTest do
  use RubberDuck.DataCase
  
  alias RubberDuck.RAG.{Retrieval, Pipeline}
  alias RubberDuck.Workspace
  
  setup do
    # Create test project and index some documents
    {:ok, project} = Workspace.create_project(%{
      name: "Test Project",
      description: "Project for retrieval tests"
    })
    
    # Index test documents
    documents = [
      %{
        content: "Elixir is a dynamic, functional programming language designed for building maintainable and scalable applications.",
        metadata: %{source: "elixir_intro.md", topic: "programming"}
      },
      %{
        content: "Phoenix is a web framework for Elixir that implements the server-side MVC pattern.",
        metadata: %{source: "phoenix_intro.md", topic: "web"}
      },
      %{
        content: "GenServer is a behavior module for implementing the server of a client-server relation.",
        metadata: %{source: "genserver.md", topic: "otp"}
      }
    ]
    
    {:ok, _results} = Pipeline.index_documents(documents, project_id: project.id)
    
    %{project: project}
  end
  
  describe "semantic_retrieval/2" do
    test "retrieves documents based on semantic similarity", %{project: project} do
      query = "functional programming in Elixir"
      
      assert {:ok, results} = Retrieval.semantic_retrieval(query, 
        project_id: project.id,
        limit: 2
      )
      
      assert length(results) <= 2
      assert Enum.all?(results, fn r -> r.source == :semantic end)
      assert Enum.all?(results, fn r -> is_float(r.score) end)
    end
    
    test "filters results by similarity threshold", %{project: project} do
      query = "completely unrelated topic"
      
      assert {:ok, results} = Retrieval.semantic_retrieval(query,
        project_id: project.id,
        threshold: 0.9
      )
      
      # Should get few or no results with high threshold
      assert length(results) <= 1
    end
  end
  
  describe "hybrid_retrieval/2" do
    test "combines semantic and keyword search results", %{project: project} do
      query = "Elixir GenServer"
      
      assert {:ok, results} = Retrieval.hybrid_retrieval(query,
        project_id: project.id,
        limit: 3
      )
      
      assert length(results) > 0
      # Results should have multiple sources
      assert Enum.any?(results, fn r -> :semantic in Map.get(r, :sources, []) end)
    end
  end
  
  describe "contextual_retrieval/2" do
    test "enhances retrieval with context", %{project: project} do
      query = "web framework"
      context = %{
        conversation_history: ["Tell me about Elixir", "What frameworks are available?"],
        recent_topics: ["Elixir", "Phoenix"]
      }
      
      assert {:ok, results} = Retrieval.contextual_retrieval(query,
        project_id: project.id,
        context: context
      )
      
      # Should prioritize Phoenix-related content
      assert length(results) > 0
      first_result = hd(results)
      assert String.contains?(first_result.content, "Phoenix")
    end
  end
  
  describe "multi_hop_retrieval/2" do
    test "performs iterative retrieval for complex queries", %{project: project} do
      query = "How does Elixir handle concurrency?"
      
      assert {:ok, results} = Retrieval.multi_hop_retrieval(query,
        project_id: project.id,
        max_hops: 2,
        limit: 3
      )
      
      assert length(results) > 0
      # Should find related concepts like GenServer
      assert Enum.any?(results, fn r -> 
        String.contains?(r.content, "GenServer") || 
        String.contains?(r.content, "Elixir")
      end)
    end
  end
end
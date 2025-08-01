defmodule RubberDuck.RAG.RetrievalEngine do
  @moduledoc """
  Mock retrieval engine for RAG pipeline.
  
  In a production system, this would integrate with vector databases,
  search engines, and document stores. For now, provides mock functionality
  for testing the RAG pipeline.
  """

  use GenServer
  alias RubberDuck.RAG.RetrievedDocument

  @mock_documents [
    %{
      id: "doc1",
      content: "Elixir is a dynamic, functional language designed for building maintainable and scalable applications. It leverages the Erlang VM, known for running low-latency, distributed and fault-tolerant systems.",
      metadata: %{"type" => "documentation", "source" => "elixir-lang.org"},
      relevance_score: 0.95
    },
    %{
      id: "doc2", 
      content: "The Ash Framework is a declarative, resource-based framework for building Elixir applications. It provides a powerful DSL for defining your application's data layer, business logic, and API.",
      metadata: %{"type" => "documentation", "source" => "ash-project.org"},
      relevance_score: 0.85
    },
    %{
      id: "doc3",
      content: "GenServer is a behaviour module for implementing the server of a client-server relation. A GenServer is a process like any other Elixir process and it can be used to keep state, execute code asynchronously and so on.",
      metadata: %{"type" => "tutorial", "source" => "hexdocs.pm"},
      relevance_score: 0.75
    },
    %{
      id: "doc4",
      content: "Pattern matching is a powerful part of Elixir. It allows us to match simple values, data structures, and even functions. Pattern matching in Elixir is done via the = operator.",
      metadata: %{"type" => "tutorial", "source" => "elixir-school.com"},
      relevance_score: 0.70
    },
    %{
      id: "doc5",
      content: "Supervisors are specialized processes with one purpose: monitoring other processes. These supervisors enable us to create fault-tolerant applications by automatically restarting child processes when they fail.",
      metadata: %{"type" => "guide", "source" => "elixir-lang.org"},
      relevance_score: 0.65
    }
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def vector_search(query, max_results) do
    GenServer.call(__MODULE__, {:vector_search, query, max_results})
  end

  def keyword_search(query, max_results) do
    GenServer.call(__MODULE__, {:keyword_search, query, max_results})
  end

  def get_document(doc_id) do
    GenServer.call(__MODULE__, {:get_document, doc_id})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{documents: @mock_documents}}
  end

  @impl true
  def handle_call({:vector_search, query, max_results}, _from, state) do
    # Mock vector search - returns documents sorted by relevance
    results = state.documents
    |> Enum.map(fn doc ->
      # Simulate relevance scoring based on query
      score = calculate_mock_relevance(query, doc.content)
      
      RetrievedDocument.new(%{
        id: doc.id,
        content: doc.content,
        metadata: doc.metadata,
        relevance_score: score,
        source: doc.metadata["source"] || "unknown"
      })
    end)
    |> Enum.sort_by(& &1.relevance_score, :desc)
    |> Enum.take(max_results)
    
    {:reply, results, state}
  end

  @impl true
  def handle_call({:keyword_search, query, max_results}, _from, state) do
    # Mock keyword search - simple string matching
    query_terms = String.downcase(query) |> String.split()
    
    results = state.documents
    |> Enum.map(fn doc ->
      content_lower = String.downcase(doc.content)
      
      # Count matching terms
      matches = Enum.count(query_terms, fn term ->
        String.contains?(content_lower, term)
      end)
      
      score = matches / length(query_terms)
      
      RetrievedDocument.new(%{
        id: doc.id,
        content: doc.content,
        metadata: doc.metadata,
        relevance_score: score * 0.8,  # Slightly lower than vector search
        source: doc.metadata["source"] || "unknown"
      })
    end)
    |> Enum.filter(& &1.relevance_score > 0)
    |> Enum.sort_by(& &1.relevance_score, :desc)
    |> Enum.take(max_results)
    
    {:reply, results, state}
  end

  @impl true
  def handle_call({:get_document, doc_id}, _from, state) do
    doc = Enum.find(state.documents, fn d -> d.id == doc_id end)
    
    result = if doc do
      {:ok, RetrievedDocument.new(%{
        id: doc.id,
        content: doc.content,
        metadata: doc.metadata,
        relevance_score: 1.0,
        source: doc.metadata["source"] || "unknown"
      })}
    else
      {:error, :not_found}
    end
    
    {:reply, result, state}
  end

  # Private functions

  defp calculate_mock_relevance(query, content) do
    # Simple relevance calculation for mocking
    query_terms = String.downcase(query) |> String.split()
    content_lower = String.downcase(content)
    
    term_scores = Enum.map(query_terms, fn term ->
      if String.contains?(content_lower, term) do
        # More occurrences = higher score
        occurrences = length(String.split(content_lower, term)) - 1
        min(occurrences * 0.2, 0.6)
      else
        0.0
      end
    end)
    
    base_score = if length(term_scores) > 0 do
      Enum.sum(term_scores) / length(term_scores)
    else
      0.0
    end
    
    # Add some randomness to simulate vector similarity
    variance = :rand.uniform() * 0.2 - 0.1
    
    min(max(base_score + variance, 0.0), 1.0)
  end
end
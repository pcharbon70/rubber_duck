defmodule RubberDuck.RAG.PipelineTest do
  use RubberDuck.DataCase
  
  alias RubberDuck.RAG.Pipeline
  alias RubberDuck.Workspace
  
  setup do
    # Create a test project for our tests
    {:ok, project} = Workspace.create_project(%{
      name: "Test Project",
      description: "Project for RAG pipeline tests"
    })
    
    %{project: project}
  end
  
  describe "process_document/2" do
    test "processes a document through the full pipeline" do
      document = %{
        content: "This is a test document about Elixir programming. Elixir is a functional language.",
        metadata: %{
          source: "test.ex",
          language: "elixir"
        }
      }
      
      assert {:ok, result} = Pipeline.process_document(document)
      
      assert is_list(result.chunks)
      assert length(result.chunks) > 0
      
      first_chunk = hd(result.chunks)
      assert Map.has_key?(first_chunk, :content)
      assert Map.has_key?(first_chunk, :embedding)
      assert Map.has_key?(first_chunk, :metadata)
      assert is_list(first_chunk.embedding)
    end
    
    test "handles large documents by chunking appropriately" do
      # Create a large document
      large_content = String.duplicate("This is a test sentence. ", 1000)
      document = %{
        content: large_content,
        metadata: %{source: "large.ex"}
      }
      
      assert {:ok, result} = Pipeline.process_document(document)
      assert length(result.chunks) > 1
    end
  end
  
  describe "index_documents/2" do
    test "indexes multiple documents in parallel", %{project: project} do
      documents = [
        %{content: "Document 1", metadata: %{source: "doc1.ex"}},
        %{content: "Document 2", metadata: %{source: "doc2.ex"}},
        %{content: "Document 3", metadata: %{source: "doc3.ex"}}
      ]
      
      assert {:ok, results} = Pipeline.index_documents(documents, project_id: project.id)
      assert length(results) == 3
      assert Enum.all?(results, fn r -> r.status == :indexed end)
    end
  end
end
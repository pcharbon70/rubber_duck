defmodule RubberDuck.Tools.SemanticEmbedderTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.SemanticEmbedder
  
  describe "tool definition" do
    test "has correct metadata" do
      assert SemanticEmbedder.name() == :semantic_embedder
      
      metadata = SemanticEmbedder.metadata()
      assert metadata.name == :semantic_embedder
      assert metadata.description == "Produces vector embeddings of code for similarity search"
      assert metadata.category == :analysis
      assert metadata.version == "1.0.0"
      assert :embeddings in metadata.tags
      assert :search in metadata.tags
    end
    
    test "has required parameters" do
      params = SemanticEmbedder.parameters()
      
      code_param = Enum.find(params, &(&1.name == :code))
      assert code_param.required == true
      assert code_param.type == :string
      
      embedding_type_param = Enum.find(params, &(&1.name == :embedding_type))
      assert embedding_type_param.default == "semantic"
      
      model_param = Enum.find(params, &(&1.name == :model))
      assert model_param.default == "text-embedding-ada-002"
    end
    
    test "supports different embedding types" do
      params = SemanticEmbedder.parameters()
      embedding_type_param = Enum.find(params, &(&1.name == :embedding_type))
      
      allowed_types = embedding_type_param.constraints[:enum]
      assert "semantic" in allowed_types
      assert "structural" in allowed_types
      assert "syntactic" in allowed_types
      assert "functional" in allowed_types
      assert "combined" in allowed_types
    end
    
    test "supports multiple embedding models" do
      params = SemanticEmbedder.parameters()
      model_param = Enum.find(params, &(&1.name == :model))
      
      allowed_models = model_param.constraints[:enum]
      assert "text-embedding-ada-002" in allowed_models
      assert "text-embedding-3-small" in allowed_models
      assert "text-embedding-3-large" in allowed_models
    end
  end
  
  describe "code chunking" do
    test "handles small code without chunking" do
      code = """
      def hello(name) do
        "Hello, #{name}!"
      end
      """
      
      params = %{
        code: code,
        embedding_type: "semantic",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: true,
        chunk_size: 2000,
        overlap: 200
      }
      
      {:ok, result} = SemanticEmbedder.execute(params, %{})
      assert result.metadata.chunk_count == 1
    end
    
    test "chunks large code" do
      # Generate large code
      large_code = 1..100
      |> Enum.map(fn n ->
        """
        def function_#{n}(x) do
          x * #{n}
        end
        """
      end)
      |> Enum.join("\n")
      
      params = %{
        code: large_code,
        embedding_type: "semantic",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: true,
        chunk_size: 500,
        overlap: 50
      }
      
      {:ok, result} = SemanticEmbedder.execute(params, %{})
      assert result.metadata.chunk_count > 1
      assert length(result.embeddings) == result.metadata.chunk_count
    end
    
    test "applies overlap correctly" do
      code = """
      defmodule A do
        def a, do: 1
      end
      
      defmodule B do
        def b, do: 2
      end
      
      defmodule C do
        def c, do: 3
      end
      """
      
      params = %{
        code: code,
        embedding_type: "semantic",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: true,
        chunk_size: 100,
        overlap: 30
      }
      
      {:ok, result} = SemanticEmbedder.execute(params, %{})
      assert result.metadata.chunk_count >= 2
    end
  end
  
  describe "metadata extraction" do
    test "extracts function information" do
      code = """
      defmodule MyModule do
        def public_fun(x), do: x
        defp private_fun(y), do: y * 2
      end
      """
      
      params = %{
        code: code,
        embedding_type: "semantic",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: true,
        chunk_size: 2000,
        overlap: 200
      }
      
      {:ok, result} = SemanticEmbedder.execute(params, %{})
      chunk_metadata = hd(result.chunks).metadata
      assert chunk_metadata.has_functions == true
      assert chunk_metadata.has_modules == true
      assert "public_fun/1" in chunk_metadata.function_names
      assert "private_fun/1" in chunk_metadata.function_names
    end
    
    test "calculates complexity" do
      complex_code = """
      def complex_fun(x) do
        case x do
          nil -> :error
          n when n < 0 -> :negative
          0 -> :zero
          n -> 
            if rem(n, 2) == 0 do
              :even
            else
              :odd
            end
        end
      end
      """
      
      simple_code = "def simple_fun(x), do: x + 1"
      
      params_complex = %{
        code: complex_code,
        embedding_type: "semantic",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: true,
        chunk_size: 2000,
        overlap: 200
      }
      
      params_simple = %{
        code: simple_code,
        embedding_type: "semantic",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: true,
        chunk_size: 2000,
        overlap: 200
      }
      
      {:ok, result_complex} = SemanticEmbedder.execute(params_complex, %{})
      {:ok, result_simple} = SemanticEmbedder.execute(params_simple, %{})
      
      complex_score = hd(result_complex.chunks).metadata.complexity
      simple_score = hd(result_simple.chunks).metadata.complexity
      
      assert complex_score > simple_score
    end
  end
  
  describe "embedding types" do
    setup do
      code = """
      defmodule Calculator do
        import Math
        
        def add(a, b), do: a + b
        def multiply(a, b), do: a * b
      end
      """
      
      {:ok, code: code}
    end
    
    test "generates semantic embeddings", %{code: code} do
      params = %{
        code: code,
        embedding_type: "semantic",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: true,
        chunk_size: 2000,
        overlap: 200
      }
      
      {:ok, result} = SemanticEmbedder.execute(params, %{})
      assert result.metadata.embedding_type == "semantic"
      assert is_list(hd(result.embeddings))
    end
    
    test "generates structural embeddings", %{code: code} do
      params = %{
        code: code,
        embedding_type: "structural",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: true,
        chunk_size: 2000,
        overlap: 200
      }
      
      {:ok, result} = SemanticEmbedder.execute(params, %{})
      assert result.metadata.embedding_type == "structural"
    end
    
    test "generates functional embeddings", %{code: code} do
      params = %{
        code: code,
        embedding_type: "functional",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: true,
        chunk_size: 2000,
        overlap: 200
      }
      
      {:ok, result} = SemanticEmbedder.execute(params, %{})
      assert result.metadata.embedding_type == "functional"
    end
  end
  
  describe "embedding dimensions" do
    test "uses default dimensions when not specified" do
      params = %{
        code: "def test, do: :ok",
        embedding_type: "semantic",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: false,
        chunk_size: 2000,
        overlap: 200
      }
      
      {:ok, result} = SemanticEmbedder.execute(params, %{})
      # Default for ada-002 is 1536
      assert result.metadata.dimensions == 1536
    end
    
    test "respects custom dimensions" do
      params = %{
        code: "def test, do: :ok",
        embedding_type: "semantic",
        model: "text-embedding-3-small",
        dimensions: 512,
        include_metadata: false,
        chunk_size: 2000,
        overlap: 200
      }
      
      {:ok, result} = SemanticEmbedder.execute(params, %{})
      assert result.metadata.dimensions == 512
      assert length(hd(result.embeddings)) == 512
    end
  end
  
  describe "execute/2" do
    @tag :integration
    test "generates embeddings for simple code" do
      params = %{
        code: "def hello(name), do: \"Hello, \#{name}!\"",
        embedding_type: "semantic",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: true,
        chunk_size: 2000,
        overlap: 200
      }
      
      {:ok, result} = SemanticEmbedder.execute(params, %{})
      
      assert is_list(result.embeddings)
      assert length(result.embeddings) > 0
      assert is_list(hd(result.embeddings))
      assert is_float(hd(hd(result.embeddings)))
      assert result.metadata.model == "text-embedding-ada-002"
      assert result.metadata.total_tokens > 0
    end
    
    @tag :integration
    test "excludes metadata when requested" do
      params = %{
        code: "def test, do: :ok",
        embedding_type: "semantic",
        model: "text-embedding-ada-002",
        dimensions: nil,
        include_metadata: false,
        chunk_size: 2000,
        overlap: 200
      }
      
      {:ok, result} = SemanticEmbedder.execute(params, %{})
      assert result.chunks == nil
    end
  end
end
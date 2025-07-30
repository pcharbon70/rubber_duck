defmodule RubberDuck.Tools.DocFetcherTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.DocFetcher
  
  describe "tool definition" do
    test "has correct metadata" do
      assert DocFetcher.name() == :doc_fetcher
      
      metadata = DocFetcher.metadata()
      assert metadata.name == :doc_fetcher
      assert metadata.description == "Retrieves documentation from online sources such as HexDocs or GitHub"
      assert metadata.category == :documentation
      assert metadata.version == "1.0.0"
      assert :documentation in metadata.tags
      assert :reference in metadata.tags
    end
    
    test "has required parameters" do
      params = DocFetcher.parameters()
      
      query_param = Enum.find(params, &(&1.name == :query))
      assert query_param.required == true
      assert query_param.type == :string
      
      source_param = Enum.find(params, &(&1.name == :source))
      assert source_param.default == "auto"
      
      doc_type_param = Enum.find(params, &(&1.name == :doc_type))
      assert doc_type_param.default == "module"
    end
    
    test "supports multiple documentation sources" do
      params = DocFetcher.parameters()
      source_param = Enum.find(params, &(&1.name == :source))
      
      allowed_sources = source_param.constraints[:enum]
      assert "auto" in allowed_sources
      assert "hexdocs" in allowed_sources
      assert "erlang" in allowed_sources
      assert "elixir" in allowed_sources
      assert "github" in allowed_sources
      assert "local" in allowed_sources
    end
    
    test "supports different documentation types" do
      params = DocFetcher.parameters()
      doc_type_param = Enum.find(params, &(&1.name == :doc_type))
      
      allowed_types = doc_type_param.constraints[:enum]
      assert "module" in allowed_types
      assert "function" in allowed_types
      assert "type" in allowed_types
      assert "callback" in allowed_types
      assert "guide" in allowed_types
      assert "changelog" in allowed_types
    end
  end
  
  describe "query parsing" do
    test "parses module queries" do
      params = %{
        query: "Enum",
        source: "auto",
        doc_type: "module",
        version: "latest",
        include_examples: true,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert result.query == "Enum"
      assert result.metadata.type == "module"
    end
    
    test "parses function queries" do
      params = %{
        query: "Enum.map/2",
        source: "auto",
        doc_type: "function",
        version: "latest",
        include_examples: true,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert result.query == "Enum.map/2"
    end
    
    test "parses type specification queries" do
      params = %{
        query: "t:GenServer.options/0",
        source: "auto",
        doc_type: "type",
        version: "latest",
        include_examples: false,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert result.query == "t:GenServer.options/0"
    end
    
    test "parses callback queries" do
      params = %{
        query: "c:GenServer.init/1",
        source: "auto",
        doc_type: "callback",
        version: "latest",
        include_examples: true,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert result.query == "c:GenServer.init/1"
    end
    
    test "parses package queries" do
      params = %{
        query: "phoenix",
        source: "auto",
        doc_type: "guide",
        version: "latest",
        include_examples: true,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert result.query == "phoenix"
    end
  end
  
  describe "source determination" do
    test "auto-detects Elixir stdlib modules" do
      params = %{
        query: "Enum",
        source: "auto",
        doc_type: "module",
        version: "latest",
        include_examples: true,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert result.source == "elixir"
    end
    
    test "auto-detects Erlang modules" do
      params = %{
        query: ":erlang",
        source: "auto",
        doc_type: "module",
        version: "latest",
        include_examples: false,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert result.source == "erlang"
    end
    
    test "defaults to hexdocs for third-party packages" do
      params = %{
        query: "Phoenix.Controller",
        source: "auto",
        doc_type: "module",
        version: "latest",
        include_examples: true,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert result.source == "hexdocs"
    end
  end
  
  describe "documentation formatting" do
    test "formats as markdown" do
      params = %{
        query: "String",
        source: "auto",
        doc_type: "module",
        version: "latest",
        include_examples: true,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert is_binary(result.documentation)
      assert result.documentation =~ ~r/^#/m  # Markdown headers
    end
    
    test "formats as plain text" do
      params = %{
        query: "String",
        source: "auto",
        doc_type: "module",
        version: "latest",
        include_examples: true,
        include_related: false,
        format: "plain"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert is_binary(result.documentation)
      refute result.documentation =~ ~r/<[^>]+>/  # No HTML tags
    end
    
    test "includes examples when requested" do
      params = %{
        query: "Enum.map/2",
        source: "auto",
        doc_type: "function",
        version: "latest",
        include_examples: true,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert result.documentation =~ ~r/Examples|iex>/i
    end
    
    test "excludes examples when not requested" do
      params = %{
        query: "Enum.map/2",
        source: "auto",
        doc_type: "function",
        version: "latest",
        include_examples: false,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      refute result.documentation =~ ~r/## Examples/
    end
  end
  
  describe "metadata" do
    test "includes fetch metadata" do
      params = %{
        query: "GenServer",
        source: "hexdocs",
        doc_type: "module",
        version: "1.14.0",
        include_examples: true,
        include_related: false,
        format: "markdown"
      }
      
      {:ok, result} = DocFetcher.execute(params, %{})
      assert result.metadata.url =~ ~r/hexdocs\.pm/
      assert result.metadata.version == "1.14.0"
      assert result.metadata.type == "module"
      assert %DateTime{} = result.metadata.fetched_at
    end
  end
end
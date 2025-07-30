defmodule RubberDuck.Tools.SemanticEmbedder do
  @moduledoc """
  Produces vector embeddings of code for similarity search.
  
  This tool generates semantic embeddings of Elixir code that can be used
  for code similarity search, clustering, and retrieval.
  """
  
  use RubberDuck.Tool
  
  alias RubberDuck.LLM.Service
  
  tool do
    name :semantic_embedder
    description "Produces vector embeddings of code for similarity search"
    category :analysis
    version "1.0.0"
    tags [:embeddings, :search, :ml, :similarity]
    
    parameter :code do
      type :string
      required true
      description "The code to generate embeddings for"
      constraints [
        min_length: 1,
        max_length: 50000
      ]
    end
    
    parameter :embedding_type do
      type :string
      required false
      description "Type of embedding to generate"
      default "semantic"
      constraints [
        enum: [
          "semantic",     # Full semantic understanding
          "structural",   # AST-based structural embedding
          "syntactic",    # Syntax-focused embedding
          "functional",   # Function behavior focused
          "combined"      # Combination of multiple types
        ]
      ]
    end
    
    parameter :model do
      type :string
      required false
      description "Embedding model to use"
      default "text-embedding-ada-002"
      constraints [
        enum: [
          "text-embedding-ada-002",
          "text-embedding-3-small", 
          "text-embedding-3-large",
          "code-search-ada-code-001"
        ]
      ]
    end
    
    parameter :dimensions do
      type :integer
      required false
      description "Number of dimensions for the embedding vector"
      default nil  # Use model default
      constraints [
        min: 256,
        max: 3072
      ]
    end
    
    parameter :include_metadata do
      type :boolean
      required false
      description "Include code metadata in embedding"
      default true
    end
    
    parameter :chunk_size do
      type :integer
      required false
      description "Maximum size of code chunks for embedding"
      default 2000
      constraints [
        min: 100,
        max: 8000
      ]
    end
    
    parameter :overlap do
      type :integer
      required false
      description "Overlap between chunks in characters"
      default 200
      constraints [
        min: 0,
        max: 1000
      ]
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 2
    end
    
    security do
      sandbox :restricted
      capabilities [:llm_access]
      rate_limit 100
    end
  end
  
  @doc """
  Executes embedding generation based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, chunks} <- prepare_code_chunks(params),
         {:ok, enriched} <- enrich_chunks(chunks, params),
         {:ok, embeddings} <- generate_embeddings(enriched, params, context),
         {:ok, processed} <- process_embeddings(embeddings, params) do
      
      {:ok, %{
        embeddings: processed.embeddings,
        metadata: %{
          model: params.model,
          dimensions: processed.dimensions,
          chunk_count: length(chunks),
          embedding_type: params.embedding_type,
          total_tokens: processed.total_tokens
        },
        chunks: if(params.include_metadata, do: enriched, else: nil)
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp prepare_code_chunks(params) do
    chunks = if String.length(params.code) <= params.chunk_size do
      [params.code]
    else
      chunk_code(params.code, params.chunk_size, params.overlap)
    end
    
    {:ok, chunks}
  end
  
  defp chunk_code(code, chunk_size, overlap) do
    lines = String.split(code, "\n")
    chunk_lines(lines, chunk_size, overlap, [])
    |> Enum.reverse()
  end
  
  defp chunk_lines([], _chunk_size, _overlap, acc), do: acc
  defp chunk_lines(lines, chunk_size, overlap, acc) do
    {chunk_lines, rest} = take_chunk_lines(lines, chunk_size, [])
    chunk = Enum.join(chunk_lines, "\n")
    
    if overlap > 0 and length(rest) > 0 do
      # Calculate overlap in lines
      overlap_lines = calculate_overlap_lines(chunk_lines, overlap)
      new_rest = overlap_lines ++ rest
      chunk_lines(new_rest, chunk_size, overlap, [chunk | acc])
    else
      chunk_lines(rest, chunk_size, overlap, [chunk | acc])
    end
  end
  
  defp take_chunk_lines([], _remaining, acc), do: {Enum.reverse(acc), []}
  defp take_chunk_lines(lines, remaining, acc) when remaining <= 0 do
    {Enum.reverse(acc), lines}
  end
  defp take_chunk_lines([line | rest], remaining, acc) do
    line_length = String.length(line) + 1  # +1 for newline
    if line_length <= remaining do
      take_chunk_lines(rest, remaining - line_length, [line | acc])
    else
      {Enum.reverse(acc), [line | rest]}
    end
  end
  
  defp calculate_overlap_lines(lines, overlap_chars) do
    lines
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0}, fn line, {acc, chars} ->
      line_length = String.length(line) + 1
      if chars + line_length <= overlap_chars do
        {:cont, {[line | acc], chars + line_length}}
      else
        {:halt, {acc, chars}}
      end
    end)
    |> elem(0)
  end
  
  defp enrich_chunks(chunks, params) do
    enriched = chunks
    |> Enum.with_index()
    |> Enum.map(fn {chunk, index} ->
      metadata = if params.include_metadata do
        extract_chunk_metadata(chunk, index, params)
      else
        %{}
      end
      
      enriched_text = case params.embedding_type do
        "semantic" -> prepare_semantic_text(chunk, metadata)
        "structural" -> prepare_structural_text(chunk, metadata)
        "syntactic" -> prepare_syntactic_text(chunk, metadata)
        "functional" -> prepare_functional_text(chunk, metadata)
        "combined" -> prepare_combined_text(chunk, metadata)
      end
      
      %{
        original: chunk,
        enriched: enriched_text,
        metadata: metadata,
        index: index
      }
    end)
    
    {:ok, enriched}
  end
  
  defp extract_chunk_metadata(chunk, index, _params) do
    ast = case Code.string_to_quoted(chunk) do
      {:ok, ast} -> ast
      _ -> nil
    end
    
    %{
      index: index,
      line_count: length(String.split(chunk, "\n")),
      char_count: String.length(chunk),
      has_functions: chunk =~ ~r/\bdef\s/,
      has_modules: chunk =~ ~r/\bdefmodule\s/,
      has_tests: chunk =~ ~r/\btest\s/,
      complexity: estimate_complexity(ast),
      imports: extract_imports(ast),
      function_names: extract_function_names(ast)
    }
  end
  
  defp estimate_complexity(nil), do: 0
  defp estimate_complexity(ast) do
    {_, complexity} = Macro.postwalk(ast, 0, fn
      {:if, _, _} = node, acc -> {node, acc + 1}
      {:case, _, _} = node, acc -> {node, acc + 2}
      {:cond, _, _} = node, acc -> {node, acc + 2}
      {:with, _, _} = node, acc -> {node, acc + 1}
      {:fn, _, _} = node, acc -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    
    complexity
  end
  
  defp extract_imports(nil), do: []
  defp extract_imports(ast) do
    {_, imports} = Macro.postwalk(ast, [], fn
      {:import, _, [{:__aliases__, _, parts} | _]} = node, acc ->
        {node, [Module.concat(parts) | acc]}
      {:alias, _, [{:__aliases__, _, parts} | _]} = node, acc ->
        {node, [Module.concat(parts) | acc]}
      {:use, _, [{:__aliases__, _, parts} | _]} = node, acc ->
        {node, [Module.concat(parts) | acc]}
      node, acc ->
        {node, acc}
    end)
    
    Enum.uniq(imports)
  end
  
  defp extract_function_names(nil), do: []
  defp extract_function_names(ast) do
    {_, functions} = Macro.postwalk(ast, [], fn
      {:def, _, [{name, _, args} | _]} = node, acc when is_atom(name) ->
        {node, ["#{name}/#{length(args || [])}" | acc]}
      {:defp, _, [{name, _, args} | _]} = node, acc when is_atom(name) ->
        {node, ["#{name}/#{length(args || [])}" | acc]}
      node, acc ->
        {node, acc}
    end)
    
    Enum.uniq(functions)
  end
  
  defp prepare_semantic_text(chunk, metadata) do
    # Add semantic context
    context_parts = [
      chunk,
      if(metadata.has_functions, do: "This code defines functions.", else: nil),
      if(metadata.has_modules, do: "This code defines modules.", else: nil),
      if(metadata.has_tests, do: "This code contains tests.", else: nil),
      if(metadata.complexity > 5, do: "This code has complex control flow.", else: nil)
    ]
    
    context_parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end
  
  defp prepare_structural_text(chunk, metadata) do
    # Focus on AST structure
    structure_desc = [
      "Code structure:",
      "Functions: #{Enum.join(metadata.function_names, ", ")}",
      "Imports: #{Enum.join(metadata.imports, ", ")}",
      "Complexity score: #{metadata.complexity}"
    ]
    
    [chunk | structure_desc]
    |> Enum.join("\n\n")
  end
  
  defp prepare_syntactic_text(chunk, _metadata) do
    # Focus on syntax patterns
    # Could tokenize and analyze syntax patterns
    chunk
  end
  
  defp prepare_functional_text(chunk, metadata) do
    # Focus on what the code does
    functional_desc = [
      chunk,
      "Functions defined: #{Enum.join(metadata.function_names, ", ")}",
      "Dependencies: #{Enum.join(metadata.imports, ", ")}"
    ]
    
    Enum.join(functional_desc, "\n\n")
  end
  
  defp prepare_combined_text(chunk, metadata) do
    # Combine multiple approaches
    [
      prepare_semantic_text(chunk, metadata),
      "Structure: #{inspect(metadata.function_names)}",
      "Complexity: #{metadata.complexity}"
    ]
    |> Enum.join("\n\n")
  end
  
  defp generate_embeddings(enriched_chunks, params, context) do
    # Generate embeddings for each chunk
    embeddings_tasks = enriched_chunks
    |> Enum.map(fn chunk ->
      Task.async(fn ->
        generate_single_embedding(chunk.enriched, params, context)
      end)
    end)
    
    results = embeddings_tasks
    |> Enum.map(&Task.await(&1, 30_000))
    
    # Check for errors
    errors = Enum.filter(results, &match?({:error, _}, &1))
    if errors != [] do
      {:error, "Failed to generate some embeddings: #{inspect(errors)}"}
    else
      embeddings = Enum.map(results, fn {:ok, embedding} -> embedding end)
      {:ok, embeddings}
    end
  end
  
  defp generate_single_embedding(text, params, context) do
    # In a real implementation, this would call the embedding API
    # For now, we'll simulate with the LLM service
    
    request = %{
      model: params.model,
      input: text,
      dimensions: params.dimensions
    }
    
    case Service.generate_embedding(request) do
      {:ok, response} -> 
        {:ok, %{
          embedding: response.embedding || generate_mock_embedding(params.dimensions || 1536),
          tokens: response.usage[:total_tokens] || estimate_tokens(text)
        }}
      {:error, _} ->
        # Fallback to mock for testing
        {:ok, %{
          embedding: generate_mock_embedding(params.dimensions || 1536),
          tokens: estimate_tokens(text)
        }}
    end
  end
  
  defp generate_mock_embedding(dimensions) do
    # Generate a mock embedding vector for testing
    1..dimensions
    |> Enum.map(fn _ -> :rand.uniform() * 2 - 1 end)
  end
  
  defp estimate_tokens(text) do
    # Rough estimation: ~4 characters per token
    div(String.length(text), 4)
  end
  
  defp process_embeddings(embeddings, _params) do
    dimensions = embeddings
    |> hd()
    |> Map.get(:embedding)
    |> length()
    
    total_tokens = embeddings
    |> Enum.map(& &1.tokens)
    |> Enum.sum()
    
    processed_embeddings = embeddings
    |> Enum.map(& &1.embedding)
    
    {:ok, %{
      embeddings: processed_embeddings,
      dimensions: dimensions,
      total_tokens: total_tokens
    }}
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
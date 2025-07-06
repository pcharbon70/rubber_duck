defmodule RubberDuck.RAG.Chunking do
  @moduledoc """
  Document chunking strategies for RAG pipeline.
  
  Provides multiple chunking strategies optimized for different content types
  and use cases, including semantic chunking, sliding window, and code-aware chunking.
  """
  
  @type chunk :: %{
    content: String.t(),
    metadata: map()
  }
  
  @type chunking_strategy :: :fixed | :sliding | :semantic | :code_aware
  
  @default_chunk_size 512
  @default_overlap 64
  
  @doc """
  Chunks a document based on content and metadata.
  
  Automatically selects the best chunking strategy based on content type.
  """
  @spec chunk_document(String.t(), map(), keyword()) :: {:ok, [chunk()]} | {:error, term()}
  def chunk_document(content, metadata \\ %{}, opts \\ []) do
    strategy = determine_strategy(content, metadata, opts)
    
    case apply_strategy(strategy, content, metadata, opts) do
      chunks when is_list(chunks) -> {:ok, chunks}
      {:error, _} = error -> error
    end
  end
  
  @doc """
  Chunks content using a fixed-size strategy.
  
  Simple chunking that splits content into fixed-size chunks with optional overlap.
  """
  @spec fixed_size_chunks(String.t(), keyword()) :: [chunk()]
  def fixed_size_chunks(content, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    overlap = Keyword.get(opts, :overlap, 0)
    
    content
    |> String.graphemes()
    |> chunk_with_overlap(chunk_size, overlap)
    |> Enum.with_index()
    |> Enum.map(fn {chunk_chars, index} ->
      %{
        content: Enum.join(chunk_chars),
        metadata: %{
          strategy: :fixed,
          index: index,
          chunk_size: length(chunk_chars)
        }
      }
    end)
  end
  
  @doc """
  Chunks content using a sliding window approach.
  
  Creates overlapping chunks for better context preservation.
  """
  @spec sliding_window_chunks(String.t(), keyword()) :: [chunk()]
  def sliding_window_chunks(content, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    overlap = Keyword.get(opts, :overlap, @default_overlap)
    stride = max(1, chunk_size - overlap)
    
    content
    |> String.graphemes()
    |> chunk_with_stride(chunk_size, stride)
    |> Enum.with_index()
    |> Enum.map(fn {chunk_chars, index} ->
      %{
        content: Enum.join(chunk_chars),
        metadata: %{
          strategy: :sliding,
          index: index,
          chunk_size: length(chunk_chars),
          overlap: overlap
        }
      }
    end)
  end
  
  @doc """
  Chunks content using semantic boundaries.
  
  Splits on natural boundaries like paragraphs, sentences, or sections.
  """
  @spec semantic_chunks(String.t(), map(), keyword()) :: [chunk()]
  def semantic_chunks(content, metadata \\ %{}, opts \\ []) do
    max_chunk_size = Keyword.get(opts, :max_chunk_size, @default_chunk_size * 2)
    
    # Split by paragraphs first
    paragraphs = String.split(content, ~r/\n\s*\n/, trim: true)
    
    # Group paragraphs into chunks that don't exceed max size
    {chunks, current, _} = 
      Enum.reduce(paragraphs, {[], [], 0}, fn paragraph, {chunks, current, size} ->
        paragraph_size = String.length(paragraph)
        
        cond do
          # Current chunk is empty, add paragraph
          current == [] ->
            {chunks, [paragraph], paragraph_size}
          
          # Adding paragraph would exceed max size
          size + paragraph_size + 1 > max_chunk_size ->
            # Save current chunk and start new one
            chunk = create_semantic_chunk(current, length(chunks))
            {[chunk | chunks], [paragraph], paragraph_size}
          
          # Add paragraph to current chunk
          true ->
            {chunks, [paragraph | current], size + paragraph_size + 1}
        end
      end)
    
    # Don't forget the last chunk
    final_chunks = 
      if current != [] do
        [create_semantic_chunk(current, length(chunks)) | chunks]
      else
        chunks
      end
    
    Enum.reverse(final_chunks)
  end
  
  @doc """
  Chunks code content with awareness of code structure.
  
  Preserves function boundaries and code blocks.
  """
  @spec code_aware_chunks(String.t(), map(), keyword()) :: [chunk()]
  def code_aware_chunks(content, metadata \\ %{}, opts \\ []) do
    language = metadata[:language] || detect_language(content)
    max_chunk_size = Keyword.get(opts, :max_chunk_size, @default_chunk_size * 3)
    
    # Split by common code boundaries
    blocks = split_code_blocks(content, language)
    
    # Group blocks into chunks
    {chunks, current, _} = 
      Enum.reduce(blocks, {[], [], 0}, fn block, {chunks, current, size} ->
        block_size = String.length(block.content)
        
        cond do
          # Current chunk is empty
          current == [] ->
            {chunks, [block], block_size}
          
          # Adding block would exceed max size and we have content
          size + block_size > max_chunk_size && current != [] ->
            chunk = create_code_chunk(current, length(chunks), language)
            {[chunk | chunks], [block], block_size}
          
          # Add block to current chunk
          true ->
            {chunks, [block | current], size + block_size}
        end
      end)
    
    # Don't forget the last chunk
    final_chunks = 
      if current != [] do
        [create_code_chunk(current, length(chunks), language) | chunks]
      else
        chunks
      end
    
    Enum.reverse(final_chunks)
  end
  
  # Private functions
  
  defp determine_strategy(content, metadata, opts) do
    cond do
      Keyword.has_key?(opts, :strategy) ->
        Keyword.get(opts, :strategy)
      
      metadata[:language] != nil ->
        :code_aware
      
      String.contains?(content, ["\n\n", "\r\n\r\n"]) ->
        :semantic
      
      true ->
        :sliding
    end
  end
  
  defp apply_strategy(strategy, content, metadata, opts) do
    case strategy do
      :fixed -> fixed_size_chunks(content, opts)
      :sliding -> sliding_window_chunks(content, opts)
      :semantic -> semantic_chunks(content, metadata, opts)
      :code_aware -> code_aware_chunks(content, metadata, opts)
      _ -> {:error, :unknown_strategy}
    end
  end
  
  defp chunk_with_overlap(chars, chunk_size, overlap) when overlap >= chunk_size do
    # Invalid overlap, fall back to no overlap
    chunk_with_overlap(chars, chunk_size, 0)
  end
  
  defp chunk_with_overlap(chars, chunk_size, 0) do
    Enum.chunk_every(chars, chunk_size)
  end
  
  defp chunk_with_overlap(chars, chunk_size, overlap) do
    stride = chunk_size - overlap
    chunk_with_stride(chars, chunk_size, stride)
  end
  
  defp chunk_with_stride(chars, chunk_size, stride) do
    Stream.unfold({chars, 0}, fn
      {[], _} -> nil
      {remaining, _offset} ->
        chunk = Enum.take(remaining, chunk_size)
        if chunk == [] do
          nil
        else
          {chunk, {Enum.drop(remaining, stride), stride}}
        end
    end)
    |> Enum.to_list()
  end
  
  defp create_semantic_chunk(paragraphs, index) do
    content = paragraphs
    |> Enum.reverse()
    |> Enum.join("\n\n")
    
    %{
      content: content,
      metadata: %{
        strategy: :semantic,
        index: index,
        paragraph_count: length(paragraphs)
      }
    }
  end
  
  defp detect_language(content) do
    cond do
      String.contains?(content, ["defmodule", "def ", "defp "]) -> "elixir"
      String.contains?(content, ["function", "const ", "=>"]) -> "javascript"
      String.contains?(content, ["class ", "def ", "import "]) -> "python"
      true -> "unknown"
    end
  end
  
  defp split_code_blocks(content, language) do
    # Simple implementation - can be enhanced with AST parsing
    patterns = case language do
      "elixir" -> [~r/(?:^|\n)((?:def|defp|defmodule)\s+.+?(?=\n(?:def|defp|defmodule|end|\z)))/ms]
      _ -> [~r/\n\n/]
    end
    
    pattern = List.first(patterns, ~r/\n\n/)
    
    content
    |> String.split(pattern, trim: true)
    |> Enum.map(fn block_content ->
      %{
        content: String.trim(block_content),
        type: detect_block_type(block_content, language)
      }
    end)
    |> Enum.filter(fn block -> String.length(block.content) > 0 end)
  end
  
  defp detect_block_type(content, "elixir") do
    cond do
      String.starts_with?(content, "defmodule") -> :module
      String.starts_with?(content, "def ") -> :function
      String.starts_with?(content, "defp ") -> :private_function
      true -> :code
    end
  end
  
  defp detect_block_type(_, _), do: :code
  
  defp create_code_chunk(blocks, index, language) do
    content = blocks
    |> Enum.reverse()
    |> Enum.map(& &1.content)
    |> Enum.join("\n\n")
    
    block_types = blocks
    |> Enum.map(& &1.type)
    |> Enum.frequencies()
    
    %{
      content: content,
      metadata: %{
        strategy: :code_aware,
        index: index,
        language: language,
        block_count: length(blocks),
        block_types: block_types
      }
    }
  end
end
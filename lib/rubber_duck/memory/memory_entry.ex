defmodule RubberDuck.Memory.MemoryEntry do
  @moduledoc """
  Data structure representing a single memory entry in the long-term storage.
  
  This struct encapsulates all information about a memory including its content,
  metadata, versioning, relationships, and access patterns. It supports various
  memory types and provides functions for memory manipulation and lifecycle management.
  """

  defstruct [
    :id,
    :type,
    :content,
    :metadata,
    :version,
    :created_at,
    :updated_at,
    :accessed_at,
    :access_count,
    :ttl,
    :expires_at,
    :deleted_at,
    :encryption,
    :compressed,
    :checksum,
    :size_bytes,
    :embedding,
    :tags,
    :relationships,
    :author,
    :provenance
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    type: atom(),
    content: map() | String.t(),
    metadata: map(),
    version: integer(),
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    accessed_at: DateTime.t(),
    access_count: integer(),
    ttl: integer() | nil,
    expires_at: DateTime.t() | nil,
    deleted_at: DateTime.t() | nil,
    encryption: boolean(),
    compressed: boolean(),
    checksum: String.t() | nil,
    size_bytes: integer(),
    embedding: list(float()) | nil,
    tags: list(String.t()),
    relationships: list(relationship()),
    author: String.t(),
    provenance: map()
  }

  @type relationship :: %{
    type: atom(),
    target_id: String.t(),
    metadata: map(),
    created_at: DateTime.t()
  }

  @memory_types [:user_profile, :code_pattern, :interaction, :knowledge, :optimization, :configuration]

  @doc """
  Creates a new memory entry with the given attributes.
  """
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()
    
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      type: validate_type(attrs[:type]),
      content: attrs[:content] || %{},
      metadata: attrs[:metadata] || %{},
      version: 1,
      created_at: now,
      updated_at: now,
      accessed_at: now,
      access_count: 0,
      ttl: attrs[:ttl],
      expires_at: calculate_expiration(now, attrs[:ttl]),
      deleted_at: nil,
      encryption: attrs[:encryption] || false,
      compressed: attrs[:compressed] || false,
      checksum: nil,
      size_bytes: 0,
      embedding: attrs[:embedding],
      tags: attrs[:tags] || [],
      relationships: attrs[:relationships] || [],
      author: attrs[:author] || "system",
      provenance: build_provenance(attrs)
    }
    |> calculate_size()
    |> calculate_checksum()
  end

  @doc """
  Updates a memory entry with new values, incrementing the version.
  """
  def update(memory, updates) when is_map(updates) do
    updated_memory = %{memory |
      content: updates[:content] || memory.content,
      metadata: Map.merge(memory.metadata, updates[:metadata] || %{}),
      tags: updates[:tags] || memory.tags,
      updated_at: DateTime.utc_now(),
      version: memory.version + 1
    }
    
    updated_memory
    |> calculate_size()
    |> calculate_checksum()
  end

  @doc """
  Records an access to the memory, updating access timestamp and count.
  """
  def record_access(memory) do
    %{memory |
      accessed_at: DateTime.utc_now(),
      access_count: memory.access_count + 1
    }
  end

  @doc """
  Marks a memory as deleted (soft delete).
  """
  def mark_deleted(memory) do
    %{memory |
      deleted_at: DateTime.utc_now()
    }
  end

  @doc """
  Checks if a memory is deleted.
  """
  def deleted?(memory) do
    memory.deleted_at != nil
  end

  @doc """
  Checks if a memory has expired based on its TTL.
  """
  def expired?(memory) do
    case memory.expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end

  @doc """
  Adds a relationship to another memory.
  """
  def add_relationship(memory, type, target_id, metadata \\ %{}) do
    relationship = %{
      type: type,
      target_id: target_id,
      metadata: metadata,
      created_at: DateTime.utc_now()
    }
    
    %{memory |
      relationships: [relationship | memory.relationships]
    }
  end

  @doc """
  Removes a relationship by target_id.
  """
  def remove_relationship(memory, target_id) do
    %{memory |
      relationships: Enum.reject(memory.relationships, &(&1.target_id == target_id))
    }
  end

  @doc """
  Compresses the memory content if it's large enough.
  """
  def compress(memory) do
    if should_compress?(memory) and not memory.compressed do
      compressed_content = :zlib.compress(:erlang.term_to_binary(memory.content))
      
      %{memory |
        content: Base.encode64(compressed_content),
        compressed: true,
        metadata: Map.put(memory.metadata, :original_size, memory.size_bytes)
      }
      |> calculate_size()
    else
      memory
    end
  end

  @doc """
  Decompresses the memory content if it was compressed.
  """
  def decompress(memory) do
    if memory.compressed do
      compressed_data = Base.decode64!(memory.content)
      decompressed_content = :erlang.binary_to_term(:zlib.uncompress(compressed_data))
      
      %{memory |
        content: decompressed_content,
        compressed: false
      }
      |> calculate_size()
    else
      memory
    end
  end

  @doc """
  Validates that a memory entry has required fields and valid data.
  """
  def valid?(memory) do
    memory.id != nil and
    memory.type in @memory_types and
    memory.content != nil and
    memory.created_at != nil
  end

  @doc """
  Returns a summary of the memory for display or logging.
  """
  def summary(memory) do
    %{
      id: memory.id,
      type: memory.type,
      version: memory.version,
      created_at: memory.created_at,
      updated_at: memory.updated_at,
      access_count: memory.access_count,
      size_bytes: memory.size_bytes,
      tags: memory.tags,
      deleted: deleted?(memory),
      expired: expired?(memory)
    }
  end

  @doc """
  Converts the memory to a format suitable for indexing.
  """
  def to_index_doc(memory) do
    %{
      id: memory.id,
      type: to_string(memory.type),
      content: extract_text_content(memory),
      tags: memory.tags,
      metadata: flatten_metadata(memory.metadata),
      created_at: memory.created_at,
      updated_at: memory.updated_at,
      version: memory.version,
      author: memory.author
    }
  end

  # Private functions

  defp generate_id do
    "mem_" <> :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp validate_type(type) when type in @memory_types, do: type
  defp validate_type(type) when is_binary(type) do
    atom_type = String.to_atom(type)
    if atom_type in @memory_types do
      atom_type
    else
      raise ArgumentError, "Invalid memory type: #{type}"
    end
  end
  defp validate_type(_), do: raise(ArgumentError, "Memory type is required")

  defp calculate_expiration(_now, nil), do: nil
  defp calculate_expiration(now, ttl_seconds) when is_integer(ttl_seconds) do
    DateTime.add(now, ttl_seconds, :second)
  end

  defp build_provenance(attrs) do
    %{
      source: attrs[:source] || "system",
      agent: attrs[:agent] || "long_term_memory",
      context: attrs[:context] || %{},
      timestamp: DateTime.utc_now()
    }
  end

  defp calculate_size(memory) do
    size = case memory.content do
      content when is_binary(content) -> byte_size(content)
      content when is_map(content) -> content |> :erlang.term_to_binary() |> byte_size()
      _ -> 0
    end
    
    %{memory | size_bytes: size}
  end

  defp calculate_checksum(memory) do
    data = :erlang.term_to_binary({memory.content, memory.metadata, memory.tags})
    checksum = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
    
    %{memory | checksum: checksum}
  end

  defp should_compress?(memory) do
    # Compress if larger than 10KB and not already compressed
    memory.size_bytes > 10_240
  end

  defp extract_text_content(memory) do
    case memory.content do
      content when is_binary(content) -> content
      content when is_map(content) ->
        content
        |> Map.values()
        |> Enum.filter(&is_binary/1)
        |> Enum.join(" ")
      _ -> ""
    end
  end

  defp flatten_metadata(metadata, prefix \\ "") do
    Enum.flat_map(metadata, fn {key, value} ->
      full_key = if prefix == "", do: to_string(key), else: "#{prefix}.#{key}"
      
      case value do
        v when is_map(v) -> flatten_metadata(v, full_key)
        v -> [{full_key, v}]
      end
    end)
    |> Map.new()
  end
end
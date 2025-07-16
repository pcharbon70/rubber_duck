defmodule RubberDuck.MCP.Server.Resources.Documentation do
  @moduledoc """
  Provides access to project documentation as MCP resources.
  
  This resource exposes guides, API documentation, and other documentation
  files to AI assistants for context and reference.
  """
  
  use Hermes.Server.Component,
    type: :resource,
    uri: "docs://",
    mime_type: "text/markdown"
  
  alias Hermes.Server.Frame
  
  @doc_directories [
    "guides",
    "docs",
    "documentation",
    ".instructions",
    ".rules"
  ]
  
  schema do
    field :category, {:enum, ["guides", "api", "instructions", "rules", "all"]},
      description: "Documentation category to access",
      default: "all"
      
    field :path, :string,
      description: "Specific document path within the category"
  end
  
  @impl true
  def uri do
    "docs://"
  end
  
  @impl true
  def read(%{path: path}, frame) when is_binary(path) do
    project_root = File.cwd!()
    
    # Try to find the document in various locations
    doc_path = find_document(path, project_root)
    
    case doc_path do
      {:ok, full_path} ->
        read_document(full_path, frame)
        
      {:error, :not_found} ->
        {:error, %{
          "code" => "document_not_found",
          "message" => "Document not found: #{path}"
        }}
    end
  end
  
  def read(%{category: category}, frame) do
    # List documents in the category
    list_category_documents(category, frame)
  end
  
  @impl true
  def list(frame) do
    project_root = File.cwd!()
    
    documents = find_all_documents(project_root)
    |> Enum.map(fn {path, category} ->
      stat = File.stat!(path)
      relative = Path.relative_to(path, project_root)
      
      %{
        "uri" => "docs://#{relative}",
        "name" => Path.basename(path),
        "path" => relative,
        "category" => category,
        "mime_type" => get_doc_mime_type(path),
        "size" => stat.size,
        "modified" => DateTime.from_unix!(stat.mtime) |> DateTime.to_iso8601()
      }
    end)
    |> Enum.sort_by(& &1["path"])
    
    {:ok, documents, frame}
  end
  
  # Private functions
  
  defp find_document(path, root) do
    # Check if it's a direct path
    full_path = Path.join(root, path)
    if File.exists?(full_path) do
      {:ok, full_path}
    else
      # Try to find in documentation directories
      Enum.find_value(@doc_directories, {:error, :not_found}, fn dir ->
        check_path = Path.join([root, dir, path])
        if File.exists?(check_path) do
          {:ok, check_path}
        else
          nil
        end
      end)
    end
  end
  
  defp read_document(path, frame) do
    case File.read(path) do
      {:ok, content} ->
        # Process the content based on type
        processed_content = process_document_content(path, content)
        
        {:ok, %{
          "content" => processed_content,
          "mime_type" => get_doc_mime_type(path),
          "metadata" => extract_metadata(content)
        }, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "read_error",
          "message" => "Failed to read document: #{inspect(reason)}"
        }}
    end
  end
  
  defp list_category_documents(category, frame) do
    project_root = File.cwd!()
    
    documents = case category do
      "guides" -> find_guides(project_root)
      "api" -> find_api_docs(project_root)
      "instructions" -> find_instructions(project_root)
      "rules" -> find_rules(project_root)
      "all" -> find_all_documents(project_root)
      _ -> []
    end
    
    formatted = Enum.map(documents, fn {path, cat} ->
      relative = Path.relative_to(path, project_root)
      %{
        "uri" => "docs://#{relative}",
        "name" => Path.basename(path),
        "path" => relative,
        "category" => cat
      }
    end)
    
    {:ok, %{
      "documents" => formatted,
      "category" => category,
      "count" => length(formatted)
    }, frame}
  end
  
  defp find_guides(root) do
    Path.wildcard(Path.join([root, "guides", "**", "*.md"]))
    |> Enum.map(&{&1, "guides"})
  end
  
  defp find_api_docs(root) do
    # Look for generated API docs
    doc_path = Path.join([root, "doc"])
    if File.dir?(doc_path) do
      Path.wildcard(Path.join([doc_path, "**", "*.html"]))
      |> Enum.map(&{&1, "api"})
    else
      []
    end
  end
  
  defp find_instructions(root) do
    patterns = [
      Path.join([root, ".instructions", "**", "*.md"]),
      Path.join([root, "*.mdc"]),
      Path.join([root, "AGENTS.md"]),
      Path.join([root, "CLAUDE.md"]),
      Path.join([root, "instructions.md"])
    ]
    
    Enum.flat_map(patterns, &Path.wildcard/1)
    |> Enum.map(&{&1, "instructions"})
  end
  
  defp find_rules(root) do
    Path.wildcard(Path.join([root, ".rules", "**", "*.md"]))
    |> Enum.map(&{&1, "rules"})
  end
  
  defp find_all_documents(root) do
    find_guides(root) ++ 
    find_api_docs(root) ++ 
    find_instructions(root) ++ 
    find_rules(root)
  end
  
  defp process_document_content(path, content) do
    cond do
      String.ends_with?(path, ".md") ->
        # Process markdown - could expand frontmatter, etc.
        content
        
      String.ends_with?(path, ".html") ->
        # For HTML docs, we might want to extract just the content
        content
        
      true ->
        content
    end
  end
  
  defp extract_metadata(content) do
    # Extract frontmatter or other metadata
    case Regex.run(~r/^---\n(.*?)\n---/s, content) do
      [_, frontmatter] ->
        # Parse YAML frontmatter (simplified)
        %{"has_frontmatter" => true}
        
      _ ->
        %{"has_frontmatter" => false}
    end
  end
  
  defp get_doc_mime_type(path) do
    case Path.extname(path) do
      ".md" -> "text/markdown"
      ".html" -> "text/html"
      ".txt" -> "text/plain"
      _ -> "text/plain"
    end
  end
end
defmodule RubberDuck.MCP.Server.Resources.ProjectFiles do
  @moduledoc """
  Provides access to project files as MCP resources.
  
  This resource allows AI assistants to browse and read files in the project
  directory, with appropriate filtering and access controls.
  """
  
  use Hermes.Server.Component, 
    type: :resource,
    uri: "file://",
    mime_type: "text/plain"
  
  alias Hermes.Server.Frame
  
  @ignored_patterns [
    ~r/^\.git\//,
    ~r/^_build\//,
    ~r/^deps\//,
    ~r/^node_modules\//,
    ~r/^\.elixir_ls\//,
    ~r/\.beam$/,
    ~r/\.ez$/
  ]
  
  @binary_extensions ~w(.jpg .jpeg .png .gif .pdf .zip .tar .gz .bz2 .xz .exe .dll .so .dylib)
  
  schema do
    field :path, :string,
      description: "File path relative to project root"
  end
  
  @impl true
  def uri do
    # Dynamic URI based on requested path
    "file://"
  end
  
  @impl true
  def mime_type do
    # Will be overridden dynamically based on file type
    "text/plain"
  end
  
  @impl true
  def read(%{path: path}, frame) when is_binary(path) do
    project_root = File.cwd!()
    full_path = Path.expand(path, project_root)
    
    # Security check
    unless String.starts_with?(full_path, project_root) do
      return {:error, %{
        "code" => "invalid_path",
        "message" => "Path traversal detected"
      }}
    end
    
    # Check if path is ignored
    relative_path = Path.relative_to(full_path, project_root)
    if path_ignored?(relative_path) do
      return {:error, %{
        "code" => "access_denied",
        "message" => "Access to this file is restricted"
      }}
    end
    
    read_file_content(full_path, frame)
  end
  
  def read(_params, _frame) do
    {:error, %{
      "code" => "missing_path",
      "message" => "Path parameter is required"
    }}
  end
  
  @impl true
  def list(frame) do
    project_root = File.cwd!()
    
    files = list_project_files(project_root)
    |> Enum.map(fn path ->
      stat = File.stat!(path)
      relative = Path.relative_to(path, project_root)
      
      %{
        "uri" => "file://#{relative}",
        "name" => Path.basename(path),
        "path" => relative,
        "mime_type" => get_mime_type(path),
        "size" => stat.size,
        "modified" => DateTime.from_unix!(stat.mtime) |> DateTime.to_iso8601()
      }
    end)
    |> Enum.sort_by(& &1["path"])
    
    {:ok, files, frame}
  end
  
  # Private functions
  
  defp read_file_content(path, frame) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} ->
        if size > 1_048_576 do  # 1MB limit
          {:error, %{
            "code" => "file_too_large",
            "message" => "File exceeds 1MB size limit"
          }}
        else
          read_file_by_type(path, frame)
        end
        
      {:ok, %{type: type}} ->
        {:error, %{
          "code" => "invalid_file_type",
          "message" => "Cannot read #{type} files"
        }}
        
      {:error, :enoent} ->
        {:error, %{
          "code" => "file_not_found",
          "message" => "File not found"
        }}
        
      {:error, reason} ->
        {:error, %{
          "code" => "file_error",
          "message" => "Failed to access file: #{inspect(reason)}"
        }}
    end
  end
  
  defp read_file_by_type(path, frame) do
    if binary_file?(path) do
      # For binary files, return base64 encoded content
      case File.read(path) do
        {:ok, content} ->
          encoded = Base.encode64(content)
          {:ok, %{
            "content" => encoded,
            "encoding" => "base64",
            "mime_type" => get_mime_type(path)
          }, frame}
          
        {:error, reason} ->
          {:error, %{
            "code" => "read_error",
            "message" => "Failed to read file: #{inspect(reason)}"
          }}
      end
    else
      # For text files, return as-is
      case File.read(path) do
        {:ok, content} ->
          {:ok, %{
            "content" => content,
            "encoding" => "utf8",
            "mime_type" => get_mime_type(path)
          }, frame}
          
        {:error, reason} ->
          {:error, %{
            "code" => "read_error",
            "message" => "Failed to read file: #{inspect(reason)}"
          }}
      end
    end
  end
  
  defp list_project_files(root) do
    Path.wildcard(Path.join(root, "**/*"))
    |> Enum.filter(&File.regular?/1)
    |> Enum.reject(fn path ->
      relative = Path.relative_to(path, root)
      path_ignored?(relative)
    end)
    |> Enum.take(1000)  # Limit to 1000 files
  end
  
  defp path_ignored?(path) do
    Enum.any?(@ignored_patterns, &Regex.match?(&1, path))
  end
  
  defp binary_file?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in @binary_extensions
  end
  
  defp get_mime_type(path) do
    ext = Path.extname(path) |> String.downcase()
    
    case ext do
      ".ex" -> "text/x-elixir"
      ".exs" -> "text/x-elixir"
      ".eex" -> "text/html"
      ".heex" -> "text/html"
      ".md" -> "text/markdown"
      ".json" -> "application/json"
      ".yaml" -> "text/yaml"
      ".yml" -> "text/yaml"
      ".toml" -> "text/toml"
      ".xml" -> "text/xml"
      ".html" -> "text/html"
      ".css" -> "text/css"
      ".js" -> "text/javascript"
      ".ts" -> "text/typescript"
      ".py" -> "text/x-python"
      ".rb" -> "text/x-ruby"
      ".sh" -> "text/x-shellscript"
      ".txt" -> "text/plain"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".pdf" -> "application/pdf"
      _ -> "application/octet-stream"
    end
  end
  
  defp return(value), do: value
end
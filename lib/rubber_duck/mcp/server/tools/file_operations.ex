defmodule RubberDuck.MCP.Server.Tools.FileOperations do
  @moduledoc """
  Provides file system operations through MCP.
  
  This tool allows AI assistants to safely read, write, and manipulate files
  within the project directory, with appropriate access controls and validation.
  """
  
  @category :file_system
  @tags [:file_operations, :io, :safe_access, :validation]
  @capabilities [:read, :write, :list, :delete, :move, :copy]
  @examples [
    %{
      description: "Read a text file",
      params: %{operation: "read", path: "config/config.exs", encoding: "utf8"}
    },
    %{
      description: "Write content to file",
      params: %{operation: "write", path: "tmp/output.txt", content: "Hello, world!"}
    },
    %{
      description: "List directory contents recursively",
      params: %{operation: "list", path: "lib", recursive: true}
    }
  ]
  
  use Hermes.Server.Component, type: :tool
  
  alias Hermes.Server.Frame
  
  @max_file_size 1_048_576  # 1MB
  
  schema do
    field :operation, {:required, {:enum, ["read", "write", "list", "delete", "move", "copy"]}},
      description: "The file operation to perform"
      
    field :path, {:required, :string},
      description: "Path relative to project root"
      
    field :content, :string,
      description: "Content for write operations"
      
    field :destination, :string,
      description: "Destination path for move/copy operations"
      
    field :encoding, {:enum, ["utf8", "binary"]},
      description: "File encoding",
      default: "utf8"
      
    field :recursive, :boolean,
      description: "For list operations, whether to recurse into subdirectories",
      default: false
  end
  
  @impl true
  def execute(%{operation: op} = params, frame) do
    # Validate and sanitize paths
    case validate_path(params.path) do
      {:ok, safe_path} ->
        perform_operation(op, safe_path, params, frame)
        
      {:error, reason} ->
        {:error, %{
          "code" => "invalid_path",
          "message" => reason
        }}
    end
  end
  
  defp perform_operation("read", path, %{encoding: encoding}, frame) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_file_size ->
        {:error, %{
          "code" => "file_too_large",
          "message" => "File exceeds maximum size of #{@max_file_size} bytes"
        }}
        
      {:ok, _} ->
        read_file(path, encoding, frame)
        
      {:error, :enoent} ->
        {:error, %{
          "code" => "file_not_found",
          "message" => "File not found: #{path}"
        }}
        
      {:error, reason} ->
        {:error, %{
          "code" => "file_error",
          "message" => "Failed to access file: #{reason}"
        }}
    end
  end
  
  defp perform_operation("write", path, %{content: content, encoding: encoding}, frame) do
    # Ensure parent directory exists
    path
    |> Path.dirname()
    |> File.mkdir_p()
    
    write_file(path, content, encoding, frame)
  end
  
  defp perform_operation("list", path, %{recursive: recursive}, frame) do
    list_directory(path, recursive, frame)
  end
  
  defp perform_operation("delete", path, _params, frame) do
    delete_file(path, frame)
  end
  
  defp perform_operation("move", path, %{destination: dest}, frame) do
    case validate_path(dest) do
      {:ok, safe_dest} ->
        move_file(path, safe_dest, frame)
        
      {:error, reason} ->
        {:error, %{
          "code" => "invalid_destination",
          "message" => reason
        }}
    end
  end
  
  defp perform_operation("copy", path, %{destination: dest}, frame) do
    case validate_path(dest) do
      {:ok, safe_dest} ->
        copy_file(path, safe_dest, frame)
        
      {:error, reason} ->
        {:error, %{
          "code" => "invalid_destination",
          "message" => reason
        }}
    end
  end
  
  # File operation implementations
  
  defp read_file(path, "binary", frame) do
    case File.read(path) do
      {:ok, content} ->
        encoded = Base.encode64(content)
        # Read binary file successfully
        {:ok, %{"content" => encoded, "encoding" => "base64"}, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "read_error",
          "message" => "Failed to read file: #{reason}"
        }}
    end
  end
  
  defp read_file(path, "utf8", frame) do
    case File.read(path) do
      {:ok, content} ->
        # Read file successfully
        {:ok, %{"content" => content, "encoding" => "utf8"}, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "read_error",
          "message" => "Failed to read file: #{reason}"
        }}
    end
  end
  
  defp write_file(path, content, "binary", frame) do
    decoded = Base.decode64!(content)
    
    case File.write(path, decoded) do
      :ok ->
        # Wrote binary file successfully
        {:ok, %{"path" => path, "bytes_written" => byte_size(decoded)}, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "write_error",
          "message" => "Failed to write file: #{reason}"
        }}
    end
  end
  
  defp write_file(path, content, "utf8", frame) do
    case File.write(path, content) do
      :ok ->
        # Wrote file successfully
        {:ok, %{"path" => path, "bytes_written" => byte_size(content)}, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "write_error",
          "message" => "Failed to write file: #{reason}"
        }}
    end
  end
  
  defp list_directory(path, recursive, frame) do
    if File.dir?(path) do
      files = if recursive do
        list_recursive(path)
      else
        case File.ls(path) do
          {:ok, entries} -> entries
          {:error, _} -> []
        end
      end
      
      entries = Enum.map(files, fn file ->
        full_path = if recursive, do: file, else: Path.join(path, file)
        stat = File.stat!(full_path)
        
        %{
          "name" => Path.basename(file),
          "path" => full_path,
          "type" => if(stat.type == :directory, do: "directory", else: "file"),
          "size" => stat.size,
          "modified" => DateTime.to_iso8601(DateTime.from_unix!(stat.mtime))
        }
      end)
      
      # Listed directory successfully
      {:ok, %{"entries" => entries}, frame}
    else
      {:error, %{
        "code" => "not_a_directory",
        "message" => "Path is not a directory: #{path}"
      }}
    end
  end
  
  defp delete_file(path, frame) do
    case File.rm(path) do
      :ok ->
        # Deleted file successfully
        {:ok, %{"deleted" => path}, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "delete_error",
          "message" => "Failed to delete file: #{reason}"
        }}
    end
  end
  
  defp move_file(source, dest, frame) do
    case File.rename(source, dest) do
      :ok ->
        # Moved file successfully
        {:ok, %{"source" => source, "destination" => dest}, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "move_error",
          "message" => "Failed to move file: #{reason}"
        }}
    end
  end
  
  defp copy_file(source, dest, frame) do
    case File.copy(source, dest) do
      {:ok, bytes} ->
        # Copied file successfully
        {:ok, %{"source" => source, "destination" => dest, "bytes_copied" => bytes}, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "copy_error",
          "message" => "Failed to copy file: #{reason}"
        }}
    end
  end
  
  # Helper functions
  
  defp validate_path(path) do
    project_root = File.cwd!()
    full_path = Path.expand(path, project_root)
    
    cond do
      # Check for path traversal
      not String.starts_with?(full_path, project_root) ->
        {:error, "Path traversal detected"}
        
      # Check for sensitive directories
      String.contains?(path, [".git/", "node_modules/", "_build/", "deps/"]) ->
        {:error, "Access to sensitive directories not allowed"}
        
      true ->
        {:ok, full_path}
    end
  end
  
  defp list_recursive(path) do
    Path.wildcard(Path.join(path, "**/*"))
    |> Enum.map(&Path.relative_to(&1, path))
  end
end
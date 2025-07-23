defmodule RubberDuck.Projects.SecurityValidator do
  @moduledoc """
  Security validation module for file operations.
  
  Provides comprehensive security checks including:
  - File content validation
  - Malware scanning integration
  - File type verification
  - Content type detection
  - Dangerous pattern detection
  """
  
  require Logger
  
  # Dangerous file extensions that could pose security risks
  @dangerous_extensions ~w[
    .exe .com .bat .cmd .scr .vbs .vbe .js .jse .wsf .wsh .msi .jar
    .ps1 .psm1 .ps1xml .psc1 .psd1 .cdxml .ps2 .ps2xml
    .application .gadget .msp .mst .shb .shs .hta .cpl .msc .ins
    .inx .isu .job .lnk .inf .reg .dll .sys
  ]
  
  # Archive extensions that need special handling
  @archive_extensions ~w[
    .zip .rar .7z .tar .gz .bz2 .xz .tar.gz .tar.bz2 .tar.xz
    .iso .dmg .pkg .deb .rpm
  ]
  
  # Known safe text file extensions
  @text_extensions ~w[
    .txt .md .markdown .rst .log .csv .json .xml .yaml .yml
    .html .htm .css .scss .sass .less
    .js .jsx .ts .tsx .coffee
    .rb .py .ex .exs .erl .hrl .go .rs .c .h .cpp .hpp .java
    .sh .bash .zsh .fish .ps1 .bat .cmd
    .sql .graphql .proto
    .ini .conf .config .env .gitignore .dockerignore
    .editorconfig .prettierrc .eslintrc .babelrc
  ]
  
  # Maximum file size for content scanning (10MB)
  @max_scan_size 10 * 1024 * 1024
  
  @doc """
  Validates a file for security concerns.
  
  Returns :ok if the file passes all security checks, or
  {:error, reason} if any security issues are found.
  """
  def validate_file(path, opts \\ []) do
    with :ok <- validate_extension(path, opts),
         :ok <- validate_file_type(path),
         :ok <- validate_content(path, opts),
         :ok <- scan_for_malware(path, opts) do
      :ok
    end
  end
  
  @doc """
  Validates just the filename without reading the file.
  Useful for pre-validation before file creation.
  """
  def validate_filename(filename, opts \\ []) do
    with :ok <- validate_extension(filename, opts),
         :ok <- validate_filename_patterns(filename) do
      :ok
    end
  end
  
  @doc """
  Validates file content without full security scan.
  Useful for validating content before writing.
  """
  def validate_content_bytes(content, filename, opts \\ []) do
    with :ok <- validate_content_size(content, opts),
         :ok <- validate_content_patterns(content, filename),
         :ok <- validate_archive_content(content, filename) do
      :ok
    end
  end
  
  @doc """
  Gets the detected content type for a file.
  """
  def get_content_type(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        header = IO.binread(file, 512)
        File.close(file)
        {:ok, detect_content_type(header, path)}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Private functions
  
  defp validate_extension(path, opts) do
    if Keyword.get(opts, :check_extension, true) do
      ext = get_extension(path)
      
      cond do
        ext in @dangerous_extensions and not Keyword.get(opts, :allow_dangerous, false) ->
          {:error, {:dangerous_extension, ext}}
          
        Keyword.has_key?(opts, :allowed_extensions) ->
          allowed = Keyword.get(opts, :allowed_extensions)
          # Handle :all as a special case
          cond do
            allowed == :all -> :ok
            ext in allowed -> :ok
            true -> {:error, {:extension_not_allowed, ext}}
          end
          
        true ->
          :ok
      end
    else
      :ok
    end
  end
  
  defp validate_file_type(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} ->
        :ok
        
      {:ok, %File.Stat{type: type}} ->
        {:error, {:invalid_file_type, type}}
        
      {:error, :enoent} ->
        # File doesn't exist yet, that's ok for pre-validation
        :ok
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp validate_content(path, opts) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} when size <= @max_scan_size ->
        case File.read(path) do
          {:ok, content} ->
            validate_content_patterns(content, path)
            
          {:error, reason} ->
            {:error, reason}
        end
        
      {:ok, %File.Stat{size: size}} ->
        if Keyword.get(opts, :skip_large_files, true) do
          Logger.debug("Skipping content validation for large file: #{path} (#{size} bytes)")
          :ok
        else
          {:error, {:file_too_large_to_scan, size}}
        end
        
      {:error, :enoent} ->
        :ok
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp validate_content_size(content, opts) do
    max_size = Keyword.get(opts, :max_content_size, @max_scan_size)
    size = byte_size(content)
    
    if size <= max_size do
      :ok
    else
      {:error, {:content_too_large, size, max_size}}
    end
  end
  
  defp validate_content_patterns(content, path) do
    ext = get_extension(path)
    
    cond do
      # Skip binary files
      is_binary_content?(content) and ext not in @text_extensions ->
        :ok
        
      # Check for suspicious patterns in text files
      true ->
        check_suspicious_patterns(content)
    end
  end
  
  defp validate_archive_content(content, filename) do
    ext = get_extension(filename)
    
    if ext in @archive_extensions do
      # For now, just check if it's a valid archive header
      case detect_archive_type(content) do
        {:ok, _type} -> :ok
        :unknown -> {:error, {:invalid_archive_format, ext}}
      end
    else
      :ok
    end
  end
  
  defp validate_filename_patterns(filename) do
    # Check for directory traversal attempts in filename
    if String.contains?(filename, ["../", "..\\", "%2e%2e", "%252e%252e"]) do
      {:error, :path_traversal_in_filename}
    else
      :ok
    end
  end
  
  defp scan_for_malware(path, opts) do
    if Keyword.get(opts, :enable_malware_scan, false) do
      # Call external malware scanner if configured
      scanner = Keyword.get(opts, :malware_scanner)
      
      if scanner do
        case scanner.scan(path) do
          {:ok, :clean} -> :ok
          {:ok, {:infected, details}} -> {:error, {:malware_detected, details}}
          {:error, reason} -> {:error, {:malware_scan_failed, reason}}
        end
      else
        # No scanner configured, log warning
        Logger.warning("Malware scanning requested but no scanner configured")
        :ok
      end
    else
      :ok
    end
  end
  
  defp get_extension(path) do
    path
    |> Path.extname()
    |> String.downcase()
  end
  
  defp is_binary_content?(content) do
    # Check for null bytes or high percentage of non-printable characters
    byte_size = byte_size(content)
    sample_size = min(byte_size, 1024)
    sample = binary_part(content, 0, sample_size)
    
    null_count = sample
    |> :binary.bin_to_list()
    |> Enum.count(&(&1 == 0))
    
    non_printable_count = sample
    |> :binary.bin_to_list()
    |> Enum.count(&(&1 < 32 and &1 not in [9, 10, 13]))  # Allow tab, newline, carriage return
    
    null_count > 0 or (non_printable_count / sample_size) > 0.3
  end
  
  defp check_suspicious_patterns(content) do
    suspicious_patterns = [
      # Script injection patterns
      ~r/<script[^>]*>/i,
      ~r/javascript:/i,
      ~r/vbscript:/i,
      ~r/onload\s*=/i,
      ~r/onerror\s*=/i,
      ~r/onclick\s*=/i,
      
      # SQL injection patterns
      ~r/;\s*(DROP|DELETE|TRUNCATE|ALTER)\s+/i,
      ~r/UNION\s+SELECT/i,
      ~r/OR\s+1\s*=\s*1/i,
      
      # Command injection patterns
      ~r/\$\(.*\)/,
      ~r/`.*`/,
      ~r/\|\s*sh\b/,
      ~r/;\s*rm\s+-rf/,
      
      # PHP patterns
      ~r/<\?php/i,
      ~r/eval\s*\(/,
      ~r/system\s*\(/,
      ~r/exec\s*\(/
    ]
    
    Enum.find(suspicious_patterns, fn pattern ->
      Regex.match?(pattern, content)
    end)
    |> case do
      nil -> :ok
      pattern -> {:error, {:suspicious_content_pattern, inspect(pattern)}}
    end
  end
  
  defp detect_content_type(header, path) do
    ext = get_extension(path)
    
    cond do
      # Check magic bytes for common file types
      starts_with?(header, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>) -> "image/png"
      starts_with?(header, <<0xFF, 0xD8, 0xFF>>) -> "image/jpeg"
      starts_with?(header, "GIF87a") or starts_with?(header, "GIF89a") -> "image/gif"
      starts_with?(header, "%PDF-") -> "application/pdf"
      starts_with?(header, "PK") -> detect_zip_type(ext)
      starts_with?(header, <<0x1F, 0x8B>>) -> "application/gzip"
      starts_with?(header, "BZh") -> "application/x-bzip2"
      starts_with?(header, <<0xFD, "7zXZ", 0x00>>) -> "application/x-xz"
      
      # Text-based formats
      starts_with?(header, "<!DOCTYPE html") or starts_with?(header, "<html") -> "text/html"
      starts_with?(header, "<?xml") -> "text/xml"
      String.printable?(header) -> detect_text_type(ext)
      
      true -> "application/octet-stream"
    end
  end
  
  defp detect_zip_type(".docx"), do: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  defp detect_zip_type(".xlsx"), do: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  defp detect_zip_type(".pptx"), do: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
  defp detect_zip_type(".jar"), do: "application/java-archive"
  defp detect_zip_type(".apk"), do: "application/vnd.android.package-archive"
  defp detect_zip_type(_), do: "application/zip"
  
  defp detect_text_type(".json"), do: "application/json"
  defp detect_text_type(".js"), do: "application/javascript"
  defp detect_text_type(".css"), do: "text/css"
  defp detect_text_type(".html"), do: "text/html"
  defp detect_text_type(".xml"), do: "text/xml"
  defp detect_text_type(".csv"), do: "text/csv"
  defp detect_text_type(".md"), do: "text/markdown"
  defp detect_text_type(_), do: "text/plain"
  
  defp detect_archive_type(content) do
    cond do
      starts_with?(content, "PK") -> {:ok, :zip}
      starts_with?(content, "Rar!") -> {:ok, :rar}
      starts_with?(content, "7z") -> {:ok, :seven_zip}
      starts_with?(content, <<0x1F, 0x8B>>) -> {:ok, :gzip}
      starts_with?(content, "BZh") -> {:ok, :bzip2}
      starts_with?(content, <<0xFD, "7zXZ", 0x00>>) -> {:ok, :xz}
      true -> :unknown
    end
  end
  
  defp starts_with?(binary, pattern) when is_binary(pattern) do
    binary_part(binary, 0, min(byte_size(binary), byte_size(pattern))) == pattern
  end
end
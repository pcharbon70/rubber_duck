defimpl RubberDuck.Processor, for: BitString do
  @moduledoc """
  Processor implementation for String/BitString data type.
  
  Handles processing of text data, including:
  - Text normalization
  - Format conversion
  - Content extraction
  - Language detection
  """
  
  @doc """
  Process a string with various transformation options.
  
  ## Options
  
  - `:normalize` - Normalize whitespace and line endings (default: true)
  - `:trim` - Trim leading/trailing whitespace (default: true)
  - `:downcase` - Convert to lowercase
  - `:upcase` - Convert to uppercase
  - `:split` - Split into lines or by delimiter
  - `:max_length` - Truncate to maximum length
  - `:format` - Convert to specific format (:plain, :markdown, :code)
  """
  def process(string, opts) when is_binary(string) do
    result = string
    |> maybe_normalize(opts)
    |> maybe_trim(opts)
    |> maybe_change_case(opts)
    |> maybe_split(opts)
    |> maybe_truncate(opts)
    |> maybe_format(opts)
    
    {:ok, result}
  rescue
    e -> {:error, e}
  end
  
  def process(_not_string, _opts) do
    {:error, :not_a_string}
  end
  
  @doc """
  Extract metadata from the string.
  """
  def metadata(string) when is_binary(string) do
    lines = String.split(string, ~r/\r?\n/)
    words = String.split(string, ~r/\s+/) |> Enum.reject(&(&1 == ""))
    
    %{
      type: :string,
      encoding: :utf8,
      byte_size: byte_size(string),
      character_count: String.length(string),
      line_count: length(lines),
      word_count: length(words),
      has_unicode: String.match?(string, ~r/[^\x00-\x7F]/),
      language_hint: detect_language_hint(string),
      timestamp: DateTime.utc_now()
    }
  end
  
  @doc """
  Validate the string format.
  """
  def validate(string) when is_binary(string) do
    if String.valid?(string) do
      :ok
    else
      {:error, :invalid_utf8}
    end
  end
  
  def validate(_not_string) do
    {:error, :not_a_string}
  end
  
  @doc """
  Normalize the string to a consistent format.
  """
  def normalize(string) when is_binary(string) do
    string
    |> String.trim()
    |> String.replace(~r/\r\n/, "\n")
    |> String.replace(~r/\r/, "\n")
    |> String.replace(~r/[[:space:]]+/, " ")
  end
  
  # Private functions
  
  defp maybe_normalize(string, opts) do
    if Keyword.get(opts, :normalize, true) do
      string
      |> String.replace(~r/\r\n/, "\n")
      |> String.replace(~r/\r/, "\n")
      |> String.replace(~r/[[:space:]]+/, " ")
    else
      string
    end
  end
  
  defp maybe_trim(string, opts) do
    if Keyword.get(opts, :trim, true) do
      String.trim(string)
    else
      string
    end
  end
  
  defp maybe_change_case(string, opts) do
    cond do
      Keyword.get(opts, :downcase) -> String.downcase(string)
      Keyword.get(opts, :upcase) -> String.upcase(string)
      true -> string
    end
  end
  
  defp maybe_split(string, opts) do
    case Keyword.get(opts, :split) do
      nil -> string
      :lines -> String.split(string, ~r/\r?\n/)
      delimiter when is_binary(delimiter) -> String.split(string, delimiter)
      regex when is_struct(regex, Regex) -> String.split(string, regex)
      _ -> string
    end
  end
  
  defp maybe_truncate(string, opts) when is_binary(string) do
    case Keyword.get(opts, :max_length) do
      nil -> string
      max when is_integer(max) and max > 0 ->
        if String.length(string) > max do
          String.slice(string, 0, max - 3) <> "..."
        else
          string
        end
    end
  end
  
  defp maybe_truncate(list, opts) when is_list(list) do
    # If string was split, apply truncation to the list
    case Keyword.get(opts, :max_length) do
      nil -> list
      max when is_integer(max) and max > 0 -> Enum.take(list, max)
    end
  end
  
  defp maybe_format(string, opts) when is_binary(string) do
    case Keyword.get(opts, :format) do
      nil -> string
      :plain -> strip_formatting(string)
      :markdown -> ensure_markdown_format(string)
      :code -> format_as_code(string)
      _ -> string
    end
  end
  
  defp maybe_format(list, opts) when is_list(list) do
    # If string was split, apply formatting to each element
    case Keyword.get(opts, :format) do
      nil -> list
      format -> Enum.map(list, &maybe_format(&1, format: format))
    end
  end
  
  defp strip_formatting(string) do
    string
    |> String.replace(~r/\*{1,2}([^*]+)\*{1,2}/, "\\1")  # Remove markdown bold/italic
    |> String.replace(~r/`([^`]+)`/, "\\1")              # Remove inline code
    |> String.replace(~r/^#+\s+/, "")                    # Remove headers
  end
  
  defp ensure_markdown_format(string) do
    # Basic markdown formatting - could be enhanced
    string
  end
  
  defp format_as_code(string) do
    "```\n#{string}\n```"
  end
  
  defp detect_language_hint(string) do
    cond do
      # Simple heuristics - could be enhanced with actual language detection
      String.match?(string, ~r/\bdef\s+\w+|defmodule\s+|defp\s+/) -> :elixir
      String.match?(string, ~r/\bfunction\s+\w+|const\s+|let\s+|var\s+/) -> :javascript
      String.match?(string, ~r/\bdef\s+\w+:|class\s+\w+:|import\s+/) -> :python
      String.match?(string, ~r/\bfn\s+\w+|impl\s+|trait\s+|struct\s+/) -> :rust
      true -> :unknown
    end
  end
end
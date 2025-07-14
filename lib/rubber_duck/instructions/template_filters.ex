defmodule RubberDuck.Instructions.TemplateFilters do
  @moduledoc """
  Custom Liquid filters for Solid template processing.
  
  Provides a set of safe, useful filters for instruction templates.
  """


  @doc """
  Converts a string to uppercase.
  
  ## Examples
  
      {{ "hello" | upcase }} => "HELLO"
  """
  def upcase(input, _args, _options) do
    to_string(input) |> String.upcase()
  end

  @doc """
  Converts a string to lowercase.
  
  ## Examples
  
      {{ "HELLO" | downcase }} => "hello"
  """
  def downcase(input, _args, _options) do
    to_string(input) |> String.downcase()
  end

  @doc """
  Capitalizes the first letter of a string.
  
  ## Examples
  
      {{ "hello world" | capitalize }} => "Hello world"
  """
  def capitalize(input, _args, _options) do
    to_string(input) |> String.capitalize()
  end

  @doc """
  Truncates a string to a specified length.
  
  ## Examples
  
      {{ "hello world" | truncate: 5 }} => "hello..."
      {{ "hello world" | truncate: 5, "---" }} => "hello---"
  """
  def truncate(input, args, _options) do
    string = to_string(input)
    length = get_arg(args, 0, 50) |> to_integer()
    suffix = get_arg(args, 1, "...")
    
    if String.length(string) > length do
      String.slice(string, 0, length) <> suffix
    else
      string
    end
  end

  @doc """
  Replaces occurrences in a string.
  
  ## Examples
  
      {{ "hello world" | replace: "world", "elixir" }} => "hello elixir"
  """
  def replace(input, args, _options) do
    string = to_string(input)
    pattern = get_arg(args, 0, "") |> to_string()
    replacement = get_arg(args, 1, "") |> to_string()
    
    String.replace(string, pattern, replacement)
  end

  @doc """
  Removes whitespace from both ends of a string.
  
  ## Examples
  
      {{ "  hello  " | strip }} => "hello"
  """
  def strip(input, _args, _options) do
    to_string(input) |> String.trim()
  end

  @doc """
  Splits a string into an array.
  
  ## Examples
  
      {{ "a,b,c" | split: "," }} => ["a", "b", "c"]
  """
  def split(input, args, _options) do
    string = to_string(input)
    delimiter = get_arg(args, 0, ",") |> to_string()
    
    String.split(string, delimiter)
  end

  @doc """
  Joins array elements into a string.
  
  ## Examples
  
      {{ ["a", "b", "c"] | join: ", " }} => "a, b, c"
  """
  def join(input, args, _options) when is_list(input) do
    delimiter = get_arg(args, 0, ", ") |> to_string()
    Enum.join(input, delimiter)
  end
  def join(input, _args, _options), do: to_string(input)

  @doc """
  Returns the size of a string or array.
  
  ## Examples
  
      {{ "hello" | size }} => 5
      {{ ["a", "b", "c"] | size }} => 3
  """
  def size(input, _args, _options) when is_list(input), do: length(input)
  def size(input, _args, _options) when is_binary(input), do: String.length(input)
  def size(input, _args, _options) when is_map(input), do: map_size(input)
  def size(_input, _args, _options), do: 0

  @doc """
  Returns the first element of an array.
  
  ## Examples
  
      {{ ["a", "b", "c"] | first }} => "a"
  """
  def first([head | _], _args, _options), do: head
  def first(_, _args, _options), do: nil

  @doc """
  Returns the last element of an array.
  
  ## Examples
  
      {{ ["a", "b", "c"] | last }} => "c"
  """
  def last(list, _args, _options) when is_list(list) do
    List.last(list)
  end
  def last(_, _args, _options), do: nil

  @doc """
  Formats a date/time string.
  
  ## Examples
  
      {{ "2024-01-15T10:30:00Z" | date: "%Y-%m-%d" }} => "2024-01-15"
  """
  def date(input, args, _options) do
    format = get_arg(args, 0, "%Y-%m-%d %H:%M:%S") |> to_string()
    
    case parse_datetime(input) do
      {:ok, datetime} -> format_datetime(datetime, format)
      _ -> to_string(input)
    end
  end

  @doc """
  Converts a value to a string with default if nil/empty.
  
  ## Examples
  
      {{ nil | default: "N/A" }} => "N/A"
      {{ "" | default: "empty" }} => "empty"
      {{ "hello" | default: "N/A" }} => "hello"
  """
  def default(input, args, _options) do
    default_value = get_arg(args, 0, "") |> to_string()
    
    case input do
      nil -> default_value
      "" -> default_value
      [] -> default_value
      value -> to_string(value)
    end
  end

  @doc """
  Escapes HTML entities in a string.
  
  ## Examples
  
      {{ "<script>alert('hi')</script>" | escape }} => "&lt;script&gt;alert('hi')&lt;/script&gt;"
  """
  def escape(input, _args, _options) do
    input
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  @doc """
  Creates a URL slug from a string.
  
  ## Examples
  
      {{ "Hello World!" | slugify }} => "hello-world"
  """
  def slugify(input, _args, _options) do
    input
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/[-\s]+/, "-")
    |> String.trim("-")
  end

  # Helper functions

  defp get_arg(args, index, default) do
    Enum.at(args, index, default)
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      _ -> 0
    end
  end
  defp to_integer(_), do: 0

  defp parse_datetime(input) when is_binary(input) do
    case DateTime.from_iso8601(input) do
      {:ok, datetime, _} -> {:ok, datetime}
      _ -> 
        case NaiveDateTime.from_iso8601(input) do
          {:ok, naive} -> {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
          _ -> {:error, :invalid_datetime}
        end
    end
  end
  defp parse_datetime(%DateTime{} = datetime), do: {:ok, datetime}
  defp parse_datetime(_), do: {:error, :invalid_input}

  defp format_datetime(datetime, format) do
    # Simple format string replacement - could be enhanced with a proper formatter
    format
    |> String.replace("%Y", datetime.year |> to_string() |> String.pad_leading(4, "0"))
    |> String.replace("%m", datetime.month |> to_string() |> String.pad_leading(2, "0"))
    |> String.replace("%d", datetime.day |> to_string() |> String.pad_leading(2, "0"))
    |> String.replace("%H", datetime.hour |> to_string() |> String.pad_leading(2, "0"))
    |> String.replace("%M", datetime.minute |> to_string() |> String.pad_leading(2, "0"))
    |> String.replace("%S", datetime.second |> to_string() |> String.pad_leading(2, "0"))
  end
end
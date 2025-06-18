defmodule RubberDuck.LLMAbstraction.Message do
  @moduledoc """
  Standard message structure for LLM conversations.
  
  This module defines the universal message format used across all LLM providers
  to ensure consistent conversation handling and compatibility.
  """

  defstruct [:role, :content, :name, :function_call, :tool_calls, :metadata]

  @type role :: :system | :user | :assistant | :function | :tool

  @type function_call :: %{
    name: String.t(),
    arguments: String.t()
  }

  @type tool_call :: %{
    id: String.t(),
    type: String.t(),
    function: function_call()
  }

  @type t :: %__MODULE__{
    role: role(),
    content: String.t() | nil,
    name: String.t() | nil,
    function_call: function_call() | nil,
    tool_calls: [tool_call()] | nil,
    metadata: map()
  }

  @doc """
  Create a system message.
  """
  def system(content, opts \\ []) do
    %__MODULE__{
      role: :system,
      content: content,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a user message.
  """
  def user(content, opts \\ []) do
    %__MODULE__{
      role: :user,
      content: content,
      name: Keyword.get(opts, :name),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create an assistant message.
  """
  def assistant(content, opts \\ []) do
    %__MODULE__{
      role: :assistant,
      content: content,
      function_call: Keyword.get(opts, :function_call),
      tool_calls: Keyword.get(opts, :tool_calls),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a function message.
  """
  def function(content, name, opts \\ []) do
    %__MODULE__{
      role: :function,
      content: content,
      name: name,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a tool message.
  """
  def tool(content, tool_call_id, opts \\ []) do
    %__MODULE__{
      role: :tool,
      content: content,
      name: tool_call_id,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Validate message structure.
  """
  def validate(%__MODULE__{} = message) do
    with :ok <- validate_role(message.role),
         :ok <- validate_content(message),
         :ok <- validate_function_fields(message) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(_), do: {:error, :invalid_message_structure}

  @doc """
  Convert message to provider-specific format.
  """
  def to_provider_format(%__MODULE__{} = message, :openai) do
    base = %{
      "role" => to_string(message.role),
      "content" => message.content
    }

    base
    |> maybe_add_field("name", message.name)
    |> maybe_add_field("function_call", message.function_call)
    |> maybe_add_field("tool_calls", message.tool_calls)
  end

  def to_provider_format(%__MODULE__{} = message, :anthropic) do
    %{
      "role" => map_role_for_anthropic(message.role),
      "content" => message.content || ""
    }
  end

  def to_provider_format(%__MODULE__{} = message, :generic) do
    %{
      role: message.role,
      content: message.content,
      name: message.name,
      function_call: message.function_call,
      tool_calls: message.tool_calls,
      metadata: message.metadata
    }
  end

  @doc """
  Convert from provider-specific format to standard message.
  """
  def from_provider_format(provider_message, :openai) do
    %__MODULE__{
      role: String.to_existing_atom(provider_message["role"]),
      content: provider_message["content"],
      name: provider_message["name"],
      function_call: provider_message["function_call"],
      tool_calls: provider_message["tool_calls"],
      metadata: %{}
    }
  rescue
    ArgumentError -> {:error, :invalid_role}
  end

  def from_provider_format(provider_message, :anthropic) do
    %__MODULE__{
      role: map_role_from_anthropic(provider_message["role"]),
      content: provider_message["content"],
      metadata: %{}
    }
  end

  def from_provider_format(provider_message, :generic) do
    struct(__MODULE__, provider_message)
  end

  @doc """
  Extract text content from message, handling various content formats.
  """
  def extract_text_content(%__MODULE__{content: content}) when is_binary(content) do
    content
  end

  def extract_text_content(%__MODULE__{content: content}) when is_list(content) do
    content
    |> Enum.filter(&(is_map(&1) and Map.get(&1, "type") == "text"))
    |> Enum.map(&Map.get(&1, "text", ""))
    |> Enum.join("")
  end

  def extract_text_content(%__MODULE__{content: nil}) do
    ""
  end

  def extract_text_content(%__MODULE__{content: content}) when is_map(content) do
    Map.get(content, "text", "")
  end

  # Private Functions

  defp validate_role(role) when role in [:system, :user, :assistant, :function, :tool] do
    :ok
  end

  defp validate_role(_), do: {:error, :invalid_role}

  defp validate_content(%__MODULE__{role: :function, name: nil}) do
    {:error, :function_message_requires_name}
  end

  defp validate_content(%__MODULE__{role: :tool, name: nil}) do
    {:error, :tool_message_requires_name}
  end

  defp validate_content(_), do: :ok

  defp validate_function_fields(%__MODULE__{function_call: function_call}) when not is_nil(function_call) do
    if is_map(function_call) and Map.has_key?(function_call, :name) do
      :ok
    else
      {:error, :invalid_function_call}
    end
  end

  defp validate_function_fields(%__MODULE__{tool_calls: tool_calls}) when is_list(tool_calls) do
    if Enum.all?(tool_calls, &valid_tool_call?/1) do
      :ok
    else
      {:error, :invalid_tool_calls}
    end
  end

  defp validate_function_fields(_), do: :ok

  defp valid_tool_call?(%{id: id, type: type, function: function}) 
       when is_binary(id) and is_binary(type) and is_map(function) do
    Map.has_key?(function, :name)
  end

  defp valid_tool_call?(_), do: false

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  defp map_role_for_anthropic(:system), do: "system"
  defp map_role_for_anthropic(:user), do: "user"
  defp map_role_for_anthropic(:assistant), do: "assistant"
  defp map_role_for_anthropic(_), do: "user"  # Default fallback

  defp map_role_from_anthropic("system"), do: :system
  defp map_role_from_anthropic("user"), do: :user
  defp map_role_from_anthropic("assistant"), do: :assistant
  defp map_role_from_anthropic(_), do: :user  # Default fallback
end
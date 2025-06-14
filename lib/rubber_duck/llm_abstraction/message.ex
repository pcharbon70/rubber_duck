defprotocol RubberDuck.LLMAbstraction.Message do
  @moduledoc """
  Protocol for provider-agnostic message handling.
  
  This protocol enables different message types to be transformed into
  provider-specific formats while maintaining a consistent interface.
  Messages can represent user input, assistant responses, system prompts,
  or function calls.
  """

  @doc """
  Convert the message to a provider-specific format.
  
  ## Parameters
    - message: The message to convert
    - provider: Atom identifying the target provider (:openai, :anthropic, etc.)
    
  ## Returns
    - Map in the provider's expected format
  """
  @spec to_provider_format(t, atom()) :: map()
  def to_provider_format(message, provider)

  @doc """
  Get the role of the message.
  
  Standard roles: :system, :user, :assistant, :function
  """
  @spec role(t) :: atom()
  def role(message)

  @doc """
  Get the content of the message.
  
  Returns the main content, which could be text, structured data, or nil.
  """
  @spec content(t) :: String.t() | map() | nil
  def content(message)

  @doc """
  Check if the message contains multi-modal content.
  
  Returns true if the message includes images, files, or other non-text content.
  """
  @spec multimodal?(t) :: boolean()
  def multimodal?(message)

  @doc """
  Extract metadata from the message.
  
  Returns any additional metadata associated with the message.
  """
  @spec metadata(t) :: map()
  def metadata(message)
end

defmodule RubberDuck.LLMAbstraction.Message.Text do
  @moduledoc """
  Simple text message implementation.
  """
  
  defstruct [:role, :content, :name, metadata: %{}]
  
  @type t :: %__MODULE__{
    role: :system | :user | :assistant,
    content: String.t(),
    name: String.t() | nil,
    metadata: map()
  }
end

defimpl RubberDuck.LLMAbstraction.Message, for: RubberDuck.LLMAbstraction.Message.Text do
  def to_provider_format(message, :openai) do
    base = %{
      "role" => to_string(message.role),
      "content" => message.content
    }
    
    if message.name do
      Map.put(base, "name", message.name)
    else
      base
    end
  end

  def to_provider_format(message, :anthropic) do
    %{
      "role" => anthropic_role(message.role),
      "content" => message.content
    }
  end

  def to_provider_format(message, _provider) do
    # Default format
    %{
      "role" => to_string(message.role),
      "content" => message.content,
      "metadata" => message.metadata
    }
  end

  def role(message), do: message.role
  def content(message), do: message.content
  def multimodal?(_message), do: false
  def metadata(message), do: message.metadata

  defp anthropic_role(:system), do: "system"
  defp anthropic_role(:user), do: "user"
  defp anthropic_role(:assistant), do: "assistant"
end

defmodule RubberDuck.LLMAbstraction.Message.Function do
  @moduledoc """
  Function call message implementation.
  """
  
  defstruct [:name, :arguments, :result, metadata: %{}]
  
  @type t :: %__MODULE__{
    name: String.t(),
    arguments: map() | String.t(),
    result: term() | nil,
    metadata: map()
  }
end

defimpl RubberDuck.LLMAbstraction.Message, for: RubberDuck.LLMAbstraction.Message.Function do
  def to_provider_format(message, :openai) do
    if message.result do
      # Function result message
      %{
        "role" => "function",
        "name" => message.name,
        "content" => Jason.encode!(message.result)
      }
    else
      # Function call message
      %{
        "role" => "assistant",
        "content" => nil,
        "function_call" => %{
          "name" => message.name,
          "arguments" => encode_arguments(message.arguments)
        }
      }
    end
  end

  def to_provider_format(message, :anthropic) do
    # Anthropic uses a different format for function calls
    %{
      "role" => "assistant",
      "content" => [
        %{
          "type" => "tool_use",
          "id" => generate_id(),
          "name" => message.name,
          "input" => message.arguments
        }
      ]
    }
  end

  def to_provider_format(message, _provider) do
    %{
      "type" => "function",
      "name" => message.name,
      "arguments" => message.arguments,
      "result" => message.result,
      "metadata" => message.metadata
    }
  end

  def role(_message), do: :function
  def content(message), do: message.result || message.arguments
  def multimodal?(_message), do: false
  def metadata(message), do: message.metadata

  defp encode_arguments(args) when is_map(args), do: Jason.encode!(args)
  defp encode_arguments(args) when is_binary(args), do: args

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end

defmodule RubberDuck.LLMAbstraction.Message.Multimodal do
  @moduledoc """
  Multimodal message implementation supporting text and images.
  """
  
  defstruct [:role, :parts, metadata: %{}]
  
  @type part :: {:text, String.t()} | {:image_url, String.t()} | {:image_base64, String.t(), String.t()}
  @type t :: %__MODULE__{
    role: :user | :assistant,
    parts: [part()],
    metadata: map()
  }
end

defimpl RubberDuck.LLMAbstraction.Message, for: RubberDuck.LLMAbstraction.Message.Multimodal do
  def to_provider_format(message, :openai) do
    content = Enum.map(message.parts, fn
      {:text, text} -> 
        %{"type" => "text", "text" => text}
      {:image_url, url} -> 
        %{"type" => "image_url", "image_url" => %{"url" => url}}
      {:image_base64, data, mime_type} ->
        %{"type" => "image_url", "image_url" => %{"url" => "data:#{mime_type};base64,#{data}"}}
    end)
    
    %{
      "role" => to_string(message.role),
      "content" => content
    }
  end

  def to_provider_format(message, :anthropic) do
    content = Enum.map(message.parts, fn
      {:text, text} -> 
        %{"type" => "text", "text" => text}
      {:image_url, _url} -> 
        # Anthropic doesn't support URLs directly, would need to fetch
        %{"type" => "text", "text" => "[Image from URL - not supported]"}
      {:image_base64, data, mime_type} ->
        %{
          "type" => "image",
          "source" => %{
            "type" => "base64",
            "media_type" => mime_type,
            "data" => data
          }
        }
    end)
    
    %{
      "role" => to_string(message.role),
      "content" => content
    }
  end

  def to_provider_format(message, _provider) do
    %{
      "role" => to_string(message.role),
      "parts" => Enum.map(message.parts, fn
        {:text, text} -> %{"type" => "text", "content" => text}
        {:image_url, url} -> %{"type" => "image_url", "url" => url}
        {:image_base64, data, mime} -> %{"type" => "image_base64", "data" => data, "mime_type" => mime}
      end),
      "metadata" => message.metadata
    }
  end

  def role(message), do: message.role
  
  def content(message) do
    # Extract text content only
    message.parts
    |> Enum.filter(fn {type, _} -> type == :text end)
    |> Enum.map(fn {_, text} -> text end)
    |> Enum.join("\n")
  end

  def multimodal?(_message), do: true
  def metadata(message), do: message.metadata
end

defmodule RubberDuck.LLMAbstraction.Message.Factory do
  @moduledoc """
  Factory functions for creating messages.
  """

  alias RubberDuck.LLMAbstraction.Message

  @doc """
  Create a system message.
  """
  def system(content, opts \\ []) do
    %Message.Text{
      role: :system,
      content: content,
      name: Keyword.get(opts, :name),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a user message.
  """
  def user(content, opts \\ []) do
    %Message.Text{
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
    %Message.Text{
      role: :assistant,
      content: content,
      name: Keyword.get(opts, :name),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a function call message.
  """
  def function_call(name, arguments, opts \\ []) do
    %Message.Function{
      name: name,
      arguments: arguments,
      result: nil,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a function result message.
  """
  def function_result(name, result, opts \\ []) do
    %Message.Function{
      name: name,
      arguments: nil,
      result: result,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a multimodal message.
  """
  def multimodal(role, parts, opts \\ []) do
    %Message.Multimodal{
      role: role,
      parts: parts,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
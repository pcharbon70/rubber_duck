defmodule RubberDuck.LLMAbstraction do
  @moduledoc """
  Main interface for the LLM abstraction layer.
  
  This module provides a unified API for interacting with multiple LLM providers
  through a consistent interface. It handles provider registration, capability
  discovery, intelligent routing, and response handling.
  
  ## Usage
  
      # Register providers
      RubberDuck.LLMAbstraction.register_provider(:openai, OpenAIProvider, config)
      RubberDuck.LLMAbstraction.register_provider(:anthropic, AnthropicProvider, config)
      
      # Simple chat
      {:ok, response} = RubberDuck.LLMAbstraction.chat(:openai, messages)
      
      # Auto-routing based on capabilities
      {:ok, response} = RubberDuck.LLMAbstraction.auto_chat(messages, requirements: [:vision])
      
      # Stream responses
      {:ok, stream} = RubberDuck.LLMAbstraction.stream(:anthropic, messages)
  """

  alias RubberDuck.LLMAbstraction.{ProviderRegistry, Message}

  @doc """
  Start the LLM abstraction layer.
  
  This should be called during application startup to initialize the provider registry.
  """
  def start_link(opts \\ []) do
    ProviderRegistry.start_link(opts)
  end

  @doc """
  Register a provider with the abstraction layer.
  """
  def register_provider(name, module, config) do
    ProviderRegistry.register_provider(name, module, config)
  end

  @doc """
  Unregister a provider from the abstraction layer.
  """
  def unregister_provider(name) do
    ProviderRegistry.unregister_provider(name)
  end

  @doc """
  Execute a chat completion with a specific provider.
  """
  def chat(provider_name, messages, opts \\ []) do
    ProviderRegistry.chat(provider_name, messages, opts)
  end

  @doc """
  Execute a text completion with a specific provider.
  """
  def complete(provider_name, prompt, opts \\ []) do
    ProviderRegistry.complete(provider_name, prompt, opts)
  end

  @doc """
  Generate embeddings with a specific provider.
  """
  def embed(provider_name, input, opts \\ []) do
    ProviderRegistry.embed(provider_name, input, opts)
  end

  @doc """
  Execute a chat completion with automatic provider selection.
  
  Selects the best provider based on requirements and current health status.
  """
  def auto_chat(messages, opts \\ []) do
    requirements = Keyword.get(opts, :requirements, [:chat_completion])
    
    case find_best_provider(requirements) do
      nil -> 
        {:error, :no_suitable_provider}
      
      provider_name ->
        provider_opts = Keyword.drop(opts, [:requirements])
        chat(provider_name, messages, provider_opts)
    end
  end

  @doc """
  Execute a text completion with automatic provider selection.
  """
  def auto_complete(prompt, opts \\ []) do
    requirements = Keyword.get(opts, :requirements, [:text_completion])
    
    case find_best_provider(requirements) do
      nil -> 
        {:error, :no_suitable_provider}
      
      provider_name ->
        provider_opts = Keyword.drop(opts, [:requirements])
        complete(provider_name, prompt, provider_opts)
    end
  end

  @doc """
  Generate embeddings with automatic provider selection.
  """
  def auto_embed(input, opts \\ []) do
    requirements = Keyword.get(opts, :requirements, [:embeddings])
    
    case find_best_provider(requirements) do
      nil -> 
        {:error, :no_suitable_provider}
      
      provider_name ->
        provider_opts = Keyword.drop(opts, [:requirements])
        embed(provider_name, input, provider_opts)
    end
  end

  @doc """
  Stream a chat completion with a specific provider.
  """
  def stream(provider_name, _messages, _opts \\ []) do
    # First check if provider supports streaming
    case ProviderRegistry.get_provider(provider_name) do
      {:ok, provider_info} ->
        streaming_supported = Enum.any?(provider_info.capabilities, fn cap ->
          cap.name == :streaming && cap.enabled
        end)
        
        if streaming_supported do
          # Execute streaming through registry (would need to add this function)
          {:error, :streaming_not_implemented_in_registry}
        else
          {:error, :streaming_not_supported}
        end
        
      error ->
        error
    end
  end

  @doc """
  List all registered providers.
  """
  def list_providers do
    ProviderRegistry.list_providers()
  end

  @doc """
  Find providers that satisfy the given requirements.
  """
  def find_providers(requirements) do
    ProviderRegistry.find_providers(requirements)
  end

  @doc """
  Get information about a specific provider.
  """
  def get_provider(name) do
    ProviderRegistry.get_provider(name)
  end

  @doc """
  Check the health status of a provider.
  """
  def health_status(provider_name) do
    ProviderRegistry.health_status(provider_name)
  end

  @doc """
  Get health status of all providers.
  """
  def health_status_all do
    providers = list_providers()
    
    Enum.map(providers, fn {name, _info} ->
      case health_status(name) do
        {:ok, status} -> {name, status}
        {:error, _} -> {name, :unknown}
      end
    end)
    |> Map.new()
  end

  @doc """
  Create a conversation context for multi-turn chats.
  """
  def create_conversation(provider_name, system_prompt \\ nil, opts \\ []) do
    messages = case system_prompt do
      nil -> []
      prompt -> [Message.Factory.system(prompt)]
    end
    
    %{
      provider: provider_name,
      messages: messages,
      options: opts,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Add a message to a conversation context.
  """
  def add_message(conversation, message) do
    %{conversation | messages: conversation.messages ++ [message]}
  end

  @doc """
  Continue a conversation with a user message.
  """
  def continue_conversation(conversation, user_message, opts \\ []) do
    message = case user_message do
      %Message.Text{} -> user_message
      text when is_binary(text) -> Message.Factory.user(text)
    end
    
    updated_conversation = add_message(conversation, message)
    merged_opts = Keyword.merge(conversation.options, opts)
    
    case chat(conversation.provider, updated_conversation.messages, merged_opts) do
      {:ok, response} ->
        assistant_message = response |> RubberDuck.LLMAbstraction.Response.to_message()
        final_conversation = add_message(updated_conversation, assistant_message)
        {:ok, response, final_conversation}
        
      error ->
        error
    end
  end

  # Private Functions

  defp find_best_provider(requirements) do
    case find_providers(requirements) do
      [] -> nil
      [{provider_name, _capabilities} | _] ->
        # Return the first match (could be enhanced with scoring)
        provider_name
    end
  end

  @doc """
  Convenience functions for creating messages.
  """
  defdelegate system(content, opts \\ []), to: Message.Factory
  defdelegate user(content, opts \\ []), to: Message.Factory
  defdelegate assistant(content, opts \\ []), to: Message.Factory
  defdelegate function_call(name, arguments, opts \\ []), to: Message.Factory
  defdelegate function_result(name, result, opts \\ []), to: Message.Factory
  defdelegate multimodal(role, parts, opts \\ []), to: Message.Factory
end
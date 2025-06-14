defmodule RubberDuck.LLMAbstraction.Adapters.LangChainAdapter do
  @moduledoc """
  Adapter for LangChain-compatible providers.
  
  This module provides a bridge between the RubberDuck LLM abstraction
  and LangChain-style provider implementations. It translates between
  LangChain's API patterns and the RubberDuck Provider behavior.
  
  Note: This is a reference implementation for future LangChain integration.
  Currently acts as a wrapper around standard HTTP providers.
  """

  @behaviour RubberDuck.LLMAbstraction.Provider

  alias RubberDuck.LLMAbstraction.{Message, Response, Capability}

  defstruct [
    :provider_name,
    :langchain_module,
    :config,
    :client,
    :call_count
  ]

  @impl true
  def init(config) do
    provider_name = config[:provider_name] || :langchain_generic
    langchain_module = config[:langchain_module]
    
    with :ok <- validate_langchain_module(langchain_module),
         {:ok, client} <- initialize_langchain_client(langchain_module, config) do
      
      state = %__MODULE__{
        provider_name: provider_name,
        langchain_module: langchain_module,
        config: config,
        client: client,
        call_count: 0
      }
      
      {:ok, state}
    end
  end

  @impl true
  def chat(messages, state, opts) do
    # Convert messages to LangChain format
    langchain_messages = Enum.map(messages, &to_langchain_message/1)
    
    # Execute through LangChain interface
    case execute_langchain_call(state.langchain_module, :chat, [langchain_messages, opts], state) do
      {:ok, langchain_response} ->
        response = convert_langchain_response(langchain_response, state.provider_name)
        new_state = %{state | call_count: state.call_count + 1}
        {:ok, response, new_state}
        
      {:error, reason} ->
        new_state = %{state | call_count: state.call_count + 1}
        {:error, reason, new_state}
    end
  end

  @impl true
  def complete(prompt, state, opts) do
    case execute_langchain_call(state.langchain_module, :complete, [prompt, opts], state) do
      {:ok, langchain_response} ->
        response = convert_langchain_response(langchain_response, state.provider_name)
        new_state = %{state | call_count: state.call_count + 1}
        {:ok, response, new_state}
        
      {:error, reason} ->
        new_state = %{state | call_count: state.call_count + 1}
        {:error, reason, new_state}
    end
  end

  @impl true
  def embed(input, state, opts) do
    case execute_langchain_call(state.langchain_module, :embed, [input, opts], state) do
      {:ok, embeddings} ->
        new_state = %{state | call_count: state.call_count + 1}
        {:ok, embeddings, new_state}
        
      {:error, reason} ->
        new_state = %{state | call_count: state.call_count + 1}
        {:error, reason, new_state}
    end
  end

  @impl true
  def stream_chat(messages, state, opts) do
    langchain_messages = Enum.map(messages, &to_langchain_message/1)
    
    case execute_langchain_call(state.langchain_module, :stream_chat, [langchain_messages, opts], state) do
      {:ok, stream} ->
        # Wrap the LangChain stream to convert formats
        converted_stream = Stream.map(stream, &convert_langchain_chunk/1)
        new_state = %{state | call_count: state.call_count + 1}
        {:ok, converted_stream, new_state}
        
      {:error, reason} ->
        new_state = %{state | call_count: state.call_count + 1}
        {:error, reason, new_state}
    end
  end

  @impl true
  def capabilities(state) do
    # Query LangChain module for capabilities if supported
    case execute_langchain_call(state.langchain_module, :capabilities, [], state) do
      {:ok, langchain_capabilities} ->
        convert_langchain_capabilities(langchain_capabilities)
        
      {:error, _} ->
        # Fallback to default capabilities
        default_capabilities()
    end
  end

  @impl true
  def health_check(state) do
    case execute_langchain_call(state.langchain_module, :health_check, [], state) do
      {:ok, :healthy} -> :healthy
      {:ok, :unhealthy} -> :unhealthy
      {:ok, status} when status in [:healthy, :degraded, :unhealthy] -> status
      _ -> :degraded
    end
  end

  @impl true
  def terminate(state) do
    # Clean up LangChain resources if supported
    case execute_langchain_call(state.langchain_module, :terminate, [state.client], state) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  @impl true
  def validate_config(config) do
    required_keys = [:langchain_module]
    case RubberDuck.LLMAbstraction.Provider.validate_required_keys(config, required_keys) do
      :ok -> 
        if valid_langchain_module?(config[:langchain_module]) do
          :ok
        else
          {:error, {:invalid_langchain_module, config[:langchain_module]}}
        end
      error -> error
    end
  end

  @impl true
  def metadata do
    %{
      name: "LangChain Adapter",
      version: "1.0.0",
      description: "Adapter for LangChain-compatible providers",
      author: "RubberDuck Team",
      adapter: true
    }
  end

  # Private Functions

  defp validate_langchain_module(nil), do: {:error, :missing_langchain_module}
  defp validate_langchain_module(module) when is_atom(module) do
    if valid_langchain_module?(module) do
      :ok
    else
      {:error, {:invalid_langchain_module, module}}
    end
  end
  defp validate_langchain_module(_), do: {:error, :invalid_langchain_module_type}

  defp valid_langchain_module?(module) when is_atom(module) do
    # Check if module exists and has required functions
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        required_functions = [:chat, :complete]
        Enum.all?(required_functions, &function_exported?(module, &1, 2))
      
      {:error, _} -> false
    end
  end
  defp valid_langchain_module?(_), do: false

  defp initialize_langchain_client(module, config) do
    if function_exported?(module, :init, 1) do
      module.init(config)
    else
      {:ok, nil}
    end
  end

  defp execute_langchain_call(module, function, args, _state) do
    if function_exported?(module, function, length(args)) do
      try do
        result = apply(module, function, args)
        {:ok, result}
      rescue
        error -> {:error, {:langchain_error, error}}
      end
    else
      {:error, {:function_not_supported, function}}
    end
  end

  defp to_langchain_message(message) do
    # Convert RubberDuck message to LangChain format
    %{
      role: Message.role(message),
      content: Message.content(message),
      metadata: Message.metadata(message)
    }
  end

  defp convert_langchain_response(langchain_response, provider_name) do
    # Convert LangChain response to RubberDuck Response
    Response.new(%{
      id: Map.get(langchain_response, :id),
      provider: provider_name,
      model: Map.get(langchain_response, :model, "langchain-model"),
      content: Map.get(langchain_response, :content),
      role: Map.get(langchain_response, :role, :assistant),
      finish_reason: convert_finish_reason(Map.get(langchain_response, :finish_reason)),
      usage: convert_usage(Map.get(langchain_response, :usage)),
      metadata: Map.get(langchain_response, :metadata, %{}),
      raw_response: langchain_response
    })
  end

  defp convert_langchain_chunk(chunk) do
    # Convert LangChain streaming chunk to OpenAI-compatible format
    %{
      "choices" => [
        %{
          "delta" => %{
            "content" => Map.get(chunk, :content, "")
          },
          "index" => 0
        }
      ]
    }
  end

  defp convert_langchain_capabilities(langchain_caps) when is_list(langchain_caps) do
    Enum.map(langchain_caps, &convert_langchain_capability/1)
  end
  defp convert_langchain_capabilities(_), do: default_capabilities()

  defp convert_langchain_capability(%{name: name, constraints: constraints}) do
    %Capability{
      name: name,
      type: name,
      enabled: true,
      constraints: constraints || [],
      metadata: %{adapter: :langchain}
    }
  end
  defp convert_langchain_capability(name) when is_atom(name) do
    %Capability{
      name: name,
      type: name,
      enabled: true,
      constraints: [],
      metadata: %{adapter: :langchain}
    }
  end

  defp convert_finish_reason(nil), do: nil
  defp convert_finish_reason(:stop), do: :stop
  defp convert_finish_reason(:length), do: :length
  defp convert_finish_reason(:error), do: :error
  defp convert_finish_reason(_), do: :unknown

  defp convert_usage(nil), do: nil
  defp convert_usage(usage) when is_map(usage) do
    %{
      prompt_tokens: Map.get(usage, :prompt_tokens, 0),
      completion_tokens: Map.get(usage, :completion_tokens, 0),
      total_tokens: Map.get(usage, :total_tokens, 0),
      cost: Map.get(usage, :cost)
    }
  end

  defp default_capabilities do
    [
      Capability.chat_completion(),
      Capability.text_completion()
    ]
  end
end

defmodule RubberDuck.LLMAbstraction.Adapters.LangChainRegistry do
  @moduledoc """
  Registry for LangChain-compatible providers.
  
  This module helps register and discover LangChain providers that can
  be adapted through the LangChainAdapter.
  """

  @doc """
  Register a LangChain provider with the main ProviderRegistry.
  """
  def register_langchain_provider(name, langchain_module, config \\ %{}) do
    adapter_config = Map.merge(config, %{
      provider_name: name,
      langchain_module: langchain_module
    })
    
    alias RubberDuck.LLMAbstraction.ProviderRegistry
    alias RubberDuck.LLMAbstraction.Adapters.LangChainAdapter
    
    ProviderRegistry.register_provider(name, LangChainAdapter, adapter_config)
  end

  @doc """
  List available LangChain modules that could be adapted.
  """
  def discover_langchain_modules do
    # This would scan for modules that implement LangChain patterns
    # For now, return an empty list as no real LangChain modules exist
    []
  end

  @doc """
  Validate a LangChain module for compatibility.
  """
  def validate_langchain_module(module) do
    required_functions = [
      {:chat, 2},
      {:complete, 2}
    ]
    
    optional_functions = [
      {:embed, 2},
      {:stream_chat, 2},
      {:capabilities, 0},
      {:health_check, 0},
      {:init, 1},
      {:terminate, 1}
    ]
    
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        missing_required = Enum.reject(required_functions, fn {func, arity} ->
          function_exported?(module, func, arity)
        end)
        
        if Enum.empty?(missing_required) do
          available_optional = Enum.filter(optional_functions, fn {func, arity} ->
            function_exported?(module, func, arity)
          end)
          
          {:ok, %{
            required: required_functions,
            optional: available_optional,
            missing_required: [],
            missing_optional: optional_functions -- available_optional
          }}
        else
          {:error, {:missing_required_functions, missing_required}}
        end
      
      {:error, reason} ->
        {:error, {:module_not_found, reason}}
    end
  end
end
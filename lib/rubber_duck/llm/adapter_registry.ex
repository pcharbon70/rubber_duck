defmodule RubberDuck.LLM.AdapterRegistry do
  @moduledoc """
  Registry for LLM provider adapters.
  
  Provides a centralized way to look up provider adapters by name,
  supporting the stateless LLM service architecture.
  """
  
  @adapters %{
    openai: RubberDuck.LLM.Providers.OpenAI,
    anthropic: RubberDuck.LLM.Providers.Anthropic,
    ollama: RubberDuck.LLM.Providers.Ollama,
    tgi: RubberDuck.LLM.Providers.TGI,
    mock: RubberDuck.LLM.Providers.Mock
  }
  
  @doc """
  Get the adapter module for a provider.
  
  ## Examples
  
      iex> AdapterRegistry.get_adapter(:openai)
      {:ok, RubberDuck.LLM.Providers.OpenAI}
      
      iex> AdapterRegistry.get_adapter(:unknown)
      {:error, {:unknown_provider, :unknown}}
  """
  @spec get_adapter(atom()) :: {:ok, module()} | {:error, {:unknown_provider, atom()}}
  def get_adapter(provider_name) when is_atom(provider_name) do
    case Map.get(@adapters, provider_name) do
      nil -> {:error, {:unknown_provider, provider_name}}
      adapter -> {:ok, adapter}
    end
  end
  
  @doc """
  List all available provider names.
  """
  @spec list_providers() :: [atom()]
  def list_providers do
    Map.keys(@adapters)
  end
  
  @doc """
  Check if a provider is registered.
  """
  @spec provider_exists?(atom()) :: boolean()
  def provider_exists?(provider_name) when is_atom(provider_name) do
    Map.has_key?(@adapters, provider_name)
  end
end
defmodule RubberDuck.LLM.ModelConfig do
  @moduledoc """
  Manages LLM model configuration and defaults.
  
  Provides functionality to:
  - Set and get default models
  - Store model preferences per provider
  - Handle model availability
  """
  
  use GenServer
  require Logger
  
  @default_model "codellama"
  @config_key :llm_model_config
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Sets the default model for LLM operations.
  """
  def set_default_model(model) when is_binary(model) do
    GenServer.call(__MODULE__, {:set_default_model, model})
  end
  
  @doc """
  Gets the current default model.
  """
  def get_default_model do
    GenServer.call(__MODULE__, :get_default_model)
  end
  
  @doc """
  Sets the model for a specific provider.
  """
  def set_provider_model(provider, model) when is_atom(provider) and is_binary(model) do
    GenServer.call(__MODULE__, {:set_provider_model, provider, model})
  end
  
  @doc """
  Gets the model for a specific provider.
  """
  def get_provider_model(provider) when is_atom(provider) do
    GenServer.call(__MODULE__, {:get_provider_model, provider})
  end
  
  @doc """
  Gets the effective model (provider-specific or default).
  """
  def get_effective_model(provider) when is_atom(provider) do
    case get_provider_model(provider) do
      nil -> get_default_model()
      model -> model
    end
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Load from persistent storage if available
    state = load_state() || %{
      default_model: @default_model,
      provider_models: %{}
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:set_default_model, model}, _from, state) do
    new_state = %{state | default_model: model}
    save_state(new_state)
    Logger.info("Default LLM model set to: #{model}")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_default_model, _from, state) do
    {:reply, state.default_model, state}
  end
  
  @impl true
  def handle_call({:set_provider_model, provider, model}, _from, state) do
    new_provider_models = Map.put(state.provider_models, provider, model)
    new_state = %{state | provider_models: new_provider_models}
    save_state(new_state)
    Logger.info("Model for provider #{provider} set to: #{model}")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:get_provider_model, provider}, _from, state) do
    model = Map.get(state.provider_models, provider)
    {:reply, model, state}
  end
  
  # Private functions
  
  defp load_state do
    case :persistent_term.get(@config_key, nil) do
      nil -> nil
      state -> state
    end
  end
  
  defp save_state(state) do
    :persistent_term.put(@config_key, state)
  end
end
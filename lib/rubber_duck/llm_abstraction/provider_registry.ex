defmodule RubberDuck.LLMAbstraction.ProviderRegistry do
  @moduledoc """
  Basic provider registry for section 3.2 compatibility.
  
  This is a minimal implementation to support the load balancing components.
  The full implementation was created in section 3.1.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{providers: %{}}}
  end

  def list_providers do
    GenServer.call(__MODULE__, :list_providers)
  end

  def find_providers(_requirements) do
    # Basic implementation - return all providers
    list_providers()
    |> Enum.map(fn {name, _info} -> name end)
  end

  def health_status(_provider_name) do
    {:ok, :healthy}
  end

  @impl true
  def handle_call(:list_providers, _from, state) do
    {:reply, state.providers, state}
  end
end
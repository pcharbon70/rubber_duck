defmodule RubberDuckWeb.Collaboration.EditorSupervisor do
  @moduledoc """
  Supervisor for collaborative editing sessions.

  Manages dynamic collaborative editor processes for each file being edited.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end

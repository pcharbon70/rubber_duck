defmodule RubberDuck.ContextSupervisor do
  @moduledoc """
  Supervisor for context management processes.

  Manages session state, conversation context, and related
  processes for AI assistant interactions.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Context management processes will be added here
      # in subsequent implementation steps
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
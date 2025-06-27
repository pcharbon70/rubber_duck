defmodule RubberDuckCore.Supervisor do
  @moduledoc """
  Main supervisor for RubberDuckCore business logic processes.

  This supervisor manages the core business logic processes including:
  - Conversation management
  - Analysis coordination
  - System state management
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Core business logic processes
      {RubberDuckCore.ConversationManager, [name: RubberDuckCore.ConversationManager]},
      # Inter-app communication
      {RubberDuckCore.PubSub, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

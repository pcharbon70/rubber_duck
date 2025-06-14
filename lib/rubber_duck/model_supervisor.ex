defmodule RubberDuck.ModelSupervisor do
  @moduledoc """
  Supervisor for AI model coordination processes.

  Manages AI model instances, coordination logic, and
  related processes for distributed AI operations.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {RubberDuck.ModelCoordinator, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
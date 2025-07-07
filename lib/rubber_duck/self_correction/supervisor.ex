defmodule RubberDuck.SelfCorrection.Supervisor do
  @moduledoc """
  Supervisor for the self-correction subsystem.

  Manages all processes related to iterative self-correction,
  including the engine, history tracking, and learning components.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # History tracker - must start first
      {RubberDuck.SelfCorrection.History, []},

      # Learning system - depends on history
      {RubberDuck.SelfCorrection.Learner, []},

      # Main correction engine
      {RubberDuck.SelfCorrection.Engine, []}
    ]

    # Restart strategy: if a child dies, only restart that child
    # This prevents cascading failures while maintaining service availability
    opts = [
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    ]

    Supervisor.init(children, opts)
  end

  @doc """
  Returns child specifications for all strategy modules.

  This can be used to dynamically load strategy implementations.
  """
  def strategy_specs() do
    [
      RubberDuck.SelfCorrection.Strategies.Syntax,
      RubberDuck.SelfCorrection.Strategies.Semantic,
      RubberDuck.SelfCorrection.Strategies.Logic
    ]
  end

  @doc """
  Checks if all required processes are running.
  """
  def health_check() do
    children = [
      RubberDuck.SelfCorrection.Engine,
      RubberDuck.SelfCorrection.History,
      RubberDuck.SelfCorrection.Learner
    ]

    all_healthy =
      Enum.all?(children, fn module ->
        case Process.whereis(module) do
          nil -> false
          pid -> Process.alive?(pid)
        end
      end)

    if all_healthy do
      {:ok, "All self-correction processes are running"}
    else
      {:error, "Some self-correction processes are not running"}
    end
  end
end

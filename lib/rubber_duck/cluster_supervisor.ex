defmodule RubberDuck.ClusterSupervisor do
  @moduledoc """
  Supervisor for cluster management processes.

  Manages libcluster configuration and supervises cluster-related
  processes for distributed operations.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Extract strategies from opts, default to gossip for development
    strategies = Keyword.get(opts, :strategies, default_strategies())
    
    # Convert strategies to libcluster topology format
    topologies = [
      rubber_duck: [
        strategy: get_strategy_module(strategies),
        config: get_strategy_config(strategies)
      ]
    ]

    children = [
      # libcluster supervisor with topology configuration
      {Cluster.Supervisor, [topologies, [name: Cluster.Supervisor]]},
      # Node monitoring GenServer
      {RubberDuck.NodeMonitor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private Functions

  defp default_strategies do
    [{Cluster.Strategy.Gossip, [
      port: 45892,
      if_addr: "0.0.0.0",
      multicast_addr: "230.1.1.251",
      broadcast_only: true
    ]}]
  end

  defp get_strategy_module([{strategy_module, _config} | _]), do: strategy_module
  defp get_strategy_module([]), do: Cluster.Strategy.Gossip

  defp get_strategy_config([{_strategy_module, config} | _]), do: config
  defp get_strategy_config([]), do: []
end
defmodule RubberDuck.Nebulex.Cache.L1 do
  @moduledoc """
  L1 (Local) cache adapter for hot data with fast access.
  Uses in-memory storage optimized for single-node performance.
  """
  
  use Nebulex.Cache,
    otp_app: :rubber_duck,
    adapter: Nebulex.Adapters.Local
end
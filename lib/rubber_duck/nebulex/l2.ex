defmodule RubberDuck.Nebulex.Cache.L2 do
  @moduledoc """
  L2 (Replicated) cache adapter for distributed data across cluster nodes.
  Uses Cachex as the underlying storage with Nebulex replication features.
  """
  
  use Nebulex.Cache,
    otp_app: :rubber_duck,
    adapter: Nebulex.Adapters.Replicated
end
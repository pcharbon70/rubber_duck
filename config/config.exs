# Config for RubberDuck Application

import Config

# L1 Cache - Local in-memory cache for hot data
config :rubber_duck, RubberDuck.Nebulex.Cache.L1,
  # Local adapter configuration
  gc_interval: :timer.seconds(30),
  max_size: 5_000,
  allocated_memory: 50_000_000, # 50MB
  gc_memory_check: true

# L2 Cache - Distributed cache across cluster nodes  
config :rubber_duck, RubberDuck.Nebulex.Cache.L2,
  # Replicated adapter configuration
  primary: [
    adapter: Nebulex.Adapters.Cachex,
    name: :l2_primary_cache,
    stats: true
  ]

# Multilevel Cache - Coordinator for L1 + L2
config :rubber_duck, RubberDuck.Nebulex.Cache,
  # Multilevel adapter configuration
  levels: [
    # L1 - Local cache (checked first)
    {
      RubberDuck.Nebulex.Cache.L1,
      gc_interval: :timer.seconds(30),
      max_size: 5_000,
      allocated_memory: 50_000_000
    },
    # L2 - Distributed cache (checked second)
    {
      RubberDuck.Nebulex.Cache.L2,
      primary: [
        adapter: Nebulex.Adapters.Cachex,
        name: :l2_cache,
        stats: true,
        limit: 10_000
      ]
    }
  ],
  # Cache inclusion policy - put in both L1 and L2
  inclusion_policy: :inclusive,
  # TTL for multilevel operations
  ttl_check_interval: :timer.seconds(60)
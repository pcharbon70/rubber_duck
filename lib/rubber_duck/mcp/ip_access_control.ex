defmodule RubberDuck.MCP.IPAccessControl do
  @moduledoc """
  IP-based access control for MCP protocol.
  
  Provides IP whitelisting, blacklisting, and temporary blocking
  for security purposes. Supports:
  
  - IP address and CIDR block rules
  - Temporary blocks for suspicious activity
  - Geo-location based restrictions
  - Dynamic rule updates
  
  ## Features
  
  - Whitelist/blacklist management
  - Automatic expiry of temporary blocks
  - IP reputation tracking
  - Integration with security events
  """
  
  use GenServer
  import Bitwise
  
  require Logger
  
  @type ip_address :: String.t()
  @type rule_type :: :whitelist | :blacklist | :temporary_block
  @type rule :: %{
    type: rule_type(),
    ip_pattern: String.t(),
    reason: String.t() | nil,
    expires_at: DateTime.t() | nil,
    created_by: String.t(),
    metadata: map()
  }
  
  @type access_decision :: :allow | {:deny, reason :: String.t()}
  
  # Default configuration
  @default_config %{
    allow_by_default: true,
    enable_geo_blocking: false,
    blocked_countries: [],
    max_failures_before_block: 5,
    block_duration_seconds: 300,
    cleanup_interval: 60_000  # 1 minute
  }
  
  # Client API
  
  @doc """
  Starts the IP access control service.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Checks if an IP address is allowed access.
  """
  @spec check_access(ip_address()) :: access_decision()
  def check_access(ip_address) do
    GenServer.call(__MODULE__, {:check_access, ip_address})
  end
  
  @doc """
  Adds an IP to the whitelist.
  """
  @spec add_whitelist(ip_address() | String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def add_whitelist(ip_pattern, created_by, opts \\ []) do
    GenServer.call(__MODULE__, {:add_rule, :whitelist, ip_pattern, created_by, opts})
  end
  
  @doc """
  Adds an IP to the blacklist.
  """
  @spec add_blacklist(ip_address() | String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def add_blacklist(ip_pattern, created_by, opts \\ []) do
    GenServer.call(__MODULE__, {:add_rule, :blacklist, ip_pattern, created_by, opts})
  end
  
  @doc """
  Temporarily blocks an IP address.
  """
  @spec temporary_block(ip_address(), pos_integer(), keyword()) :: :ok
  def temporary_block(ip_address, duration_seconds \\ 300, opts \\ []) do
    GenServer.call(__MODULE__, {:temporary_block, ip_address, duration_seconds, opts})
  end
  
  @doc """
  Reports a failure from an IP address.
  
  After a threshold of failures, the IP will be automatically blocked.
  """
  @spec report_failure(ip_address(), String.t()) :: :ok
  def report_failure(ip_address, reason) do
    GenServer.cast(__MODULE__, {:report_failure, ip_address, reason})
  end
  
  @doc """
  Removes a rule by IP pattern.
  """
  @spec remove_rule(ip_address() | String.t()) :: :ok | {:error, :not_found}
  def remove_rule(ip_pattern) do
    GenServer.call(__MODULE__, {:remove_rule, ip_pattern})
  end
  
  @doc """
  Lists all active rules.
  """
  @spec list_rules() :: [rule()]
  def list_rules do
    GenServer.call(__MODULE__, :list_rules)
  end
  
  @doc """
  Gets current statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Updates configuration.
  """
  @spec update_config(map()) :: :ok
  def update_config(config) do
    GenServer.call(__MODULE__, {:update_config, config})
  end
  
  # Server implementation
  
  @impl GenServer
  def init(opts) do
    # Create ETS tables
    :ets.new(:mcp_ip_rules, [:set, :public, :named_table])
    :ets.new(:mcp_ip_failures, [:set, :public, :named_table])
    :ets.new(:mcp_ip_cache, [:set, :public, :named_table])
    
    # Load configuration
    config = load_config(opts)
    
    # Schedule cleanup
    schedule_cleanup(config.cleanup_interval)
    
    # Initialize with any pre-configured rules
    init_default_rules(opts)
    
    state = %{
      config: config,
      stats: %{
        checks_allowed: 0,
        checks_denied: 0,
        rules_added: 0,
        auto_blocks: 0
      }
    }
    
    Logger.info("MCP IP Access Control started")
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:check_access, ip_address}, _from, state) do
    decision = perform_access_check(ip_address, state)
    
    # Update stats
    new_state = case decision do
      :allow -> 
        update_in(state.stats.checks_allowed, &(&1 + 1))
      {:deny, _} -> 
        update_in(state.stats.checks_denied, &(&1 + 1))
    end
    
    # Cache the decision
    cache_decision(ip_address, decision)
    
    {:reply, decision, new_state}
  end
  
  @impl GenServer
  def handle_call({:add_rule, type, ip_pattern, created_by, opts}, _from, state) do
    case validate_ip_pattern(ip_pattern) do
      :ok ->
        rule = build_rule(type, ip_pattern, created_by, opts)
        :ets.insert(:mcp_ip_rules, {ip_pattern, rule})
        
        # Clear cache for affected IPs
        clear_cache_for_pattern(ip_pattern)
        
        new_state = update_in(state.stats.rules_added, &(&1 + 1))
        
        Logger.info("Added #{type} rule for #{ip_pattern} by #{created_by}")
        {:reply, :ok, new_state}
        
      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end
  
  @impl GenServer
  def handle_call({:temporary_block, ip_address, duration_seconds, opts}, _from, state) do
    expires_at = DateTime.add(DateTime.utc_now(), duration_seconds, :second)
    reason = Keyword.get(opts, :reason, "Temporary security block")
    
    rule = %{
      type: :temporary_block,
      ip_pattern: ip_address,
      reason: reason,
      expires_at: expires_at,
      created_by: "system",
      metadata: %{
        block_duration: duration_seconds,
        triggered_at: DateTime.utc_now()
      }
    }
    
    :ets.insert(:mcp_ip_rules, {ip_address, rule})
    clear_cache_for_pattern(ip_address)
    
    new_state = update_in(state.stats.auto_blocks, &(&1 + 1))
    
    Logger.warning("Temporarily blocked #{ip_address} for #{duration_seconds}s: #{reason}")
    {:reply, :ok, new_state}
  end
  
  @impl GenServer
  def handle_call({:remove_rule, ip_pattern}, _from, state) do
    case :ets.lookup(:mcp_ip_rules, ip_pattern) do
      [{^ip_pattern, _rule}] ->
        :ets.delete(:mcp_ip_rules, ip_pattern)
        clear_cache_for_pattern(ip_pattern)
        
        Logger.info("Removed rule for #{ip_pattern}")
        {:reply, :ok, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:list_rules, _from, state) do
    rules = :ets.tab2list(:mcp_ip_rules)
    |> Enum.map(fn {_pattern, rule} -> rule end)
    |> Enum.sort_by(& &1.ip_pattern)
    
    {:reply, rules, state}
  end
  
  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      active_rules: :ets.info(:mcp_ip_rules, :size),
      tracked_failures: :ets.info(:mcp_ip_failures, :size),
      cache_size: :ets.info(:mcp_ip_cache, :size)
    })
    
    {:reply, stats, state}
  end
  
  @impl GenServer
  def handle_call({:update_config, config}, _from, state) do
    new_config = Map.merge(state.config, config)
    {:reply, :ok, %{state | config: new_config}}
  end
  
  @impl GenServer
  def handle_cast({:report_failure, ip_address, reason}, state) do
    # Track failures
    failures = case :ets.lookup(:mcp_ip_failures, ip_address) do
      [{^ip_address, count, _reasons}] ->
        count + 1
      [] ->
        1
    end
    
    :ets.insert(:mcp_ip_failures, {ip_address, failures, [reason]})
    
    # Check if we should auto-block
    if failures >= state.config.max_failures_before_block do
      temporary_block(ip_address, state.config.block_duration_seconds, 
        reason: "Exceeded failure threshold (#{failures} failures)")
      
      # Reset failure count
      :ets.delete(:mcp_ip_failures, ip_address)
    end
    
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info(:cleanup, state) do
    # Remove expired temporary blocks
    now = DateTime.utc_now()
    
    expired = :ets.select(:mcp_ip_rules, [
      {
        {:_, %{type: :temporary_block, expires_at: :"$1"}},
        [{:"<", :"$1", now}],
        [:"$_"]
      }
    ])
    
    Enum.each(expired, fn {pattern, _rule} ->
      :ets.delete(:mcp_ip_rules, pattern)
      clear_cache_for_pattern(pattern)
      Logger.info("Removed expired block for #{pattern}")
    end)
    
    # Clear old cache entries
    cache_cutoff = System.monotonic_time(:second) - 300  # 5 minutes
    :ets.select_delete(:mcp_ip_cache, [
      {
        {:_, {:_, :"$1"}},
        [{:"<", :"$1", cache_cutoff}],
        [true]
      }
    ])
    
    # Schedule next cleanup
    schedule_cleanup(state.config.cleanup_interval)
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp load_config(opts) do
    config = Keyword.get(opts, :config, %{})
    Map.merge(@default_config, config)
  end
  
  defp init_default_rules(opts) do
    # Add any pre-configured whitelist entries
    Enum.each(Keyword.get(opts, :whitelist, []), fn ip ->
      add_whitelist(ip, "system", reason: "Pre-configured")
    end)
    
    # Add any pre-configured blacklist entries
    Enum.each(Keyword.get(opts, :blacklist, []), fn ip ->
      add_blacklist(ip, "system", reason: "Pre-configured")
    end)
  end
  
  defp perform_access_check(ip_address, state) do
    # Check cache first
    case get_cached_decision(ip_address) do
      {:ok, decision} ->
        decision
        
      :miss ->
        # Check rules in order: whitelist, blacklist, temporary blocks
        cond do
          match_rule?(ip_address, :whitelist) ->
            :allow
            
          match_rule?(ip_address, :blacklist) ->
            {:deny, "IP blacklisted"}
            
          match_rule?(ip_address, :temporary_block) ->
            {:deny, "IP temporarily blocked"}
            
          true ->
            # Check geo-blocking if enabled
            geo_decision = if state.config.enable_geo_blocking do
              if geo_blocked?(ip_address, state) do
                {:deny, "Geographic location blocked"}
              else
                nil
              end
            else
              nil
            end
            
            # Return geo decision or default decision
            geo_decision || default_decision(state)
        end
    end
  end
  
  defp match_rule?(ip_address, rule_type) do
    :ets.tab2list(:mcp_ip_rules)
    |> Enum.filter(fn {_pattern, rule} -> rule.type == rule_type end)
    |> Enum.any?(fn {pattern, _rule} -> ip_matches_pattern?(ip_address, pattern) end)
  end
  
  defp ip_matches_pattern?(ip_address, pattern) do
    cond do
      ip_address == pattern ->
        true
        
      String.contains?(pattern, "/") ->
        # CIDR block matching
        match_cidr?(ip_address, pattern)
        
      String.contains?(pattern, "*") ->
        # Wildcard matching
        pattern_regex = pattern
        |> String.replace(".", "\\.")
        |> String.replace("*", ".*")
        |> Regex.compile!()
        
        Regex.match?(pattern_regex, ip_address)
        
      true ->
        false
    end
  end
  
  defp match_cidr?(ip_address, cidr) do
    # Simple CIDR matching implementation
    # In production, use a proper IP address library
    try do
      [network, bits] = String.split(cidr, "/")
      mask_bits = String.to_integer(bits)
      
      ip_int = ip_to_integer(ip_address)
      network_int = ip_to_integer(network)
      
      mask = -1 <<< (32 - mask_bits)
      
      (ip_int &&& mask) == (network_int &&& mask)
    rescue
      _ -> false
    end
  end
  
  defp ip_to_integer(ip) do
    ip
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> Enum.reduce(0, fn octet, acc -> (acc <<< 8) + octet end)
  end
  
  defp geo_blocked?(_ip_address, _state) do
    # Placeholder for geo-blocking logic
    # Would integrate with a geo-IP service
    false
  end
  
  defp default_decision(state) do
    if state.config.allow_by_default do
      :allow
    else
      {:deny, "No whitelist entry found"}
    end
  end
  
  defp validate_ip_pattern(pattern) do
    cond do
      # Basic IP address
      Regex.match?(~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/, pattern) ->
        :ok
        
      # CIDR notation
      Regex.match?(~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}$/, pattern) ->
        :ok
        
      # Wildcard pattern
      Regex.match?(~r/^[\d\.\*]+$/, pattern) ->
        :ok
        
      true ->
        {:error, "Invalid IP pattern"}
    end
  end
  
  defp build_rule(type, ip_pattern, created_by, opts) do
    %{
      type: type,
      ip_pattern: ip_pattern,
      reason: Keyword.get(opts, :reason),
      expires_at: Keyword.get(opts, :expires_at),
      created_by: created_by,
      metadata: %{
        created_at: DateTime.utc_now(),
        notes: Keyword.get(opts, :notes)
      }
    }
  end
  
  defp cache_decision(ip_address, decision) do
    timestamp = System.monotonic_time(:second)
    :ets.insert(:mcp_ip_cache, {ip_address, {decision, timestamp}})
  end
  
  defp get_cached_decision(ip_address) do
    case :ets.lookup(:mcp_ip_cache, ip_address) do
      [{^ip_address, {decision, timestamp}}] ->
        # Cache valid for 5 minutes
        if System.monotonic_time(:second) - timestamp < 300 do
          {:ok, decision}
        else
          :ets.delete(:mcp_ip_cache, ip_address)
          :miss
        end
        
      [] ->
        :miss
    end
  end
  
  defp clear_cache_for_pattern(pattern) do
    # Clear exact matches
    :ets.delete(:mcp_ip_cache, pattern)
    
    # Clear related entries if it's a CIDR or wildcard
    if String.contains?(pattern, "/") or String.contains?(pattern, "*") do
      cached_ips = :ets.select(:mcp_ip_cache, [
        {{:"$1", :_}, [], [:"$1"]}
      ])
      
      Enum.each(cached_ips, fn ip ->
        if ip_matches_pattern?(ip, pattern) do
          :ets.delete(:mcp_ip_cache, ip)
        end
      end)
    end
  end
  
  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end
end
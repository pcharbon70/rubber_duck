defmodule RubberDuck.MCP.IPAccessControlTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.IPAccessControl

  setup do
    # Start a fresh IP access control for each test
    {:ok, pid} = IPAccessControl.start_link(name: nil)

    %{ip_control: pid}
  end

  describe "check_access/1" do
    test "allows access by default when configured", %{ip_control: pid} do
      # Default config allows by default
      assert :allow = GenServer.call(pid, {:check_access, "192.168.1.100"})
      assert :allow = GenServer.call(pid, {:check_access, "10.0.0.1"})
    end

    test "denies access when allow_by_default is false", %{ip_control: pid} do
      config = %{allow_by_default: false}
      GenServer.call(pid, {:update_config, config})

      assert {:deny, "No whitelist entry found"} =
               GenServer.call(pid, {:check_access, "192.168.1.100"})
    end
  end

  describe "whitelist management" do
    test "adds and enforces whitelist entries", %{ip_control: pid} do
      # Configure to deny by default
      GenServer.call(pid, {:update_config, %{allow_by_default: false}})

      # Add whitelist entry
      assert :ok =
               GenServer.call(
                 pid,
                 {:add_rule, :whitelist, "192.168.1.100", "admin", []}
               )

      # Whitelisted IP should be allowed
      assert :allow = GenServer.call(pid, {:check_access, "192.168.1.100"})

      # Non-whitelisted should be denied
      assert {:deny, _} = GenServer.call(pid, {:check_access, "192.168.1.101"})
    end

    test "supports CIDR notation in whitelist", %{ip_control: pid} do
      GenServer.call(pid, {:update_config, %{allow_by_default: false}})

      # Add CIDR block
      assert :ok =
               GenServer.call(
                 pid,
                 {:add_rule, :whitelist, "192.168.1.0/24", "admin", []}
               )

      # IPs in range should be allowed
      assert :allow = GenServer.call(pid, {:check_access, "192.168.1.1"})
      assert :allow = GenServer.call(pid, {:check_access, "192.168.1.100"})
      assert :allow = GenServer.call(pid, {:check_access, "192.168.1.255"})

      # IPs outside range should be denied
      assert {:deny, _} = GenServer.call(pid, {:check_access, "192.168.2.1"})
    end

    test "supports wildcard patterns", %{ip_control: pid} do
      GenServer.call(pid, {:update_config, %{allow_by_default: false}})

      # Add wildcard pattern
      assert :ok =
               GenServer.call(
                 pid,
                 {:add_rule, :whitelist, "10.0.*.*", "admin", []}
               )

      # Matching IPs should be allowed
      assert :allow = GenServer.call(pid, {:check_access, "10.0.1.1"})
      assert :allow = GenServer.call(pid, {:check_access, "10.0.255.255"})

      # Non-matching should be denied
      assert {:deny, _} = GenServer.call(pid, {:check_access, "10.1.0.1"})
    end
  end

  describe "blacklist management" do
    test "blacklist takes precedence over whitelist", %{ip_control: pid} do
      # Add to both lists
      assert :ok =
               GenServer.call(
                 pid,
                 {:add_rule, :whitelist, "192.168.1.100", "admin", []}
               )

      assert :ok =
               GenServer.call(
                 pid,
                 {:add_rule, :blacklist, "192.168.1.100", "admin", reason: "Suspicious activity"}
               )

      # Should be denied due to blacklist
      assert {:deny, "IP blacklisted"} =
               GenServer.call(pid, {:check_access, "192.168.1.100"})
    end

    test "blacklist patterns work correctly", %{ip_control: pid} do
      # Blacklist a subnet
      assert :ok =
               GenServer.call(
                 pid,
                 {:add_rule, :blacklist, "10.10.10.0/24", "system", []}
               )

      assert {:deny, "IP blacklisted"} =
               GenServer.call(pid, {:check_access, "10.10.10.50"})

      # Other IPs should still be allowed
      assert :allow = GenServer.call(pid, {:check_access, "10.10.11.50"})
    end
  end

  describe "temporary_block/3" do
    test "temporarily blocks an IP address", %{ip_control: pid} do
      # Block for 1 second
      assert :ok =
               GenServer.call(
                 pid,
                 {:temporary_block, "192.168.1.100", 1, reason: "Test block"}
               )

      # Should be blocked
      assert {:deny, "IP temporarily blocked"} =
               GenServer.call(pid, {:check_access, "192.168.1.100"})

      # Wait for expiry
      Process.sleep(1100)

      # Trigger cleanup
      send(pid, :cleanup)
      Process.sleep(100)

      # Should be allowed again
      assert :allow = GenServer.call(pid, {:check_access, "192.168.1.100"})
    end

    test "temporary blocks are tracked separately from permanent rules", %{ip_control: pid} do
      # Add permanent whitelist
      assert :ok =
               GenServer.call(
                 pid,
                 {:add_rule, :whitelist, "192.168.1.0/24", "admin", []}
               )

      # Temporarily block specific IP
      assert :ok =
               GenServer.call(
                 pid,
                 {:temporary_block, "192.168.1.100", 1, []}
               )

      # Blocked IP should be denied
      assert {:deny, _} = GenServer.call(pid, {:check_access, "192.168.1.100"})

      # Other IPs in range should still work
      assert :allow = GenServer.call(pid, {:check_access, "192.168.1.101"})
    end
  end

  describe "report_failure/2" do
    test "automatically blocks after threshold failures", %{ip_control: pid} do
      # Report failures
      for i <- 1..4 do
        GenServer.cast(pid, {:report_failure, "192.168.1.100", "Attempt #{i}"})
      end

      # Still allowed (threshold is 5)
      assert :allow = GenServer.call(pid, {:check_access, "192.168.1.100"})

      # One more failure triggers auto-block
      GenServer.cast(pid, {:report_failure, "192.168.1.100", "Final attempt"})
      # Let cast process
      Process.sleep(50)

      # Should now be blocked
      assert {:deny, "IP temporarily blocked"} =
               GenServer.call(pid, {:check_access, "192.168.1.100"})
    end
  end

  describe "remove_rule/1" do
    test "removes rules by pattern", %{ip_control: pid} do
      # Add and verify rule
      assert :ok =
               GenServer.call(
                 pid,
                 {:add_rule, :blacklist, "192.168.1.100", "admin", []}
               )

      assert {:deny, _} = GenServer.call(pid, {:check_access, "192.168.1.100"})

      # Remove rule
      assert :ok = GenServer.call(pid, {:remove_rule, "192.168.1.100"})

      # Should be allowed again
      assert :allow = GenServer.call(pid, {:check_access, "192.168.1.100"})
    end

    test "returns error for non-existent rules", %{ip_control: pid} do
      assert {:error, :not_found} =
               GenServer.call(pid, {:remove_rule, "192.168.1.100"})
    end
  end

  describe "list_rules/0" do
    test "returns all active rules", %{ip_control: pid} do
      # Add various rules
      GenServer.call(pid, {:add_rule, :whitelist, "10.0.0.0/8", "admin", []})
      GenServer.call(pid, {:add_rule, :blacklist, "10.1.1.1", "system", reason: "Bad actor"})
      GenServer.call(pid, {:temporary_block, "192.168.1.1", 300, []})

      rules = GenServer.call(pid, :list_rules)

      assert length(rules) == 3
      assert Enum.any?(rules, &(&1.type == :whitelist))
      assert Enum.any?(rules, &(&1.type == :blacklist))
      assert Enum.any?(rules, &(&1.type == :temporary_block))
    end
  end

  describe "caching" do
    test "caches access decisions for performance", %{ip_control: pid} do
      # First check should miss cache
      assert :allow = GenServer.call(pid, {:check_access, "192.168.1.100"})

      # Add a blacklist rule
      GenServer.call(
        pid,
        {:add_rule, :blacklist, "192.168.0.0/16", "admin", []}
      )

      # Should still return cached allow (cache not cleared)
      assert :allow = GenServer.call(pid, {:check_access, "192.168.1.100"})

      # Different IP should see the new rule
      assert {:deny, _} = GenServer.call(pid, {:check_access, "192.168.1.101"})
    end
  end

  describe "IP pattern validation" do
    test "validates IP patterns on rule creation", %{ip_control: pid} do
      # Valid patterns
      assert :ok =
               GenServer.call(
                 pid,
                 {:add_rule, :whitelist, "192.168.1.1", "admin", []}
               )

      assert :ok =
               GenServer.call(
                 pid,
                 {:add_rule, :whitelist, "10.0.0.0/8", "admin", []}
               )

      assert :ok =
               GenServer.call(
                 pid,
                 {:add_rule, :whitelist, "192.168.*.*", "admin", []}
               )

      # Invalid patterns
      assert {:error, "Invalid IP pattern"} =
               GenServer.call(pid, {:add_rule, :whitelist, "not-an-ip", "admin", []})

      assert {:error, "Invalid IP pattern"} =
               GenServer.call(pid, {:add_rule, :whitelist, "256.1.1.1", "admin", []})
    end
  end
end

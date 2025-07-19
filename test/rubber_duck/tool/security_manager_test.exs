defmodule RubberDuck.Tool.SecurityManagerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Tool.SecurityManager

  setup do
    # Start a fresh SecurityManager for each test
    start_supervised!({SecurityManager, []})
    :ok
  end

  describe "capability management" do
    test "can declare valid capabilities" do
      assert :ok = SecurityManager.declare_capabilities(TestTool, [:file_read, :network_access])
    end

    test "rejects invalid capabilities" do
      assert {:error, {:invalid_capabilities, [:invalid_cap]}} =
               SecurityManager.declare_capabilities(TestTool, [:invalid_cap])
    end

    test "lists all available capabilities" do
      capabilities = SecurityManager.list_capabilities()
      assert is_list(capabilities)
      assert :file_read in capabilities
      assert :network_access in capabilities
    end
  end

  describe "access control" do
    test "allows access when capabilities match" do
      # Declare tool capabilities
      SecurityManager.declare_capabilities(TestTool, [:file_read])

      # Set permissive user policy
      policy = %{
        capabilities: [:file_read, :file_write],
        restrictions: %{},
        metadata: %{name: "test_policy"}
      }

      SecurityManager.set_policy("user123", policy)

      # Check access
      user_context = %{user_id: "user123"}
      assert :ok = SecurityManager.check_access(TestTool, user_context)
    end

    test "denies access when capabilities don't match" do
      # Declare tool capabilities
      SecurityManager.declare_capabilities(TestTool, [:file_write])

      # Set restrictive user policy
      policy = %{
        capabilities: [:file_read],
        restrictions: %{},
        metadata: %{name: "restricted_policy"}
      }

      SecurityManager.set_policy("user123", policy)

      # Check access
      user_context = %{user_id: "user123"}
      assert {:error, {:access_denied, _}} = SecurityManager.check_access(TestTool, user_context)
    end

    test "applies file path restrictions" do
      # Declare tool capabilities
      SecurityManager.declare_capabilities(TestTool, [:file_read])

      # Set policy with file restrictions
      policy = %{
        capabilities: [:file_read],
        restrictions: %{file_paths: ["/tmp/"]},
        metadata: %{name: "file_restricted"}
      }

      SecurityManager.set_policy("user123", policy)

      user_context = %{user_id: "user123"}

      # Should allow access to restricted path
      assert :ok = SecurityManager.check_access(TestTool, user_context, %{file_path: "/tmp/test.txt"})

      # Should deny access to unrestricted path
      assert {:error, {:access_denied, _}} =
               SecurityManager.check_access(TestTool, user_context, %{file_path: "/etc/passwd"})
    end

    test "falls back to default policy for unknown users" do
      # Declare tool capabilities that exceed default policy
      SecurityManager.declare_capabilities(TestTool, [:network_access])

      user_context = %{user_id: "unknown_user"}

      # Should be denied due to default restrictive policy
      assert {:error, {:access_denied, _}} = SecurityManager.check_access(TestTool, user_context)
    end
  end

  describe "policy management" do
    test "can set and get policies" do
      policy = %{
        capabilities: [:file_read, :system_info],
        restrictions: %{max_execution_time: 60_000},
        metadata: %{name: "custom_policy"}
      }

      assert :ok = SecurityManager.set_policy("user123", policy)
      assert {:ok, ^policy} = SecurityManager.get_policy("user123")
    end

    test "validates policy structure" do
      invalid_policy = %{
        capabilities: "not_a_list",
        restrictions: %{}
      }

      assert {:error, _} = SecurityManager.set_policy("user123", invalid_policy)
    end

    test "validates capability names in policy" do
      invalid_policy = %{
        capabilities: [:file_read, :invalid_capability],
        restrictions: %{},
        metadata: %{}
      }

      assert {:error, _} = SecurityManager.set_policy("user123", invalid_policy)
    end
  end

  describe "audit logging" do
    test "logs capability declarations" do
      SecurityManager.declare_capabilities(TestTool, [:file_read])

      {:ok, logs} = SecurityManager.get_audit_log(%{action: :capability_declaration})

      assert length(logs) > 0
      log = hd(logs)
      assert log.action == :capability_declaration
      assert log.tool == TestTool
    end

    test "logs access checks" do
      SecurityManager.declare_capabilities(TestTool, [:file_read])

      user_context = %{user_id: "user123"}
      SecurityManager.check_access(TestTool, user_context)

      {:ok, logs} = SecurityManager.get_audit_log(%{action: :access_check})

      assert length(logs) > 0
      log = hd(logs)
      assert log.action == :access_check
      assert log.user == "user123"
      assert log.tool == TestTool
    end

    test "filters audit logs by user" do
      user1_context = %{user_id: "user1"}
      user2_context = %{user_id: "user2"}

      SecurityManager.declare_capabilities(TestTool, [:file_read])
      SecurityManager.check_access(TestTool, user1_context)
      SecurityManager.check_access(TestTool, user2_context)

      {:ok, user1_logs} = SecurityManager.get_audit_log(%{user: "user1"})
      {:ok, user2_logs} = SecurityManager.get_audit_log(%{user: "user2"})

      assert length(user1_logs) > 0
      assert length(user2_logs) > 0
      assert Enum.all?(user1_logs, &(&1.user == "user1"))
      assert Enum.all?(user2_logs, &(&1.user == "user2"))
    end

    test "clears old audit logs" do
      SecurityManager.declare_capabilities(TestTool, [:file_read])

      # Should clear 0 logs (they're recent)
      assert {:ok, 0} = SecurityManager.clear_old_audit_logs(24)

      # Should clear all logs (they're "old")
      assert {:ok, count} = SecurityManager.clear_old_audit_logs(0)
      assert count > 0
    end
  end

  describe "group policies" do
    test "applies group policies when user has no specific policy" do
      # Declare tool capabilities
      SecurityManager.declare_capabilities(TestTool, [:network_access])

      # Set group policy
      group_policy = %{
        capabilities: [:network_access],
        restrictions: %{},
        metadata: %{name: "group_policy"}
      }

      SecurityManager.set_policy("admins", group_policy)

      # User with group membership
      user_context = %{user_id: "user123", groups: ["admins"]}

      # Should allow access via group policy
      assert :ok = SecurityManager.check_access(TestTool, user_context)
    end

    test "user policy overrides group policy" do
      # Declare tool capabilities
      SecurityManager.declare_capabilities(TestTool, [:network_access])

      # Set permissive group policy
      group_policy = %{
        capabilities: [:network_access],
        restrictions: %{},
        metadata: %{name: "group_policy"}
      }

      SecurityManager.set_policy("admins", group_policy)

      # Set restrictive user policy
      user_policy = %{
        capabilities: [:file_read],
        restrictions: %{},
        metadata: %{name: "user_policy"}
      }

      SecurityManager.set_policy("user123", user_policy)

      # User with group membership
      user_context = %{user_id: "user123", groups: ["admins"]}

      # Should deny access due to user policy override
      assert {:error, {:access_denied, _}} = SecurityManager.check_access(TestTool, user_context)
    end
  end

  describe "macro usage" do
    defmodule TestSecureTool do
      use RubberDuck.Tool.SecurityManager, capabilities: [:file_read, :system_info]

      def test_function do
        "test result"
      end
    end

    test "macro automatically registers capabilities" do
      # Wait a bit for the @after_compile callback to run
      Process.sleep(100)

      # Check that capabilities were registered
      policy = %{
        capabilities: [:file_read, :system_info],
        restrictions: %{},
        metadata: %{name: "test_policy"}
      }

      SecurityManager.set_policy("user123", policy)

      user_context = %{user_id: "user123"}
      assert :ok = SecurityManager.check_access(TestSecureTool, user_context)
    end
  end
end

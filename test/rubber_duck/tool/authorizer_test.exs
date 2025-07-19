defmodule RubberDuck.Tool.AuthorizerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Tool.Authorizer

  # Test user contexts
  @admin_user %{
    id: "admin-123",
    roles: [:admin],
    permissions: [:all]
  }

  @regular_user %{
    id: "user-456",
    roles: [:user],
    permissions: [:read, :execute]
  }

  @restricted_user %{
    id: "restricted-789",
    roles: [:restricted],
    permissions: [:read]
  }

  @guest_user %{
    id: "guest-000",
    roles: [:guest],
    permissions: []
  }

  defmodule PublicTool do
    use RubberDuck.Tool

    tool do
      name :public_tool
      description "A public tool available to all users"
      category(:public)

      parameter :input do
        type :string
        required(true)
      end

      execution do
        handler(&PublicTool.execute/2)
      end

      security do
        sandbox(:none)
        capabilities([])
      end
    end

    def execute(_params, _context) do
      {:ok, "public result"}
    end
  end

  defmodule AdminTool do
    use RubberDuck.Tool

    tool do
      name :admin_tool
      description "An admin-only tool"
      category(:admin)

      parameter :action do
        type :string
        required(true)
      end

      execution do
        handler(&AdminTool.execute/2)
      end

      security do
        sandbox(:strict)
        capabilities([:admin_access, :system_modify])
      end
    end

    def execute(_params, _context) do
      {:ok, "admin result"}
    end
  end

  defmodule FileSystemTool do
    use RubberDuck.Tool

    tool do
      name :filesystem_tool
      description "A tool that requires file system access"
      category(:utility)

      parameter :path do
        type :string
        required(true)
      end

      execution do
        handler(&FileSystemTool.execute/2)
      end

      security do
        sandbox(:strict)
        capabilities([:file_read, :file_write])
      end
    end

    def execute(_params, _context) do
      {:ok, "filesystem result"}
    end
  end

  describe "capability-based authorization" do
    test "allows access when user has required capability" do
      user = %{@regular_user | permissions: [:read, :execute, :file_read]}

      assert {:ok, :authorized} = Authorizer.authorize(FileSystemTool, user, %{action: :read})
    end

    test "denies access when user lacks required capability" do
      user = @regular_user

      assert {:error, :insufficient_capabilities} = Authorizer.authorize(FileSystemTool, user, %{action: :read})
    end

    test "allows admin access to all tools" do
      assert {:ok, :authorized} = Authorizer.authorize(AdminTool, @admin_user, %{action: :execute})
      assert {:ok, :authorized} = Authorizer.authorize(FileSystemTool, @admin_user, %{action: :read})
      assert {:ok, :authorized} = Authorizer.authorize(PublicTool, @admin_user, %{action: :execute})
    end

    test "allows access to tools with no required capabilities" do
      assert {:ok, :authorized} = Authorizer.authorize(PublicTool, @regular_user, %{action: :execute})
      assert {:ok, :authorized} = Authorizer.authorize(PublicTool, @restricted_user, %{action: :execute})
      assert {:ok, :authorized} = Authorizer.authorize(PublicTool, @guest_user, %{action: :execute})
    end
  end

  describe "role-based authorization" do
    test "allows access based on user roles" do
      # Admin can access admin tools
      assert {:ok, :authorized} = Authorizer.authorize(AdminTool, @admin_user, %{action: :execute})

      # Regular user cannot access admin tools
      assert {:error, :insufficient_role} = Authorizer.authorize(AdminTool, @regular_user, %{action: :execute})
    end

    test "checks custom role requirements" do
      # Define a custom authorization check
      defmodule CustomRoleTool do
        use RubberDuck.Tool

        tool do
          name :custom_role_tool
          description "Tool with custom role requirements"

          execution do
            handler(&CustomRoleTool.execute/2)
          end

          security do
            capabilities([:custom_access])
          end
        end

        def execute(_params, _context) do
          {:ok, "custom result"}
        end
      end

      # User with custom access should be authorized
      user = %{@regular_user | permissions: [:custom_access]}
      assert {:ok, :authorized} = Authorizer.authorize(CustomRoleTool, user, %{action: :execute})
    end
  end

  describe "context-based authorization" do
    test "considers execution context in authorization" do
      # Different contexts may have different authorization rules
      read_context = %{action: :read, resource: "config"}
      write_context = %{action: :write, resource: "config"}

      user = %{@regular_user | permissions: [:read, :file_read]}

      # Read access should be allowed
      assert {:ok, :authorized} = Authorizer.authorize(FileSystemTool, user, read_context)

      # Write access should be denied (no file_write permission)
      assert {:error, :insufficient_capabilities} = Authorizer.authorize(FileSystemTool, user, write_context)
    end

    test "validates resource access permissions" do
      # Test resource-specific permissions
      context = %{action: :read, resource: "sensitive_data"}

      user = %{@regular_user | permissions: [:read, :file_read]}

      # Should check for resource-specific permissions
      assert {:ok, :authorized} = Authorizer.authorize(FileSystemTool, user, context)
    end
  end

  describe "audit logging" do
    test "logs successful authorization" do
      user = @admin_user
      context = %{action: :execute}

      # Capture log output
      import ExUnit.CaptureLog

      log =
        capture_log([level: :info], fn ->
          assert {:ok, :authorized} = Authorizer.authorize(AdminTool, user, context)
        end)

      # Check that authorization was logged
      assert log =~ "Tool authorization granted"
      assert log =~ "admin_tool"
      assert log =~ "admin-123"
    end

    test "logs failed authorization" do
      user = @restricted_user
      context = %{action: :execute}

      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          assert {:error, :insufficient_role} = Authorizer.authorize(AdminTool, user, context)
        end)

      # Check that authorization failure was logged
      assert log =~ "Tool authorization denied"
      assert log =~ "admin_tool"
      assert log =~ "restricted-789"
      assert log =~ "insufficient_role"
    end
  end

  describe "authorization policies" do
    test "applies custom authorization policies" do
      # Define a custom policy
      defmodule CustomPolicy do
        def authorize(_tool, user, _context) do
          if user.id == "special-user" do
            {:ok, :authorized}
          else
            {:error, :custom_denial}
          end
        end
      end

      # Test with custom policy
      special_user = %{@regular_user | id: "special-user"}

      assert {:ok, :authorized} = Authorizer.authorize(PublicTool, special_user, %{}, CustomPolicy)
      assert {:error, :custom_denial} = Authorizer.authorize(PublicTool, @regular_user, %{}, CustomPolicy)
    end

    test "combines multiple authorization checks" do
      # Test that both capability and role checks are applied
      user = %{@regular_user | permissions: [:admin_access, :system_modify]}

      # Should still fail due to insufficient role
      assert {:error, :insufficient_role} = Authorizer.authorize(AdminTool, user, %{action: :execute})
    end
  end

  describe "rate limiting integration" do
    test "checks rate limits before authorization" do
      # This would integrate with the existing rate limiting system
      user = @regular_user
      context = %{action: :execute, rate_limit_key: "user:#{user.id}"}

      # Should check rate limits as part of authorization
      assert {:ok, :authorized} = Authorizer.authorize(PublicTool, user, context)
    end
  end

  describe "time-based authorization" do
    test "supports time-based access control" do
      # Test time-based restrictions
      defmodule TimeRestrictedTool do
        use RubberDuck.Tool

        tool do
          name :time_restricted_tool
          description "Tool with time-based restrictions"

          execution do
            handler(&TimeRestrictedTool.execute/2)
          end

          security do
            capabilities([:time_restricted])
          end
        end

        def execute(_params, _context) do
          {:ok, "time restricted result"}
        end
      end

      user = %{@regular_user | permissions: [:time_restricted]}

      # During allowed hours
      allowed_context = %{action: :execute, time: ~T[10:00:00]}
      assert {:ok, :authorized} = Authorizer.authorize(TimeRestrictedTool, user, allowed_context)

      # During restricted hours (would need custom policy implementation)
      restricted_context = %{action: :execute, time: ~T[02:00:00]}
      # This would require custom policy implementation
    end
  end

  describe "authorization caching" do
    test "caches authorization decisions" do
      user = @admin_user
      context = %{action: :execute}

      # First authorization call
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, :authorized} = Authorizer.authorize(AdminTool, user, context)
      first_time = System.monotonic_time(:millisecond) - start_time

      # Second authorization call (should be cached)
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, :authorized} = Authorizer.authorize(AdminTool, user, context)
      second_time = System.monotonic_time(:millisecond) - start_time

      # Second call should be faster (cached)
      assert second_time < first_time
    end
  end

  describe "error handling" do
    test "handles invalid tool modules gracefully" do
      assert {:error, :invalid_tool} = Authorizer.authorize(NonExistentTool, @regular_user, %{})
    end

    test "handles malformed user contexts" do
      malformed_user = %{invalid: "user"}

      assert {:error, :invalid_user} = Authorizer.authorize(PublicTool, malformed_user, %{})
    end

    test "handles missing security configuration" do
      defmodule NoSecurityTool do
        use RubberDuck.Tool

        tool do
          name :no_security_tool
          description "Tool without security configuration"

          execution do
            handler(&NoSecurityTool.execute/2)
          end
        end

        def execute(_params, _context) do
          {:ok, "no security result"}
        end
      end

      # Should default to allowing access
      assert {:ok, :authorized} = Authorizer.authorize(NoSecurityTool, @regular_user, %{})
    end
  end
end

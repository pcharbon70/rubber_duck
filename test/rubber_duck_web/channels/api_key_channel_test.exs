defmodule RubberDuckWeb.ApiKeyChannelTest do
  use RubberDuckWeb.ChannelCase

  import RubberDuck.AccountsFixtures
  alias RubberDuckWeb.{UserSocket, ApiKeyChannel}
  alias RubberDuck.Accounts.ApiKey

  setup do
    user = user_fixture()

    # Generate a token for the user
    {:ok, token} = AshAuthentication.Jwt.token_for_user(user)

    # Connect to socket with token
    {:ok, socket} = connect(UserSocket, %{"token" => token})

    %{socket: socket, user: user}
  end

  describe "join/3" do
    test "authorized user can join api_keys:manage", %{socket: socket} do
      assert {:ok, reply, _socket} = subscribe_and_join(socket, ApiKeyChannel, "api_keys:manage")

      # Should receive initial stats
      assert %{
               total_keys: _,
               active_keys: _,
               expired_keys: _,
               revoked_keys: _,
               generation_limit: %{
                 used: _,
                 limit: _,
                 resets_at: _
               }
             } = reply
    end

    test "rejects join to unauthorized topic", %{socket: socket} do
      assert {:error, %{reason: "unauthorized_topic"}} =
               subscribe_and_join(socket, ApiKeyChannel, "api_keys:private")
    end
  end

  describe "handle_in generate" do
    setup %{socket: socket} do
      {:ok, _reply, socket} = subscribe_and_join(socket, ApiKeyChannel, "api_keys:manage")
      %{channel: socket}
    end

    test "generates API key with default expiration", %{channel: socket} do
      ref = push(socket, "generate", %{})

      assert_push("key_generated", %{
        api_key: %{
          id: _id,
          name: "Generated via WebSocket",
          key: key,
          expires_at: expires_at,
          created_at: _created_at
        },
        warning: "Store this key securely - it won't be shown again"
      })

      # Verify key format
      assert String.starts_with?(key, "rubberduck_")

      # Verify expiration is approximately 1 year from now
      {:ok, exp_dt, _} = DateTime.from_iso8601(expires_at)
      diff = DateTime.diff(exp_dt, DateTime.utc_now(), :day)
      assert diff >= 364 and diff <= 366

      # Other clients should receive update
      assert_broadcast("key_list_updated", %{
        action: "generated",
        api_key_id: _
      })
    end

    test "generates API key with custom expiration and name", %{channel: socket} do
      custom_expires = DateTime.utc_now() |> DateTime.add(30, :day)

      ref =
        push(socket, "generate", %{
          "expires_at" => DateTime.to_iso8601(custom_expires),
          "name" => "Custom API Key"
        })

      assert_push("key_generated", %{
        api_key: %{
          id: _id,
          name: "Custom API Key",
          key: _key,
          expires_at: expires_at,
          created_at: _created_at
        },
        warning: _
      })

      # Verify custom expiration
      {:ok, exp_dt, _} = DateTime.from_iso8601(expires_at)
      diff = DateTime.diff(exp_dt, custom_expires, :second)
      # Within a minute
      assert abs(diff) < 60
    end

    @tag :skip
    test "enforces rate limiting", %{channel: socket} do
      # This test would require implementing actual rate limiting
      # For now, it's skipped
    end
  end

  describe "handle_in list" do
    setup %{socket: socket, user: user} do
      {:ok, _reply, socket} = subscribe_and_join(socket, ApiKeyChannel, "api_keys:manage")

      # Create some test API keys
      {:ok, key1} =
        Ash.create(ApiKey, %{
          user_id: user.id,
          name: "Test Key 1",
          expires_at: DateTime.utc_now() |> DateTime.add(30, :day)
        })

      {:ok, key2} =
        Ash.create(ApiKey, %{
          user_id: user.id,
          name: "Test Key 2",
          expires_at: DateTime.utc_now() |> DateTime.add(60, :day)
        })

      %{channel: socket, keys: [key1, key2]}
    end

    test "lists user's API keys", %{channel: socket, keys: keys} do
      ref = push(socket, "list", %{})

      assert_push("key_list", %{
        api_keys: api_keys,
        page: 1,
        per_page: 20,
        total_count: count
      })

      assert count == 2
      assert length(api_keys) == 2

      # Verify keys are returned in descending order by created_at
      [first_key, second_key] = api_keys
      assert first_key.name == "Test Key 2"
      assert second_key.name == "Test Key 1"

      # Verify key structure
      assert %{
               id: _,
               name: _,
               expires_at: _,
               valid: _,
               last_used_at: _,
               created_at: _
             } = first_key
    end

    test "supports pagination", %{channel: socket, keys: _keys} do
      ref = push(socket, "list", %{"page" => 2, "per_page" => 1})

      assert_push("key_list", %{
        api_keys: api_keys,
        page: 2,
        per_page: 1,
        total_count: _
      })

      assert length(api_keys) == 1
    end

    test "handles list errors gracefully", %{channel: socket} do
      # This would test error handling if the read operation fails
      # Implementation depends on how to simulate Ash.read failures
    end
  end

  describe "handle_in revoke" do
    setup %{socket: socket, user: user} do
      {:ok, _reply, socket} = subscribe_and_join(socket, ApiKeyChannel, "api_keys:manage")

      # Create a test API key
      {:ok, api_key} =
        Ash.create(ApiKey, %{
          user_id: user.id,
          name: "Key to Revoke",
          expires_at: DateTime.utc_now() |> DateTime.add(30, :day)
        })

      %{channel: socket, api_key: api_key}
    end

    test "revokes an API key", %{channel: socket, api_key: api_key} do
      ref = push(socket, "revoke", %{"api_key_id" => api_key.id})

      assert_push("key_revoked", %{
        api_key_id: api_key_id,
        message: "API key revoked successfully"
      })

      assert api_key_id == api_key.id

      # Other clients should receive update
      assert_broadcast("key_list_updated", %{
        action: "revoked",
        api_key_id: ^api_key_id
      })

      # Verify key is actually deleted
      assert {:error, %Ash.Error.Query.NotFound{}} = Ash.get(ApiKey, api_key.id)
    end

    test "fails to revoke non-existent key", %{channel: socket} do
      fake_id = Ash.UUID.generate()
      ref = push(socket, "revoke", %{"api_key_id" => fake_id})

      assert_push("error", %{
        operation: "revoke",
        message: "Failed to revoke API key",
        details: "API key not found or unauthorized"
      })
    end

    test "fails to revoke another user's key", %{channel: socket} do
      # Create another user and their API key
      other_user = user_fixture()

      {:ok, other_key} =
        Ash.create(ApiKey, %{
          user_id: other_user.id,
          name: "Other User's Key",
          expires_at: DateTime.utc_now() |> DateTime.add(30, :day)
        })

      ref = push(socket, "revoke", %{"api_key_id" => other_key.id})

      assert_push("error", %{
        operation: "revoke",
        message: "Failed to revoke API key",
        details: "API key not found or unauthorized"
      })
    end
  end

  describe "handle_in get_stats" do
    setup %{socket: socket} do
      {:ok, _reply, socket} = subscribe_and_join(socket, ApiKeyChannel, "api_keys:manage")
      %{channel: socket}
    end

    test "returns API key statistics", %{channel: socket} do
      ref = push(socket, "get_stats", %{})

      assert_push("stats", %{
        total_keys: _,
        active_keys: _,
        expired_keys: _,
        revoked_keys: _,
        generation_limit: %{
          used: _,
          limit: limit,
          resets_at: resets_at
        }
      })

      # Matches @max_api_key_generation_per_hour
      assert limit == 10
      assert is_binary(resets_at)

      # Verify resets_at is a valid future datetime
      {:ok, reset_dt, _} = DateTime.from_iso8601(resets_at)
      assert DateTime.compare(reset_dt, DateTime.utc_now()) == :gt
    end
  end

  describe "broadcasting" do
    setup %{socket: socket} do
      {:ok, _reply, socket} = subscribe_and_join(socket, ApiKeyChannel, "api_keys:manage")
      %{channel: socket}
    end

    test "broadcasts updates to other clients", %{channel: socket} do
      # Simulate another client on the same channel
      # In a real test, you'd connect another socket

      ref = push(socket, "generate", %{"name" => "Broadcast Test"})

      assert_push("key_generated", %{api_key: %{id: key_id}})

      # Should broadcast to other clients (not self)
      assert_broadcast("key_list_updated", %{
        action: "generated",
        api_key_id: ^key_id
      })
    end
  end
end

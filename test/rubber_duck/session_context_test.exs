defmodule RubberDuck.SessionContextTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.SessionContext
  alias RubberDuck.UserConfig

  @valid_user_id "user_123"
  @valid_session_id "session_456"
  @valid_provider :openai
  @valid_model "gpt-4"

  setup do
    # Start the SessionContext GenServer for testing
    {:ok, _pid} = start_supervised({SessionContext, []})

    # Clean up any existing contexts
    contexts = SessionContext.list_contexts()

    Enum.each(contexts, fn context ->
      SessionContext.remove_context(context.session_id)
    end)

    :ok
  end

  describe "create_context/3" do
    test "creates a new session context" do
      assert {:ok, context} = SessionContext.create_context(@valid_session_id, @valid_user_id, %{})

      assert context.session_id == @valid_session_id
      assert context.user_id == @valid_user_id
      assert context.request_count == 0
      assert is_map(context.llm_config)
      assert is_map(context.preferences)
      assert %DateTime{} = context.created_at
      assert %DateTime{} = context.last_activity
    end

    test "includes user LLM configuration when available" do
      # Set user's LLM preference
      {:ok, _config} = UserConfig.set_default(@valid_user_id, @valid_provider, @valid_model)

      # Create context
      assert {:ok, context} = SessionContext.create_context(@valid_session_id, @valid_user_id, %{})

      assert context.llm_config.provider == @valid_provider
      assert context.llm_config.model == @valid_model
    end

    test "handles user without LLM configuration" do
      # Create context for user without preferences
      assert {:ok, context} = SessionContext.create_context(@valid_session_id, "new_user", %{})

      # Should still create context with nil/empty LLM config
      assert context.llm_config.provider == nil
      assert context.llm_config.model == nil
    end
  end

  describe "get_context/1" do
    test "retrieves existing context" do
      # Create context
      {:ok, original_context} = SessionContext.create_context(@valid_session_id, @valid_user_id, %{})

      # Retrieve context
      assert {:ok, retrieved_context} = SessionContext.get_context(@valid_session_id)
      assert retrieved_context.session_id == original_context.session_id
      assert retrieved_context.user_id == original_context.user_id
    end

    test "returns error for non-existent context" do
      assert {:error, :not_found} = SessionContext.get_context("non_existent_session")
    end
  end

  describe "update_preferences/2" do
    test "updates session preferences" do
      # Create context
      {:ok, _context} = SessionContext.create_context(@valid_session_id, @valid_user_id, %{})

      # Update preferences
      new_preferences = %{"temperature" => 0.9, "max_tokens" => 1000}
      assert :ok = SessionContext.update_preferences(@valid_session_id, new_preferences)

      # Verify preferences were updated
      {:ok, updated_context} = SessionContext.get_context(@valid_session_id)
      assert updated_context.preferences["temperature"] == 0.9
      assert updated_context.preferences["max_tokens"] == 1000
    end

    test "merges with existing preferences" do
      # Create context with initial preferences
      initial_preferences = %{"temperature" => 0.7}

      {:ok, _context} =
        SessionContext.create_context(@valid_session_id, @valid_user_id, %{preferences: initial_preferences})

      # Update with additional preferences
      new_preferences = %{"max_tokens" => 1000}
      assert :ok = SessionContext.update_preferences(@valid_session_id, new_preferences)

      # Verify both preferences exist
      {:ok, updated_context} = SessionContext.get_context(@valid_session_id)
      assert updated_context.preferences["temperature"] == 0.7
      assert updated_context.preferences["max_tokens"] == 1000
    end

    test "returns error for non-existent context" do
      assert {:error, :not_found} = SessionContext.update_preferences("non_existent_session", %{})
    end
  end

  describe "get_llm_config/1" do
    test "returns user's LLM configuration" do
      # Set user's LLM preference
      {:ok, _config} = UserConfig.set_default(@valid_user_id, @valid_provider, @valid_model)

      # Create context
      {:ok, _context} = SessionContext.create_context(@valid_session_id, @valid_user_id, %{})

      # Get LLM config
      assert {:ok, llm_config} = SessionContext.get_llm_config(@valid_session_id)
      assert llm_config.provider == @valid_provider
      assert llm_config.model == @valid_model
    end

    test "falls back to global config when no user preference" do
      # Mock global config
      Application.put_env(:rubber_duck, :llm,
        default_provider: :anthropic,
        providers: [
          %{name: :anthropic, models: ["claude-3-sonnet"], default_model: "claude-3-sonnet"}
        ]
      )

      # Create context for user without preferences
      {:ok, _context} = SessionContext.create_context(@valid_session_id, "new_user", %{})

      # Get LLM config - should fall back to global
      assert {:ok, llm_config} = SessionContext.get_llm_config(@valid_session_id)
      assert llm_config.provider == :anthropic
      assert llm_config.model == "claude-3-sonnet"
    end

    test "returns error when no configuration available" do
      # Clear global config
      Application.put_env(:rubber_duck, :llm, [])

      # Create context for user without preferences
      {:ok, _context} = SessionContext.create_context(@valid_session_id, "new_user", %{})

      # Get LLM config - should return error
      assert {:error, :no_llm_config} = SessionContext.get_llm_config(@valid_session_id)
    end

    test "returns error for non-existent context" do
      assert {:error, :not_found} = SessionContext.get_llm_config("non_existent_session")
    end
  end

  describe "record_llm_usage/3" do
    test "records LLM usage in session context" do
      # Create context
      {:ok, _context} = SessionContext.create_context(@valid_session_id, @valid_user_id, %{})

      # Record usage
      assert :ok = SessionContext.record_llm_usage(@valid_session_id, @valid_provider, @valid_model)

      # Verify usage was recorded
      {:ok, updated_context} = SessionContext.get_context(@valid_session_id)
      assert updated_context.last_used_provider == @valid_provider
      assert updated_context.last_used_model == @valid_model
      assert updated_context.request_count == 1
    end

    test "increments request count on multiple uses" do
      # Create context
      {:ok, _context} = SessionContext.create_context(@valid_session_id, @valid_user_id, %{})

      # Record multiple usages
      assert :ok = SessionContext.record_llm_usage(@valid_session_id, @valid_provider, @valid_model)
      assert :ok = SessionContext.record_llm_usage(@valid_session_id, @valid_provider, @valid_model)
      assert :ok = SessionContext.record_llm_usage(@valid_session_id, :anthropic, "claude-3-sonnet")

      # Verify count was incremented
      {:ok, updated_context} = SessionContext.get_context(@valid_session_id)
      assert updated_context.request_count == 3
      assert updated_context.last_used_provider == :anthropic
      assert updated_context.last_used_model == "claude-3-sonnet"
    end

    test "succeeds even for non-existent context" do
      # Recording usage for non-existent context should not crash
      assert :ok = SessionContext.record_llm_usage("non_existent_session", @valid_provider, @valid_model)
    end
  end

  describe "remove_context/1" do
    test "removes session context" do
      # Create context
      {:ok, _context} = SessionContext.create_context(@valid_session_id, @valid_user_id, %{})

      # Verify it exists
      assert {:ok, _context} = SessionContext.get_context(@valid_session_id)

      # Remove it
      assert :ok = SessionContext.remove_context(@valid_session_id)

      # Verify it's gone
      assert {:error, :not_found} = SessionContext.get_context(@valid_session_id)
    end

    test "succeeds even for non-existent context" do
      assert :ok = SessionContext.remove_context("non_existent_session")
    end
  end

  describe "list_contexts/0" do
    test "lists all active contexts" do
      # Create multiple contexts
      {:ok, _context1} = SessionContext.create_context("session_1", "user_1", %{})
      {:ok, _context2} = SessionContext.create_context("session_2", "user_2", %{})

      # List contexts
      contexts = SessionContext.list_contexts()
      assert length(contexts) == 2

      session_ids = Enum.map(contexts, & &1.session_id)
      assert "session_1" in session_ids
      assert "session_2" in session_ids
    end

    test "returns empty list when no contexts exist" do
      contexts = SessionContext.list_contexts()
      assert contexts == []
    end
  end

  describe "get_stats/0" do
    test "returns session context statistics" do
      # Create some contexts
      {:ok, _context1} = SessionContext.create_context("session_1", "user_1", %{})
      {:ok, _context2} = SessionContext.create_context("session_2", "user_2", %{})

      # Record some usage
      SessionContext.record_llm_usage("session_1", @valid_provider, @valid_model)
      SessionContext.record_llm_usage("session_2", @valid_provider, @valid_model)

      # Get stats
      stats = SessionContext.get_stats()
      assert stats.active_contexts == 2
      assert stats.llm_requests == 2
      assert stats.contexts_created == 2
      assert is_integer(stats.uptime_ms)
    end
  end

  describe "ensure_context/3" do
    test "creates context if it doesn't exist" do
      # Ensure context for non-existent session
      assert {:ok, context} = SessionContext.ensure_context(@valid_session_id, @valid_user_id, %{})
      assert context.session_id == @valid_session_id
      assert context.user_id == @valid_user_id
    end

    test "returns existing context if it exists" do
      # Create context
      {:ok, original_context} = SessionContext.create_context(@valid_session_id, @valid_user_id, %{})

      # Ensure context - should return existing one
      assert {:ok, ensured_context} = SessionContext.ensure_context(@valid_session_id, @valid_user_id, %{})
      assert ensured_context.session_id == original_context.session_id
      assert ensured_context.created_at == original_context.created_at
    end
  end

  describe "enhance_llm_options/2" do
    test "enhances options with user's LLM config" do
      # Set user's LLM preference
      {:ok, _config} = UserConfig.set_default(@valid_user_id, @valid_provider, @valid_model)

      # Create context
      {:ok, _context} = SessionContext.create_context(@valid_session_id, @valid_user_id, %{})

      # Enhance options
      original_opts = [temperature: 0.8, max_tokens: 500]
      enhanced_opts = SessionContext.enhance_llm_options(@valid_session_id, original_opts)

      assert enhanced_opts[:temperature] == 0.8
      assert enhanced_opts[:max_tokens] == 500
      assert enhanced_opts[:model] == @valid_model
      assert enhanced_opts[:provider] == @valid_provider
      assert enhanced_opts[:user_id] == @valid_user_id
    end

    test "preserves original options when no user config" do
      # Create context for user without preferences
      {:ok, _context} = SessionContext.create_context(@valid_session_id, "new_user", %{})

      # Enhance options
      original_opts = [temperature: 0.8, max_tokens: 500]
      enhanced_opts = SessionContext.enhance_llm_options(@valid_session_id, original_opts)

      assert enhanced_opts[:temperature] == 0.8
      assert enhanced_opts[:max_tokens] == 500
      assert enhanced_opts[:user_id] == "new_user"
    end

    test "returns original options for non-existent context" do
      original_opts = [temperature: 0.8, max_tokens: 500]
      enhanced_opts = SessionContext.enhance_llm_options("non_existent_session", original_opts)

      assert enhanced_opts == original_opts
    end
  end
end

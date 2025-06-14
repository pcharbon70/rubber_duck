defmodule RubberDuck.MessagePassingTest do
  use ExUnit.Case, async: false

  alias RubberDuck.{ContextManager, ModelCoordinator}

  setup do
    # Ensure application is started
    {:ok, _} = Application.ensure_all_started(:rubber_duck)
    on_exit(fn -> Application.stop(:rubber_duck) end)
    :ok
  end

  describe "ContextManager to ModelCoordinator communication" do
    test "ContextManager can request model selection from ModelCoordinator" do
      # Register a model first
      model_spec = %{
        name: "gpt-4",
        type: :llm,
        endpoint: "https://api.openai.com/v1/chat/completions",
        capabilities: [:chat, :completion]
      }
      ModelCoordinator.register_model(model_spec)
      
      # Create a session
      {:ok, session_id} = ContextManager.create_session()
      
      # ContextManager should be able to request a model
      assert {:ok, model} = ContextManager.request_model(session_id, capability: :chat)
      assert model.name == "gpt-4"
      assert :chat in model.capabilities
    end

    test "ContextManager stores selected model in session metadata" do
      # Register a model
      model_spec = %{
        name: "claude",
        type: :llm,
        endpoint: "https://api.anthropic.com/v1/messages",
        capabilities: [:chat, :reasoning]
      }
      ModelCoordinator.register_model(model_spec)
      
      # Create session and request model
      {:ok, session_id} = ContextManager.create_session()
      {:ok, _model} = ContextManager.request_model(session_id, capability: :reasoning)
      
      # Check that model is stored in session metadata
      {:ok, context} = ContextManager.get_context(session_id)
      assert context.metadata.selected_model == "claude"
    end

    test "ContextManager tracks model usage through ModelCoordinator" do
      # Register a model
      model_spec = %{
        name: "gpt-4",
        type: :llm,
        endpoint: "endpoint",
        capabilities: [:chat]
      }
      ModelCoordinator.register_model(model_spec)
      
      # Create session and simulate model usage
      {:ok, session_id} = ContextManager.create_session()
      {:ok, _model} = ContextManager.request_model(session_id)
      
      # Simulate successful completion
      assert :ok = ContextManager.report_model_usage(session_id, :success, 250)
      
      # Verify stats were tracked
      stats = ModelCoordinator.get_stats("gpt-4")
      assert stats.success_count == 1
      assert stats.total_latency == 250
    end
  end

  describe "ModelCoordinator to ContextManager communication" do
    test "ModelCoordinator can notify ContextManager of model health changes" do
      # Register a model
      model_spec = %{
        name: "gpt-4",
        type: :llm,
        endpoint: "endpoint",
        capabilities: [:chat]
      }
      ModelCoordinator.register_model(model_spec)
      
      # Create sessions using the model
      {:ok, session1} = ContextManager.create_session()
      {:ok, session2} = ContextManager.create_session()
      
      ContextManager.request_model(session1)
      ContextManager.request_model(session2)
      
      # Mark model as unhealthy
      ModelCoordinator.mark_unhealthy("gpt-4", "Connection timeout")
      
      # Both sessions should be notified
      {:ok, context1} = ContextManager.get_context(session1)
      {:ok, context2} = ContextManager.get_context(session2)
      
      assert context1.metadata.model_health_warning == "Model gpt-4 is unhealthy: Connection timeout"
      assert context2.metadata.model_health_warning == "Model gpt-4 is unhealthy: Connection timeout"
    end
  end

  describe "Bidirectional communication patterns" do
    test "processes can discover each other via Registry" do
      # Both processes should be findable by their module names
      context_pid = Process.whereis(RubberDuck.ContextManager)
      model_pid = Process.whereis(RubberDuck.ModelCoordinator)
      
      assert context_pid != nil
      assert model_pid != nil
      assert Process.alive?(context_pid)
      assert Process.alive?(model_pid)
    end

    test "processes handle concurrent requests properly" do
      # Register multiple models
      models = [
        %{name: "gpt-4", type: :llm, endpoint: "endpoint1", capabilities: [:chat]},
        %{name: "claude", type: :llm, endpoint: "endpoint2", capabilities: [:chat]},
        %{name: "local", type: :llm, endpoint: "endpoint3", capabilities: [:chat]}
      ]
      
      Enum.each(models, &ModelCoordinator.register_model/1)
      
      # Create multiple sessions concurrently
      tasks = for _i <- 1..10 do
        Task.async(fn ->
          {:ok, session_id} = ContextManager.create_session()
          {:ok, model} = ContextManager.request_model(session_id)
          {session_id, model.name}
        end)
      end
      
      results = Task.await_many(tasks)
      
      # All should succeed
      assert length(results) == 10
      assert Enum.all?(results, fn {session_id, model_name} ->
        is_binary(session_id) && model_name in ["gpt-4", "claude", "local"]
      end)
    end

    test "graceful handling when ModelCoordinator is unavailable" do
      # Stop the ModelCoordinator
      GenServer.stop(ModelCoordinator)
      
      # Wait a bit for supervisor to restart it
      Process.sleep(100)
      
      # ContextManager should handle this gracefully
      {:ok, session_id} = ContextManager.create_session()
      assert {:error, :no_model_available} = ContextManager.request_model(session_id)
    end
  end
end
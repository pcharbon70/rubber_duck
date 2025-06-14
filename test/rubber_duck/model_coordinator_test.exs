defmodule RubberDuck.ModelCoordinatorTest do
  use ExUnit.Case, async: false

  alias RubberDuck.ModelCoordinator

  setup do
    # Stop the application to control GenServer lifecycle in tests
    Application.stop(:rubber_duck)
    on_exit(fn -> Application.start(:rubber_duck) end)
    :ok
  end

  describe "start_link/1" do
    test "starts the ModelCoordinator GenServer" do
      assert {:ok, pid} = ModelCoordinator.start_link([])
      assert Process.alive?(pid)
    end

    test "registers the process with its module name" do
      assert {:ok, _pid} = ModelCoordinator.start_link([])
      assert Process.whereis(ModelCoordinator) != nil
    end

    test "accepts configuration options" do
      config = %{max_concurrent_models: 3, timeout: 30_000}
      assert {:ok, pid} = ModelCoordinator.start_link(config: config)
      assert Process.alive?(pid)
    end
  end

  describe "model management" do
    setup do
      {:ok, pid} = ModelCoordinator.start_link([])
      %{pid: pid}
    end

    test "registers a model", %{pid: pid} do
      model_spec = %{
        name: "gpt-4",
        type: :llm,
        endpoint: "https://api.openai.com/v1/chat/completions",
        capabilities: [:chat, :completion]
      }
      
      assert :ok = ModelCoordinator.register_model(pid, model_spec)
    end

    test "lists registered models", %{pid: pid} do
      model1 = %{name: "gpt-4", type: :llm, endpoint: "endpoint1", capabilities: [:chat]}
      model2 = %{name: "claude", type: :llm, endpoint: "endpoint2", capabilities: [:chat]}
      
      ModelCoordinator.register_model(pid, model1)
      ModelCoordinator.register_model(pid, model2)
      
      models = ModelCoordinator.list_models(pid)
      assert length(models) == 2
      assert "gpt-4" in Enum.map(models, & &1.name)
      assert "claude" in Enum.map(models, & &1.name)
    end

    test "gets model info", %{pid: pid} do
      model_spec = %{
        name: "gpt-4",
        type: :llm,
        endpoint: "https://api.openai.com/v1/chat/completions",
        capabilities: [:chat, :completion]
      }
      
      ModelCoordinator.register_model(pid, model_spec)
      
      assert {:ok, model} = ModelCoordinator.get_model(pid, "gpt-4")
      assert model.name == "gpt-4"
      assert model.type == :llm
    end

    test "returns error for non-existent model", %{pid: pid} do
      assert {:error, :model_not_found} = ModelCoordinator.get_model(pid, "non-existent")
    end

    test "unregisters a model", %{pid: pid} do
      model_spec = %{name: "gpt-4", type: :llm, endpoint: "endpoint", capabilities: [:chat]}
      
      ModelCoordinator.register_model(pid, model_spec)
      assert :ok = ModelCoordinator.unregister_model(pid, "gpt-4")
      assert {:error, :model_not_found} = ModelCoordinator.get_model(pid, "gpt-4")
    end

    test "updates model configuration", %{pid: pid} do
      model_spec = %{name: "gpt-4", type: :llm, endpoint: "endpoint1", capabilities: [:chat]}
      ModelCoordinator.register_model(pid, model_spec)
      
      updates = %{endpoint: "endpoint2", timeout: 60_000}
      assert :ok = ModelCoordinator.update_model(pid, "gpt-4", updates)
      
      {:ok, model} = ModelCoordinator.get_model(pid, "gpt-4")
      assert model.endpoint == "endpoint2"
      assert model.timeout == 60_000
    end
  end

  describe "model selection and load balancing" do
    setup do
      {:ok, pid} = ModelCoordinator.start_link([])
      
      # Register multiple models
      models = [
        %{name: "gpt-4", type: :llm, endpoint: "endpoint1", capabilities: [:chat, :completion]},
        %{name: "claude", type: :llm, endpoint: "endpoint2", capabilities: [:chat, :reasoning]},
        %{name: "local-llm", type: :llm, endpoint: "endpoint3", capabilities: [:chat]}
      ]
      
      Enum.each(models, &ModelCoordinator.register_model(pid, &1))
      
      %{pid: pid}
    end

    test "selects model by capability", %{pid: pid} do
      assert {:ok, model} = ModelCoordinator.select_model(pid, capability: :reasoning)
      assert model.name == "claude"
    end

    test "selects any available model when no capability specified", %{pid: pid} do
      assert {:ok, model} = ModelCoordinator.select_model(pid)
      assert model.name in ["gpt-4", "claude", "local-llm"]
    end

    test "returns error when no model matches capability", %{pid: pid} do
      assert {:error, :no_model_available} = ModelCoordinator.select_model(pid, capability: :image_generation)
    end

    test "tracks model usage statistics", %{pid: pid} do
      ModelCoordinator.track_usage(pid, "gpt-4", :success, 150)
      ModelCoordinator.track_usage(pid, "gpt-4", :success, 200)
      ModelCoordinator.track_usage(pid, "gpt-4", :failure, 0)
      
      stats = ModelCoordinator.get_stats(pid, "gpt-4")
      assert stats.success_count == 2
      assert stats.failure_count == 1
      assert stats.total_latency == 350
      assert stats.average_latency == 175
    end
  end

  describe "process registration with Registry" do
    setup do
      # Ensure application is started
      {:ok, _} = Application.ensure_all_started(:rubber_duck)
      on_exit(fn -> Application.stop(:rubber_duck) end)
      :ok
    end

    test "registers with Registry on start" do
      {:ok, pid} = ModelCoordinator.start_link(name: :test_model_coordinator)
      
      # Should be findable via Registry
      assert [{^pid, _}] = Registry.lookup(RubberDuck.Registry, :test_model_coordinator)
      assert Process.alive?(pid)
      
      # Stop the process
      GenServer.stop(pid)
    end
  end

  describe "graceful shutdown" do
    test "handles normal shutdown gracefully" do
      {:ok, pid} = ModelCoordinator.start_link([])
      
      # Add some state
      model_spec = %{name: "gpt-4", type: :llm, endpoint: "endpoint", capabilities: [:chat]}
      ModelCoordinator.register_model(pid, model_spec)
      
      # Shutdown should complete without error
      assert :ok = GenServer.stop(pid, :normal)
      refute Process.alive?(pid)
    end
  end

  describe "health monitoring" do
    setup do
      {:ok, pid} = ModelCoordinator.start_link([])
      %{pid: pid}
    end

    test "responds to health check", %{pid: pid} do
      assert :ok = ModelCoordinator.health_check(pid)
    end

    test "returns coordinator info", %{pid: pid} do
      info = ModelCoordinator.get_info(pid)
      
      assert %{
        status: :running,
        model_count: 0,
        memory: _,
        uptime: _
      } = info
    end

    test "monitors model health", %{pid: pid} do
      model_spec = %{name: "gpt-4", type: :llm, endpoint: "endpoint", capabilities: [:chat]}
      ModelCoordinator.register_model(pid, model_spec)
      
      # Mark model as unhealthy
      ModelCoordinator.mark_unhealthy(pid, "gpt-4", "Connection timeout")
      
      {:ok, model} = ModelCoordinator.get_model(pid, "gpt-4")
      assert model.health_status == :unhealthy
      assert model.health_reason == "Connection timeout"
      
      # Mark model as healthy again
      ModelCoordinator.mark_healthy(pid, "gpt-4")
      
      {:ok, model} = ModelCoordinator.get_model(pid, "gpt-4")
      assert model.health_status == :healthy
    end
  end
end
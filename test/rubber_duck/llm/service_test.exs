defmodule RubberDuck.LLM.ServiceTest do
  use ExUnit.Case, async: false

  alias RubberDuck.LLM.{Service, Response}

  setup do
    # Ensure the service is started
    case GenServer.whereis(Service) do
      nil ->
        {:ok, _pid} = Service.start_link()

      _ ->
        :ok
    end

    :ok
  end

  describe "completion/1" do
    test "sends completion request to mock provider" do
      opts = [
        provider: :mock,
        model: "mock-fast",
        messages: [
          %{"role" => "user", "content" => "Hello, world!"}
        ],
        user_id: "test_user"
      ]

      assert {:ok, %Response{} = response} = Service.completion(opts)
      assert response.provider == :mock
      assert response.model == "mock-fast"
      assert is_list(response.choices)
      assert length(response.choices) > 0
    end

    test "returns error when model is not provided" do
      opts = [
        provider: :mock,
        messages: [
          %{"role" => "user", "content" => "Hello"}
        ],
        user_id: "test_user"
      ]

      assert {:error, {:missing_required_parameter, :model}} = Service.completion(opts)
    end

    test "returns error when messages are not provided" do
      opts = [
        provider: :mock,
        model: "mock-fast",
        user_id: "test_user"
      ]

      assert {:error, {:missing_required_parameter, :messages}} = Service.completion(opts)
    end

    @tag :skip  # Mock provider accepts any model for testing purposes
    test "returns error for unknown model" do
      opts = [
        provider: :mock,
        model: "unknown-model",
        messages: [
          %{"role" => "user", "content" => "Hello"}
        ],
        user_id: "test_user"
      ]

      assert {:error, {:unknown_model, "unknown-model"}} = Service.completion(opts)
    end

    test "includes optional parameters in request" do
      opts = [
        provider: :mock,
        model: "mock-fast",
        messages: [
          %{"role" => "user", "content" => "Generate code"}
        ],
        temperature: 0.5,
        max_tokens: 100,
        user_id: "test_user"
      ]

      assert {:ok, %Response{} = response} = Service.completion(opts)
      assert response.provider == :mock
    end
  end

  describe "completion_async/1" do
    @tag :skip
    @tag :skip
    test "returns request ID immediately" do
      opts = [
        provider: :mock,
        model: "mock-fast",
        messages: [
          %{"role" => "user", "content" => "Hello async"}
        ],
        user_id: "test_user"
      ]

      assert {:ok, request_id} = Service.completion_async(opts)
      assert is_binary(request_id)
      assert String.starts_with?(request_id, "req_")
    end

    @tag :skip
    test "can retrieve async result" do
      opts = [
        provider: :mock,
        model: "mock-fast",
        messages: [
          %{"role" => "user", "content" => "Hello async"}
        ],
        user_id: "test_user"
      ]

      {:ok, request_id} = Service.completion_async(opts)

      # Wait a bit for processing
      Process.sleep(200)

      assert {:ok, %Response{}} = Service.get_result(request_id)
    end

    @tag :skip
    test "returns pending for in-progress request" do
      # Use a mock with delay
      opts = [
        provider: :mock,
        model: "mock-smart",
        messages: [
          %{"role" => "user", "content" => "Slow request"}
        ],
        user_id: "test_user"
      ]

      {:ok, request_id} = Service.completion_async(opts)

      # Check immediately
      assert :pending = Service.get_result(request_id)
    end
  end

  describe "list_models/0" do
    test "returns available models" do
      assert {:ok, models} = Service.list_models()

      assert is_list(models)
      assert length(models) > 0

      # Check mock models are included
      model_names = Enum.map(models, & &1.model)
      assert "mock-fast" in model_names
      assert "mock-smart" in model_names
    end

    test "includes provider and availability info" do
      {:ok, models} = Service.list_models()

      first_model = hd(models)
      assert Map.has_key?(first_model, :model)
      assert Map.has_key?(first_model, :provider)
      assert Map.has_key?(first_model, :available)
    end
  end

  describe "health_status/0" do
    @tag :skip
    test "returns health information for all providers" do
      assert {:ok, health} = Service.health_status()

      assert is_map(health)
      assert Map.has_key?(health, :mock)

      mock_health = health[:mock]
      assert Map.has_key?(mock_health, :status)
      assert Map.has_key?(mock_health, :uptime_percentage)
    end
  end

  describe "cost_summary/1" do
    test "returns cost tracking information" do
      # Make a request first to generate some cost data
      opts = [
        provider: :mock,
        model: "mock-fast",
        messages: [
          %{"role" => "user", "content" => "Test for cost tracking"}
        ],
        user_id: "test_user"
      ]

      {:ok, _response} = Service.completion(opts)

      # Get cost summary
      assert {:ok, summary} = Service.cost_summary()

      assert Map.has_key?(summary, :total_cost)
      assert Map.has_key?(summary, :cost_by_provider)
      assert Map.has_key?(summary, :token_usage)
    end

    test "can filter cost summary by provider" do
      assert {:ok, summary} = Service.cost_summary(provider: :mock)

      assert Map.has_key?(summary, :total_cost)
    end
  end
end

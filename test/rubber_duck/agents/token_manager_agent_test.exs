defmodule RubberDuck.Agents.TokenManagerAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.TokenManagerAgent
  alias RubberDuck.Agents.TokenManager.{TokenUsage, Budget}

  describe "TokenManagerAgent initialization" do
    test "initializes with default configuration" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      assert agent.budgets == %{}
      assert agent.active_requests == %{}
      assert agent.usage_buffer == []
      assert agent.metrics.total_tokens == 0
      assert Decimal.eq?(agent.metrics.total_cost, Decimal.new(0))
      assert agent.config.buffer_size == 100
      assert agent.config.flush_interval == 5_000
    end

    test "includes default pricing models" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      assert Map.has_key?(agent.pricing_models, "openai")
      assert Map.has_key?(agent.pricing_models, "anthropic")
      assert Map.has_key?(agent.pricing_models, "local")
      
      # Check OpenAI pricing
      assert agent.pricing_models["openai"]["gpt-4"].prompt == 0.03
      assert agent.pricing_models["openai"]["gpt-4"].completion == 0.06
    end
  end

  describe "track_usage signal" do
    setup do
      {:ok, agent} = TokenManagerAgent.init(%{})
      {:ok, agent: agent}
    end

    test "tracks token usage successfully", %{agent: agent} do
      data = %{
        "request_id" => "req_123",
        "provider" => "openai",
        "model" => "gpt-4",
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "user_id" => "user_123",
        "project_id" => "proj_123",
        "metadata" => %{"feature" => "chat"}
      }
      
      {:ok, result, updated_agent} = TokenManagerAgent.handle_signal("track_usage", data, agent)
      
      assert result["tracked"] == true
      assert result["usage"].total_tokens == 150
      assert Decimal.gt?(result["usage"].cost, Decimal.new(0))
      
      # Check agent state updates
      assert length(updated_agent.usage_buffer) == 1
      assert updated_agent.metrics.total_tokens == 150
      assert updated_agent.metrics.requests_tracked == 1
    end

    test "calculates cost correctly for OpenAI GPT-4", %{agent: agent} do
      data = %{
        "request_id" => "req_123",
        "provider" => "openai",
        "model" => "gpt-4",
        "prompt_tokens" => 1000,
        "completion_tokens" => 500,
        "user_id" => "user_123",
        "project_id" => "proj_123",
        "metadata" => %{}
      }
      
      {:ok, result, _} = TokenManagerAgent.handle_signal("track_usage", data, agent)
      
      # GPT-4: $0.03/1K prompt + $0.06/1K completion
      # 1000 prompt tokens = $0.03
      # 500 completion tokens = $0.03
      # Total = $0.06
      expected_cost = Decimal.new("0.06")
      assert Decimal.eq?(result["usage"].cost, expected_cost)
    end

    test "handles missing metadata gracefully", %{agent: agent} do
      data = %{
        "request_id" => "req_123",
        "provider" => "anthropic",
        "model" => "claude-3-sonnet",
        "prompt_tokens" => 200,
        "completion_tokens" => 100,
        "user_id" => "user_123",
        "project_id" => "proj_123",
        "metadata" => %{}
      }
      
      {:ok, result, _} = TokenManagerAgent.handle_signal("track_usage", data, agent)
      
      assert result["tracked"] == true
      assert result["usage"].team_id == nil
      assert result["usage"].feature == nil
    end

    test "flushes buffer when full", %{agent: agent} do
      # Set small buffer size for testing
      agent = put_in(agent.config.buffer_size, 2)
      
      # Track first usage
      data1 = base_usage_data("req_1")
      {:ok, _, agent} = TokenManagerAgent.handle_signal("track_usage", data1, agent)
      assert length(agent.usage_buffer) == 1
      
      # Track second usage - should trigger flush
      data2 = base_usage_data("req_2")
      {:ok, _, agent} = TokenManagerAgent.handle_signal("track_usage", data2, agent)
      assert length(agent.usage_buffer) == 0  # Buffer flushed
    end
  end

  describe "check_budget signal" do
    setup do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      # Create a test budget
      budget_data = %{
        "name" => "Test Budget",
        "type" => "user",
        "entity_id" => "user_123",
        "period" => "daily",
        "limit" => "10.00",
        "currency" => "USD"
      }
      
      {:ok, _, agent} = TokenManagerAgent.handle_signal("create_budget", budget_data, agent)
      {:ok, agent: agent}
    end

    test "approves request within budget", %{agent: agent} do
      data = %{
        "user_id" => "user_123",
        "project_id" => "proj_123",
        "estimated_tokens" => 1000,
        "request_id" => "req_123"
      }
      
      {:ok, result, updated_agent} = TokenManagerAgent.handle_signal("check_budget", data, agent)
      
      assert result["allowed"] == true
      assert Map.has_key?(updated_agent.active_requests, "req_123")
    end

    test "denies request exceeding budget", %{agent: agent} do
      # First, use up most of the budget
      [budget_id | _] = Map.keys(agent.budgets)
      budget = agent.budgets[budget_id]
      updated_budget = %{budget | spent: Decimal.new("9.90"), remaining: Decimal.new("0.10")}
      agent = put_in(agent.budgets[budget_id], updated_budget)
      
      data = %{
        "user_id" => "user_123",
        "project_id" => "proj_123",
        "estimated_tokens" => 10000,  # Would cost more than $0.10
        "request_id" => "req_123"
      }
      
      {:ok, result, updated_agent} = TokenManagerAgent.handle_signal("check_budget", data, agent)
      
      assert result["allowed"] == false
      assert length(result["violations"]) > 0
      assert updated_agent.metrics.budget_violations == 1
    end

    test "checks multiple applicable budgets", %{agent: agent} do
      # Add a global budget
      global_budget_data = %{
        "name" => "Global Budget",
        "type" => "global",
        "entity_id" => nil,
        "period" => "monthly",
        "limit" => "1000.00"
      }
      
      {:ok, _, agent} = TokenManagerAgent.handle_signal("create_budget", global_budget_data, agent)
      
      data = %{
        "user_id" => "user_123",
        "project_id" => "proj_123",
        "estimated_tokens" => 1000,
        "request_id" => "req_123"
      }
      
      {:ok, result, _} = TokenManagerAgent.handle_signal("check_budget", data, agent)
      
      assert result["allowed"] == true
      # Should check both user and global budgets
    end
  end

  describe "budget management signals" do
    test "creates budget successfully" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      budget_data = %{
        "name" => "Project Alpha Budget",
        "type" => "project",
        "entity_id" => "proj_alpha",
        "period" => "monthly",
        "limit" => "500.00",
        "currency" => "USD",
        "alert_thresholds" => [50, 80, 95]
      }
      
      {:ok, result, updated_agent} = TokenManagerAgent.handle_signal("create_budget", budget_data, agent)
      
      assert Map.has_key?(result, "budget_id")
      assert result["budget"].name == "Project Alpha Budget"
      assert Decimal.eq?(result["budget"].limit, Decimal.new("500.00"))
      assert map_size(updated_agent.budgets) == 1
    end

    test "updates budget successfully" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      # Create budget
      {:ok, %{"budget_id" => budget_id}, agent} = TokenManagerAgent.handle_signal(
        "create_budget",
        %{
          "name" => "Test Budget",
          "type" => "user",
          "entity_id" => "user_123",
          "period" => "daily",
          "limit" => "10.00"
        },
        agent
      )
      
      # Update budget
      update_data = %{
        "budget_id" => budget_id,
        "updates" => %{
          "limit" => "20.00",
          "alert_thresholds" => [60, 85, 95]
        }
      }
      
      {:ok, result, updated_agent} = TokenManagerAgent.handle_signal("update_budget", update_data, agent)
      
      assert Decimal.eq?(result["budget"].limit, Decimal.new("20.00"))
      assert result["budget"].alert_thresholds == [60, 85, 95]
    end

    test "handles update of non-existent budget" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      update_data = %{
        "budget_id" => "non_existent",
        "updates" => %{"limit" => "20.00"}
      }
      
      {:error, reason, _} = TokenManagerAgent.handle_signal("update_budget", update_data, agent)
      
      assert reason == "Budget not found"
    end
  end

  describe "usage query signals" do
    setup do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      # Add some usage data
      usage_data = [
        %{provider: "openai", model: "gpt-4", tokens: 1000, user: "user_1"},
        %{provider: "openai", model: "gpt-3.5-turbo", tokens: 2000, user: "user_1"},
        %{provider: "anthropic", model: "claude-3-sonnet", tokens: 1500, user: "user_2"}
      ]
      
      agent = Enum.reduce(usage_data, agent, fn data, acc ->
        usage = TokenUsage.new(%{
          provider: data.provider,
          model: data.model,
          prompt_tokens: div(data.tokens, 2),
          completion_tokens: div(data.tokens, 2),
          total_tokens: data.tokens,
          user_id: data.user,
          project_id: "proj_123",
          cost: Decimal.new("1.00"),
          request_id: "req_#{:rand.uniform(1000)}"
        })
        
        update_in(acc.usage_buffer, &[usage | &1])
        |> update_in([Access.key(:metrics), :total_tokens], &(&1 + data.tokens))
        |> update_in([Access.key(:metrics), :requests_tracked], &(&1 + 1))
      end)
      
      {:ok, agent: agent}
    end

    test "queries usage data", %{agent: agent} do
      query_data = %{
        "user_id" => "user_1",
        "project_id" => "proj_123",
        "limit" => 10
      }
      
      {:ok, result, _} = TokenManagerAgent.handle_signal("get_usage", query_data, agent)
      
      assert result.total_tokens == 4500  # Total from all usage
      assert result.requests == 3
      assert Map.has_key?(result, :breakdown)
    end
  end

  describe "report generation signals" do
    setup do
      {:ok, agent} = TokenManagerAgent.init(%{})
      {:ok, agent: agent}
    end

    test "generates usage report", %{agent: agent} do
      report_data = %{
        "type" => "usage",
        "period" => "last_7_days"
      }
      
      {:ok, report, _} = TokenManagerAgent.handle_signal("generate_report", report_data, agent)
      
      assert Map.has_key?(report, :id)
      assert Map.has_key?(report, :total_tokens)
      assert Map.has_key?(report, :total_cost)
      assert Map.has_key?(report, :recommendations)
    end

    test "generates cost report", %{agent: agent} do
      report_data = %{
        "type" => "cost",
        "period" => "this_month"
      }
      
      {:ok, report, _} = TokenManagerAgent.handle_signal("generate_report", report_data, agent)
      
      assert Map.has_key?(report, :total_cost)
      assert Map.has_key?(report, :projections)
    end

    test "generates optimization report", %{agent: agent} do
      report_data = %{
        "type" => "optimization",
        "period" => "last_30_days"
      }
      
      {:ok, report, _} = TokenManagerAgent.handle_signal("generate_report", report_data, agent)
      
      assert Map.has_key?(report, :opportunities)
      assert Map.has_key?(report, :recommendations)
      assert Map.has_key?(report, :potential_savings)
    end

    test "handles unknown report type", %{agent: agent} do
      report_data = %{
        "type" => "unknown_type",
        "period" => "today"
      }
      
      {:error, reason, _} = TokenManagerAgent.handle_signal("generate_report", report_data, agent)
      
      assert reason == "Unknown report type"
    end
  end

  describe "recommendations signal" do
    test "generates optimization recommendations" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      # Add usage data that would trigger recommendations
      expensive_usage = Enum.map(1..10, fn i ->
        TokenUsage.new(%{
          provider: "openai",
          model: "gpt-4",
          prompt_tokens: 50,
          completion_tokens: 50,
          total_tokens: 100,
          user_id: "user_123",
          project_id: "proj_123",
          cost: Decimal.new("0.006"),
          request_id: "req_#{i}"
        })
      end)
      
      agent = %{agent | usage_buffer: expensive_usage}
      
      data = %{
        "user_id" => "user_123",
        "project_id" => "proj_123"
      }
      
      {:ok, result, _} = TokenManagerAgent.handle_signal("get_recommendations", data, agent)
      
      assert is_list(result["recommendations"])
      assert length(result["recommendations"]) > 0
      
      # Should recommend model optimization
      model_recs = Enum.filter(result["recommendations"], &(&1.type == "model_optimization"))
      assert length(model_recs) > 0
    end
  end

  describe "pricing update signal" do
    test "updates pricing for a model" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      pricing_data = %{
        "provider" => "openai",
        "model" => "gpt-4-turbo",
        "pricing" => %{
          "prompt" => 0.01,
          "completion" => 0.03,
          "unit" => 1000
        }
      }
      
      {:ok, result, updated_agent} = TokenManagerAgent.handle_signal("update_pricing", pricing_data, agent)
      
      assert result["updated"] == true
      assert updated_agent.pricing_models["openai"]["gpt-4-turbo"].prompt == 0.01
      assert updated_agent.pricing_models["openai"]["gpt-4-turbo"].completion == 0.03
    end
  end

  describe "configuration signal" do
    test "updates manager configuration" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      config_data = %{
        "buffer_size" => 200,
        "flush_interval" => 10_000,
        "retention_days" => 60
      }
      
      {:ok, result, updated_agent} = TokenManagerAgent.handle_signal("configure_manager", config_data, agent)
      
      assert result["config"].buffer_size == 200
      assert result["config"].flush_interval == 10_000
      assert result["config"].retention_days == 60
    end

    test "preserves unspecified config values" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      original_alert_channels = agent.config.alert_channels
      
      config_data = %{"buffer_size" => 150}
      
      {:ok, _, updated_agent} = TokenManagerAgent.handle_signal("configure_manager", config_data, agent)
      
      assert updated_agent.config.buffer_size == 150
      assert updated_agent.config.alert_channels == original_alert_channels
    end
  end

  describe "status signal" do
    test "returns agent status" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      # Add some data
      agent = %{agent | 
        budgets: %{"b1" => %Budget{}, "b2" => %Budget{}},
        active_requests: %{"r1" => %{}, "r2" => %{}, "r3" => %{}},
        usage_buffer: [%TokenUsage{}, %TokenUsage{}],
        metrics: %{agent.metrics | 
          requests_tracked: 100,
          total_tokens: 50000,
          total_cost: Decimal.new("25.50")
        }
      }
      
      {:ok, status, _} = TokenManagerAgent.handle_signal("get_status", %{}, agent)
      
      assert status["healthy"] == true
      assert status["budgets_active"] == 2
      assert status["active_requests"] == 3
      assert status["buffer_size"] == 2
      assert status["total_tracked"] == 100
      assert status["total_tokens"] == 50000
      assert status["total_cost"] == "25.50"
    end
  end

  describe "scheduled tasks" do
    test "handles buffer flush message" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      # Add usage to buffer
      usage = TokenUsage.new(%{
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 100,
        completion_tokens: 50,
        user_id: "user_123",
        project_id: "proj_123",
        request_id: "req_123"
      })
      
      agent = %{agent | usage_buffer: [usage]}
      
      {:noreply, updated_agent} = TokenManagerAgent.handle_info(:flush_buffer, agent)
      
      assert updated_agent.usage_buffer == []
      assert updated_agent.metrics.last_flush != agent.metrics.last_flush
    end

    test "handles cleanup message" do
      {:ok, agent} = TokenManagerAgent.init(%{})
      
      # Add old active request
      old_timestamp = DateTime.add(DateTime.utc_now(), -7200, :second)  # 2 hours old
      agent = put_in(agent.active_requests["old_req"], %{timestamp: old_timestamp})
      agent = put_in(agent.active_requests["new_req"], %{timestamp: DateTime.utc_now()})
      
      {:noreply, updated_agent} = TokenManagerAgent.handle_info(:cleanup_old_data, agent)
      
      assert Map.has_key?(updated_agent.active_requests, "new_req")
      refute Map.has_key?(updated_agent.active_requests, "old_req")
    end
  end

  # Helper functions

  defp base_usage_data(request_id) do
    %{
      "request_id" => request_id,
      "provider" => "openai",
      "model" => "gpt-3.5-turbo",
      "prompt_tokens" => 100,
      "completion_tokens" => 50,
      "user_id" => "user_123",
      "project_id" => "proj_123",
      "metadata" => %{}
    }
  end
end
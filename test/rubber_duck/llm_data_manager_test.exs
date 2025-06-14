defmodule RubberDuck.LLMDataManagerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.LLMDataManager
  alias RubberDuck.MnesiaManager
  
  setup_all do
    # Ensure Mnesia is running and tables are created
    {:ok, _pid} = MnesiaManager.start_link()
    :ok = MnesiaManager.initialize_schema()
    
    on_exit(fn ->
      # Clean up test data
      :mnesia.clear_table(:llm_responses)
      :mnesia.clear_table(:llm_provider_status)
    end)
    
    :ok
  end
  
  setup do
    # Clean tables before each test
    :mnesia.clear_table(:llm_responses)
    :mnesia.clear_table(:llm_provider_status)
    :ok
  end
  
  describe "LLM response storage" do
    test "stores and retrieves LLM responses" do
      response_data = %{
        provider: "openai",
        model: "gpt-4",
        prompt: "What is the meaning of life?",
        response: "42",
        tokens_used: 150,
        cost: 0.003,
        latency: 1200,
        session_id: "test_session_123"
      }
      
      # Store response
      assert {:ok, response_id} = LLMDataManager.store_response(response_data)
      assert is_binary(response_id)
      
      # Retrieve response by prompt
      assert {:ok, retrieved} = LLMDataManager.get_response_by_prompt(response_data.prompt, "openai", "gpt-4")
      assert retrieved.provider == "openai"
      assert retrieved.model == "gpt-4"
      assert retrieved.response == "42"
      assert retrieved.tokens_used == 150
    end
    
    test "deduplicates responses with same prompt hash" do
      response_data = %{
        provider: "openai",
        model: "gpt-4",
        prompt: "Duplicate test prompt",
        response: "First response",
        session_id: "session_1"
      }
      
      # Store first response
      assert {:ok, response_id_1} = LLMDataManager.store_response(response_data)
      
      # Store second response with same prompt
      response_data_2 = %{response_data | response: "Second response", session_id: "session_2"}
      assert {:ok, response_id_2} = LLMDataManager.store_response(response_data_2)
      
      # Should be different response IDs (different timestamps)
      assert response_id_1 != response_id_2
      
      # Should find responses by prompt
      assert {:ok, _response} = LLMDataManager.get_response_by_prompt(response_data.prompt, "openai", "gpt-4")
    end
    
    test "retrieves response statistics" do
      # Store multiple responses
      responses = [
        %{provider: "openai", model: "gpt-4", prompt: "Test 1", response: "Response 1", tokens_used: 100, cost: 0.002},
        %{provider: "openai", model: "gpt-3.5", prompt: "Test 2", response: "Response 2", tokens_used: 80, cost: 0.001},
        %{provider: "anthropic", model: "claude", prompt: "Test 3", response: "Response 3", tokens_used: 120, cost: 0.003}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Get overall stats
      assert {:ok, stats} = LLMDataManager.get_response_stats()
      assert stats.total_responses == 3
      assert stats.total_tokens == 300
      assert stats.total_cost == 0.006
      assert Map.has_key?(stats.providers, "openai")
      assert Map.has_key?(stats.providers, "anthropic")
      
      # Get provider-specific stats
      assert {:ok, openai_stats} = LLMDataManager.get_response_stats(provider: "openai")
      assert openai_stats.total_responses == 2
      assert openai_stats.providers["openai"] == 2
    end
  end
  
  describe "provider status management" do
    test "updates and retrieves provider status" do
      provider_data = %{
        provider_name: "openai",
        status: :active,
        health_score: 95,
        total_requests: 1000,
        successful_requests: 950,
        failed_requests: 50,
        average_latency: 800,
        cost_total: 25.50,
        rate_limit_remaining: 4500,
        rate_limit_reset: :os.system_time(:millisecond) + 3600000
      }
      
      # Update provider status
      assert {:ok, _} = LLMDataManager.update_provider_status(provider_data)
      
      # Retrieve provider status
      assert {:ok, status} = LLMDataManager.get_provider_status("openai")
      assert status.provider_name == "openai"
      assert status.status == :active
      assert status.health_score == 95
      assert status.total_requests == 1000
      assert status.successful_requests == 950
    end
    
    test "gets all active provider status" do
      providers = [
        %{provider_name: "openai", status: :active, health_score: 95},
        %{provider_name: "anthropic", status: :active, health_score: 88},
        %{provider_name: "cohere", status: :inactive, health_score: 60}
      ]
      
      Enum.each(providers, &LLMDataManager.update_provider_status/1)
      
      # Should only return active providers
      assert {:ok, active_providers} = LLMDataManager.get_all_provider_status()
      assert length(active_providers) == 2
      
      provider_names = Enum.map(active_providers, & &1.provider_name)
      assert "openai" in provider_names
      assert "anthropic" in provider_names
      assert "cohere" not in provider_names
    end
  end
  
  describe "query operations" do
    test "finds similar responses" do
      prompt = "Explain quantum computing"
      
      responses = [
        %{provider: "openai", model: "gpt-4", prompt: prompt, response: "Quantum computing explanation 1"},
        %{provider: "anthropic", model: "claude", prompt: prompt, response: "Quantum computing explanation 2"},
        %{provider: "openai", model: "gpt-3.5", prompt: "Different prompt", response: "Different response"}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Find similar responses (currently exact hash matching)
      assert {:ok, similar} = LLMDataManager.find_similar_responses(prompt)
      assert length(similar) == 2
      
      response_texts = Enum.map(similar, & &1.response)
      assert "Quantum computing explanation 1" in response_texts
      assert "Quantum computing explanation 2" in response_texts
    end
    
    test "gets session responses" do
      session_id = "test_session_456"
      
      responses = [
        %{provider: "openai", model: "gpt-4", prompt: "First question", response: "First answer", session_id: session_id},
        %{provider: "openai", model: "gpt-4", prompt: "Second question", response: "Second answer", session_id: session_id},
        %{provider: "openai", model: "gpt-4", prompt: "Other session", response: "Other answer", session_id: "other_session"}
      ]
      
      Enum.each(responses, &LLMDataManager.store_response/1)
      
      # Get responses for specific session
      assert {:ok, session_responses} = LLMDataManager.get_session_responses(session_id)
      assert length(session_responses) == 2
      
      prompts = Enum.map(session_responses, & &1.prompt)
      assert "First question" in prompts
      assert "Second question" in prompts
      assert "Other session" not in prompts
    end
  end
  
  describe "cleanup operations" do
    test "cleans up expired data" do
      current_time = :os.system_time(:millisecond)
      expired_time = current_time - 1000  # 1 second ago
      
      # Store response with custom expiration
      response_data = %{
        provider: "openai",
        model: "gpt-4",
        prompt: "Test expired response",
        response: "This should be cleaned up"
      }
      
      # Manually create expired response
      response_id = "test_expired_response"
      prompt_hash = :crypto.hash(:sha256, response_data.prompt) |> Base.encode64(padding: false)
      
      expired_record = {
        :llm_responses,
        response_id,
        prompt_hash,
        response_data.provider,
        response_data.model,
        response_data.prompt,
        response_data.response,
        0, 0.0, 0,
        current_time,
        expired_time,  # Already expired
        nil,
        node()
      }
      
      # Insert directly into Mnesia
      :mnesia.transaction(fn -> :mnesia.write(expired_record) end)
      
      # Store a non-expired response
      assert {:ok, _} = LLMDataManager.store_response(%{
        provider: "openai",
        model: "gpt-4", 
        prompt: "Non-expired response",
        response: "This should remain"
      })
      
      # Run cleanup
      assert {:ok, cleanup_stats} = LLMDataManager.cleanup_expired_data()
      
      # Should have cleaned up the expired response
      assert cleanup_stats.expired_responses >= 1
      
      # Verify expired response is gone
      assert {:error, :not_found} = LLMDataManager.get_response_by_prompt("Test expired response")
      
      # Verify non-expired response remains
      assert {:ok, _} = LLMDataManager.get_response_by_prompt("Non-expired response")
    end
  end
end
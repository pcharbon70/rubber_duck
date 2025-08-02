defmodule RubberDuck.Agents.GenerationAgentJidoTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.GenerationAgent
  alias RubberDuck.Jido.Actions.Generation.CodeGenerationAction

  describe "Jido compliance" do
    test "agent can be started with BaseAgent pattern" do
      assert {:ok, agent} = GenerationAgent.start_link(id: "test_generation_agent")
      assert is_pid(agent)
    end

    test "agent responds to code generation signals" do
      {:ok, agent} = GenerationAgent.start_link(id: "test_generation_agent")
      
      # Signal-based request
      signal = %{
        "type" => "generation.code.request",
        "data" => %{
          "prompt" => "Create a simple function that adds two numbers",
          "language" => "elixir"
        }
      }
      
      assert {:ok, result} = GenerationAgent.handle_signal(agent, signal)
      assert Map.has_key?(result, "generated_code")
      assert Map.has_key?(result, "language")
    end

    test "agent can execute CodeGenerationAction directly" do
      {:ok, agent} = GenerationAgent.start_link(id: "test_generation_agent")
      
      params = %{
        prompt: "Create a simple function that adds two numbers",
        language: :elixir,
        context: %{}
      }
      
      assert {:ok, result} = GenerationAgent.cmd(agent, CodeGenerationAction, params)
      assert Map.has_key?(result, :generated_code)
      assert Map.has_key?(result, :confidence)
    end

    test "agent maintains state properly" do
      {:ok, agent} = GenerationAgent.start_link(id: "test_generation_agent")
      
      # Check initial state
      state = GenerationAgent.get_state(agent)
      assert Map.has_key?(state, :generation_cache)
      assert Map.has_key?(state, :metrics)
      assert state.metrics.tasks_completed == 0
    end
  end

  describe "generation capabilities" do
    test "supports all required generation types" do
      {:ok, agent} = GenerationAgent.start_link(id: "test_generation_agent")
      
      capabilities = GenerationAgent.get_capabilities(agent)
      
      assert :code_generation in capabilities
      assert :code_refactoring in capabilities
      assert :code_fixing in capabilities
      assert :code_completion in capabilities
      assert :documentation_generation in capabilities
    end
  end

  describe "streaming generation" do
    test "supports streaming code generation with progress signals" do
      {:ok, agent} = GenerationAgent.start_link(id: "test_generation_agent")
      
      signal = %{
        "type" => "generation.streaming.request",
        "data" => %{
          "prompt" => "Create a GenServer module",
          "language" => "elixir",
          "streaming" => true
        }
      }
      
      # Should emit progress signals during generation
      assert {:ok, %{"streaming_id" => streaming_id}} = 
        GenerationAgent.handle_signal(agent, signal)
      assert is_binary(streaming_id)
    end
  end
end
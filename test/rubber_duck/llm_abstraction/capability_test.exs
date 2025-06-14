defmodule RubberDuck.LLMAbstraction.CapabilityTest do
  use ExUnit.Case, async: true

  alias RubberDuck.LLMAbstraction.{Capability, CapabilityMatcher}

  describe "Capability creation" do
    test "creates chat_completion capability" do
      cap = Capability.chat_completion(
        version: "2.0",
        constraints: [{:max_tokens, 4096}],
        metadata: %{tier: "pro"}
      )
      
      assert cap.name == :chat_completion
      assert cap.type == :chat_completion
      assert cap.enabled == true
      assert cap.version == "2.0"
      assert cap.constraints == [{:max_tokens, 4096}]
      assert cap.metadata == %{tier: "pro"}
    end

    test "creates function_calling capability with defaults" do
      cap = Capability.function_calling()
      
      assert cap.name == :function_calling
      assert cap.version == "1.0"
      assert cap.constraints == [{:max_functions, 128}]
    end

    test "creates vision capability" do
      cap = Capability.vision(constraints: [{:max_images, 10}])
      
      assert cap.name == :vision
      assert cap.constraints == [{:max_images, 10}]
    end
  end

  describe "Capability satisfaction" do
    test "satisfies? with simple requirement" do
      cap = Capability.chat_completion()
      
      assert Capability.satisfies?(cap, :chat_completion) == true
      assert Capability.satisfies?(cap, :embeddings) == false
    end

    test "satisfies? with disabled capability" do
      cap = %Capability{
        name: :streaming,
        type: :streaming,
        enabled: false
      }
      
      assert Capability.satisfies?(cap, :streaming) == false
    end

    test "satisfies? with constraint requirements" do
      cap = Capability.chat_completion(
        constraints: [{:max_tokens, 8192}, {:max_context_window, 32768}]
      )
      
      # Satisfied - requires less than available
      assert Capability.satisfies?(cap, {:chat_completion, [{:max_tokens, 4096}]}) == true
      
      # Not satisfied - requires more than available
      assert Capability.satisfies?(cap, {:chat_completion, [{:max_tokens, 16384}]}) == false
    end

    test "satisfies? with model constraints" do
      cap = Capability.embeddings(
        constraints: [{:supported_models, ["text-embedding-ada-002", "text-embedding-3-small"]}]
      )
      
      # All required models are supported
      assert Capability.satisfies?(cap, 
        {:embeddings, [{:supported_models, ["text-embedding-ada-002"]}]}
      ) == true
      
      # Required model not supported
      assert Capability.satisfies?(cap,
        {:embeddings, [{:supported_models, ["text-embedding-3-large"]}]}
      ) == false
    end
  end

  describe "Capability utilities" do
    test "get_constraint retrieves constraint values" do
      cap = Capability.function_calling(
        constraints: [
          {:max_functions, 64},
          {:parallel_calls, true}
        ]
      )
      
      assert Capability.get_constraint(cap, :max_functions) == 64
      assert Capability.get_constraint(cap, :parallel_calls) == true
      assert Capability.get_constraint(cap, :non_existent) == nil
    end

    test "has_capability? checks list of capabilities" do
      capabilities = [
        Capability.chat_completion(),
        Capability.embeddings(),
        %Capability{name: :vision, enabled: false}
      ]
      
      assert Capability.has_capability?(capabilities, :chat_completion) == true
      assert Capability.has_capability?(capabilities, :embeddings) == true
      assert Capability.has_capability?(capabilities, :vision) == false
      assert Capability.has_capability?(capabilities, :streaming) == false
    end

    test "by_type filters capabilities by type" do
      capabilities = [
        Capability.chat_completion(),
        Capability.text_completion(),
        Capability.embeddings(),
        %Capability{name: :disabled_chat, type: :chat_completion, enabled: false}
      ]
      
      chat_caps = Capability.by_type(capabilities, :chat_completion)
      assert length(chat_caps) == 1
      assert hd(chat_caps).name == :chat_completion
    end
  end

  describe "CapabilityMatcher" do
    setup do
      provider_capabilities = %{
        provider_a: [
          Capability.chat_completion(constraints: [{:max_tokens, 4096}]),
          Capability.embeddings(),
          Capability.streaming()
        ],
        provider_b: [
          Capability.chat_completion(constraints: [{:max_tokens, 8192}]),
          Capability.function_calling(),
          Capability.vision()
        ],
        provider_c: [
          Capability.chat_completion(constraints: [{:max_tokens, 2048}]),
          Capability.text_completion()
        ]
      }
      
      {:ok, capabilities: provider_capabilities}
    end

    test "finds providers matching simple requirements", %{capabilities: caps} do
      requirements = [:chat_completion]
      matches = CapabilityMatcher.find_matching_providers(requirements, caps)
      
      assert length(matches) == 3
      assert Enum.map(matches, &elem(&1, 0)) == [:provider_a, :provider_b, :provider_c]
    end

    test "finds providers matching multiple requirements", %{capabilities: caps} do
      requirements = [:chat_completion, :function_calling]
      matches = CapabilityMatcher.find_matching_providers(requirements, caps)
      
      assert length(matches) == 1
      assert {provider, _} = hd(matches)
      assert provider == :provider_b
    end

    test "finds providers matching constraint requirements", %{capabilities: caps} do
      requirements = [{:chat_completion, [{:max_tokens, 6000}]}]
      matches = CapabilityMatcher.find_matching_providers(requirements, caps)
      
      assert length(matches) == 1
      assert {provider, _} = hd(matches)
      assert provider == :provider_b
    end

    test "returns empty list when no providers match", %{capabilities: caps} do
      requirements = [:non_existent_capability]
      matches = CapabilityMatcher.find_matching_providers(requirements, caps)
      
      assert matches == []
    end

    test "provider_satisfies? checks single provider", %{capabilities: caps} do
      provider_b_caps = caps[:provider_b]
      
      assert CapabilityMatcher.provider_satisfies?(provider_b_caps, [:chat_completion]) == true
      assert CapabilityMatcher.provider_satisfies?(provider_b_caps, [:embeddings]) == false
      assert CapabilityMatcher.provider_satisfies?(
        provider_b_caps, 
        [:chat_completion, :vision]
      ) == true
    end

    test "sorts providers by match score", %{capabilities: caps} do
      # Add a provider with more capabilities
      enhanced_caps = Map.put(caps, :provider_d, [
        Capability.chat_completion(),
        Capability.embeddings(),
        Capability.function_calling(),
        Capability.vision(),
        Capability.streaming()
      ])
      
      requirements = [:chat_completion]
      matches = CapabilityMatcher.find_matching_providers(requirements, enhanced_caps)
      
      # Provider D should be first due to more capabilities
      assert {first_provider, _} = hd(matches)
      assert first_provider == :provider_d
    end
  end
end
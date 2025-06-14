defmodule RubberDuck.LLMAbstraction.ResponseTest do
  use ExUnit.Case, async: true

  alias RubberDuck.LLMAbstraction.{Response, StreamResponse}
  alias RubberDuck.LLMAbstraction.Message

  describe "Response creation" do
    test "creates response with all fields" do
      response = Response.new(%{
        id: "test-123",
        provider: :openai,
        model: "gpt-4",
        content: "Hello!",
        role: :assistant,
        finish_reason: :stop,
        usage: %{
          prompt_tokens: 10,
          completion_tokens: 5,
          total_tokens: 15,
          cost: 0.001
        },
        metadata: %{custom: "data"},
        latency_ms: 500
      })
      
      assert response.id == "test-123"
      assert response.provider == :openai
      assert response.model == "gpt-4"
      assert response.content == "Hello!"
      assert response.role == :assistant
      assert response.finish_reason == :stop
      assert response.usage.total_tokens == 15
      assert response.metadata == %{custom: "data"}
      assert response.latency_ms == 500
    end

    test "creates response with defaults" do
      response = Response.new(%{content: "Test"})
      
      assert response.provider == :unknown
      assert response.model == "unknown"
      assert response.role == :assistant
      assert response.metadata == %{}
      assert %DateTime{} = response.created_at
    end
  end

  describe "OpenAI response parsing" do
    test "parses complete OpenAI response" do
      openai_response = %{
        "id" => "chatcmpl-123",
        "model" => "gpt-3.5-turbo",
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "The capital is Paris."
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 20,
          "completion_tokens" => 10,
          "total_tokens" => 30
        },
        "system_fingerprint" => "fp_123abc",
        "created" => 1234567890
      }
      
      response = Response.from_openai(openai_response, :openai, 250)
      
      assert response.id == "chatcmpl-123"
      assert response.provider == :openai
      assert response.model == "gpt-3.5-turbo"
      assert response.content == "The capital is Paris."
      assert response.role == :assistant
      assert response.finish_reason == :stop
      assert response.usage.prompt_tokens == 20
      assert response.usage.completion_tokens == 10
      assert response.usage.total_tokens == 30
      assert response.latency_ms == 250
      assert response.metadata.system_fingerprint == "fp_123abc"
    end

    test "handles missing fields gracefully" do
      minimal_response = %{
        "choices" => [
          %{"message" => %{"content" => "Test"}}
        ]
      }
      
      response = Response.from_openai(minimal_response)
      
      assert response.content == "Test"
      assert response.role == :assistant
      assert response.finish_reason == nil
      assert response.usage == nil
    end
  end

  describe "Anthropic response parsing" do
    test "parses complete Anthropic response" do
      anthropic_response = %{
        "id" => "msg_123",
        "model" => "claude-3-opus",
        "content" => [
          %{"type" => "text", "text" => "Hello from Claude!"}
        ],
        "stop_reason" => "end_turn",
        "usage" => %{
          "input_tokens" => 15,
          "output_tokens" => 8
        }
      }
      
      response = Response.from_anthropic(anthropic_response, 180)
      
      assert response.id == "msg_123"
      assert response.provider == :anthropic
      assert response.model == "claude-3-opus"
      assert response.content == "Hello from Claude!"
      assert response.finish_reason == :stop
      assert response.usage.prompt_tokens == 15
      assert response.usage.completion_tokens == 8
      assert response.usage.total_tokens == 23
      assert response.latency_ms == 180
    end

    test "handles different content formats" do
      # Simple array format
      response1 = Response.from_anthropic(%{
        "content" => [%{"text" => "Simple format"}]
      })
      assert response1.content == "Simple format"
      
      # Explicit type format
      response2 = Response.from_anthropic(%{
        "content" => [%{"type" => "text", "text" => "Explicit format"}]
      })
      assert response2.content == "Explicit format"
    end
  end

  describe "Response utilities" do
    test "error? detects error responses" do
      error_response = Response.new(%{finish_reason: :error})
      normal_response = Response.new(%{finish_reason: :stop})
      
      assert Response.error?(error_response) == true
      assert Response.error?(normal_response) == false
    end

    test "truncated? detects length-limited responses" do
      truncated = Response.new(%{finish_reason: :length})
      complete = Response.new(%{finish_reason: :stop})
      
      assert Response.truncated?(truncated) == true
      assert Response.truncated?(complete) == false
    end

    test "function_call? detects function call responses" do
      function_response = Response.new(%{finish_reason: :function_call})
      normal_response = Response.new(%{finish_reason: :stop})
      
      assert Response.function_call?(function_response) == true
      assert Response.function_call?(normal_response) == false
    end

    test "total_tokens returns token count" do
      response_with_usage = Response.new(%{
        usage: %{total_tokens: 42}
      })
      response_without_usage = Response.new(%{})
      
      assert Response.total_tokens(response_with_usage) == 42
      assert Response.total_tokens(response_without_usage) == 0
    end

    test "calculate_cost with pricing info" do
      response = Response.new(%{
        usage: %{
          prompt_tokens: 1000,
          completion_tokens: 500,
          total_tokens: 1500
        }
      })
      
      pricing = %{
        input: 0.01,  # $0.01 per 1M tokens
        output: 0.03  # $0.03 per 1M tokens
      }
      
      cost = Response.calculate_cost(response, pricing)
      assert_in_delta cost, 0.000025, 0.000001
    end

    test "calculate_cost returns embedded cost if available" do
      response = Response.new(%{
        usage: %{cost: 0.05}
      })
      
      assert Response.calculate_cost(response) == 0.05
    end

    test "to_message converts response to assistant message" do
      response = Response.new(%{
        content: "I can help!",
        metadata: %{model: "gpt-4"}
      })
      
      message = Response.to_message(response)
      
      assert %Message.Text{} = message
      assert message.role == :assistant
      assert message.content == "I can help!"
      assert message.metadata == %{model: "gpt-4"}
    end
  end

  describe "StreamResponse" do
    test "accumulates content from chunks" do
      stream = StreamResponse.new(:openai, "gpt-4", id: "stream-123")
      
      chunk1 = %{
        "choices" => [
          %{"delta" => %{"content" => "Hello"}}
        ]
      }
      
      chunk2 = %{
        "choices" => [
          %{"delta" => %{"content" => " world!"}}
        ]
      }
      
      stream = stream
      |> StreamResponse.add_chunk(chunk1)
      |> StreamResponse.add_chunk(chunk2)
      
      assert stream.accumulated_content == "Hello world!"
      assert length(stream.chunks) == 2
    end

    test "converts to final response" do
      stream = StreamResponse.new(:openai, "gpt-3.5-turbo")
      |> StreamResponse.add_chunk(%{
        "choices" => [%{"delta" => %{"content" => "Streamed response"}}]
      })
      
      # Simulate some time passing
      Process.sleep(10)
      
      response = StreamResponse.to_response(stream, :stop)
      
      assert response.content == "Streamed response"
      assert response.provider == :openai
      assert response.model == "gpt-3.5-turbo"
      assert response.finish_reason == :stop
      assert response.latency_ms >= 10
    end

    test "extracts usage from final chunk" do
      stream = StreamResponse.new(:openai, "gpt-4")
      |> StreamResponse.add_chunk(%{
        "choices" => [%{"delta" => %{"content" => "Test"}}]
      })
      |> StreamResponse.add_chunk(%{
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 5,
          "total_tokens" => 15
        }
      })
      
      response = StreamResponse.to_response(stream)
      
      assert response.usage.prompt_tokens == 10
      assert response.usage.completion_tokens == 5
      assert response.usage.total_tokens == 15
    end

    test "handles Anthropic streaming format" do
      stream = StreamResponse.new(:anthropic, "claude-3")
      |> StreamResponse.add_chunk(%{
        "delta" => %{"text" => "Claude "}
      })
      |> StreamResponse.add_chunk(%{
        "delta" => %{"text" => "response"}
      })
      
      assert stream.accumulated_content == "Claude response"
    end
  end
end
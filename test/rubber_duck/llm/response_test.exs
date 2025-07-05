defmodule RubberDuck.LLM.ResponseTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.LLM.Response
  
  describe "from_provider/2 - OpenAI" do
    test "parses OpenAI response correctly" do
      raw_response = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "created" => 1677652288,
        "model" => "gpt-3.5-turbo",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Hello! How can I help you?"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 8,
          "total_tokens" => 18
        },
        "system_fingerprint" => "fp_123"
      }
      
      response = Response.from_provider(:openai, raw_response)
      
      assert response.id == "chatcmpl-123"
      assert response.model == "gpt-3.5-turbo"
      assert response.provider == :openai
      assert length(response.choices) == 1
      
      choice = hd(response.choices)
      assert choice.index == 0
      assert choice.message["content"] == "Hello! How can I help you?"
      assert choice.finish_reason == "stop"
      
      assert response.usage.prompt_tokens == 10
      assert response.usage.completion_tokens == 8
      assert response.usage.total_tokens == 18
      
      assert response.metadata.system_fingerprint == "fp_123"
    end
    
    test "handles missing usage data" do
      raw_response = %{
        "id" => "test",
        "model" => "gpt-4",
        "created" => 1677652288,
        "choices" => [
          %{
            "index" => 0,
            "message" => %{"role" => "assistant", "content" => "Test"},
            "finish_reason" => "stop"
          }
        ]
      }
      
      response = Response.from_provider(:openai, raw_response)
      
      assert response.usage == nil
    end
  end
  
  describe "from_provider/2 - Anthropic" do
    test "parses Anthropic response correctly" do
      raw_response = %{
        "id" => "msg_123",
        "type" => "message",
        "model" => "claude-3-sonnet",
        "content" => [
          %{
            "type" => "text",
            "text" => "Hello! I'm Claude."
          }
        ],
        "stop_reason" => "end_turn",
        "stop_sequence" => nil,
        "usage" => %{
          "input_tokens" => 12,
          "output_tokens" => 6
        }
      }
      
      response = Response.from_provider(:anthropic, raw_response)
      
      assert response.id == "msg_123"
      assert response.model == "claude-3-sonnet"
      assert response.provider == :anthropic
      
      choice = hd(response.choices)
      assert choice.message["content"] == "Hello! I'm Claude."
      
      assert response.usage.prompt_tokens == 12
      assert response.usage.completion_tokens == 6
      assert response.usage.total_tokens == 18
    end
    
    test "handles multiple content blocks" do
      raw_response = %{
        "id" => "msg_123",
        "model" => "claude-3-opus",
        "content" => [
          %{"type" => "text", "text" => "Part 1."},
          %{"type" => "text", "text" => "Part 2."}
        ],
        "usage" => %{"input_tokens" => 10, "output_tokens" => 10}
      }
      
      response = Response.from_provider(:anthropic, raw_response)
      
      choice = hd(response.choices)
      assert choice.message["content"] == "Part 1.\nPart 2."
    end
  end
  
  describe "get_content/1" do
    test "extracts content from response" do
      response = %Response{
        choices: [
          %{
            index: 0,
            message: %{"content" => "Test content"},
            finish_reason: "stop"
          }
        ]
      }
      
      assert Response.get_content(response) == "Test content"
    end
    
    test "returns nil for empty choices" do
      response = %Response{choices: []}
      
      assert Response.get_content(response) == nil
    end
    
    test "handles atom keys in message" do
      response = %Response{
        choices: [
          %{
            index: 0,
            message: %{content: "Atom key content"},
            finish_reason: "stop"
          }
        ]
      }
      
      assert Response.get_content(response) == "Atom key content"
    end
  end
  
  describe "get_messages/1" do
    test "returns all messages from choices" do
      response = %Response{
        choices: [
          %{
            index: 0,
            message: %{"content" => "First"},
            finish_reason: "stop"
          },
          %{
            index: 1,
            message: %{"content" => "Second"},
            finish_reason: "stop"
          }
        ]
      }
      
      messages = Response.get_messages(response)
      
      assert length(messages) == 2
      assert hd(messages)["content"] == "First"
    end
  end
  
  describe "calculate_cost/1" do
    test "calculates cost for OpenAI GPT-4" do
      response = %Response{
        provider: :openai,
        model: "gpt-4",
        usage: %{
          prompt_tokens: 1000,
          completion_tokens: 500,
          total_tokens: 1500
        }
      }
      
      cost = Response.calculate_cost(response)
      
      # GPT-4: $0.03/1K prompt + $0.06/1K completion
      expected = (1000/1000 * 0.03) + (500/1000 * 0.06)
      assert_in_delta cost, expected, 0.001
    end
    
    test "calculates cost for Anthropic Claude" do
      response = %Response{
        provider: :anthropic,
        model: "claude-3-sonnet",
        usage: %{
          prompt_tokens: 2000,
          completion_tokens: 1000,
          total_tokens: 3000
        }
      }
      
      cost = Response.calculate_cost(response)
      
      # Claude 3 Sonnet: $0.003/1K prompt + $0.015/1K completion
      expected = (2000/1000 * 0.003) + (1000/1000 * 0.015)
      assert_in_delta cost, expected, 0.001
    end
    
    test "returns 0 for missing usage data" do
      response = %Response{
        provider: :openai,
        model: "gpt-4",
        usage: nil
      }
      
      assert Response.calculate_cost(response) == 0.0
    end
  end
end
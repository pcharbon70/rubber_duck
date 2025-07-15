defmodule RubberDuck.CoTFunctionClauseFixTest do
  use ExUnit.Case
  
  alias RubberDuck.Commands.Handlers.Conversation
  
  describe "extract_cot_response function" do
    test "handles session with result field containing final_answer" do
      # Mock CoT session with result field
      cot_session = %{
        id: "test-session",
        result: %{
          final_answer: "This is the final answer"
        },
        steps: [],
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      }
      
      # Use reflection to access the private function
      result = apply(Conversation, :extract_cot_response, [cot_session])
      
      assert result == "This is the final answer"
    end
    
    test "handles session with direct result string" do
      # Mock CoT session with direct result string
      cot_session = %{
        id: "test-session",
        result: "This is the direct result",
        steps: [],
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      }
      
      # Use reflection to access the private function
      result = apply(Conversation, :extract_cot_response, [cot_session])
      
      assert result == "This is the direct result"
    end
    
    test "handles session with steps containing format_output" do
      # Mock CoT session with steps
      cot_session = %{
        id: "test-session",
        result: nil,
        steps: [
          %{name: :understand_context, result: "Understanding context"},
          %{name: :format_output, result: "Final formatted output"}
        ],
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      }
      
      # Use reflection to access the private function
      result = apply(Conversation, :extract_cot_response, [cot_session])
      
      assert result == "Final formatted output"
    end
    
    test "handles session with steps without format_output" do
      # Mock CoT session with steps but no format_output
      cot_session = %{
        id: "test-session",
        result: nil,
        steps: [
          %{name: :understand_context, result: "Understanding context"},
          %{name: :generate_response, result: "Generated response"}
        ],
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      }
      
      # Use reflection to access the private function
      result = apply(Conversation, :extract_cot_response, [cot_session])
      
      assert result == "Generated response"
    end
    
    test "handles fallback case" do
      # Mock CoT session with no usable data
      cot_session = %{
        id: "test-session",
        result: nil,
        steps: [],
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      }
      
      # Use reflection to access the private function
      result = apply(Conversation, :extract_cot_response, [cot_session])
      
      assert result == "I apologize, but I couldn't generate a proper response."
    end
  end
end
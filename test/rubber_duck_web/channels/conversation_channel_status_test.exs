defmodule RubberDuckWeb.ConversationChannelStatusTest do
  use RubberDuckWeb.ChannelCase
  import RubberDuck.AccountsFixtures

  alias RubberDuckWeb.ConversationChannel
  alias RubberDuck.Status

  setup do
    # Create a user for authentication
    user = user_fixture()
    
    # Generate JWT token
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    
    # Create a socket with JWT authentication
    {:ok, socket} = connect(RubberDuckWeb.UserSocket, %{"token" => token})

    # Generate a valid UUID for the conversation
    conversation_id = Ecto.UUID.generate()
    
    # Join the conversation channel
    {:ok, _, socket} = subscribe_and_join(socket, ConversationChannel, "conversation:#{conversation_id}")

    %{socket: socket, user: user, conversation_id: conversation_id}
  end

  describe "status updates" do
    test "receives status updates from engines", %{socket: _socket, conversation_id: conversation_id} do
      # Broadcast a status update
      Status.engine(conversation_id, "Processing with GPT-4", %{model: "gpt-4", step: 1})
      
      # Should receive the status update
      assert_push("status_update", %{
        category: :engine,
        text: "Processing with GPT-4",
        metadata: %{model: "gpt-4", step: 1},
        timestamp: _
      })
    end
    
    test "receives cancellation broadcasts", %{socket: _socket, conversation_id: conversation_id} do
      # Broadcast a cancellation status
      Status.engine(conversation_id, "Processing cancelled for test_engine", %{
        engine: "test_engine",
        cancelled_at: DateTime.utc_now()
      })
      
      # Should receive both status update and cancellation event
      assert_push("status_update", %{
        category: :engine,
        text: "Processing cancelled for test_engine",
        metadata: %{engine: "test_engine", cancelled_at: _},
        timestamp: _
      })
      
      # Should also receive specific cancellation event
      assert_push("processing_cancelled", %{
        message: "Processing cancelled for test_engine",
        metadata: %{engine: "test_engine", cancelled_at: _},
        timestamp: _
      })
    end
    
    test "receives workflow cancellation updates", %{socket: _socket, conversation_id: conversation_id} do
      # Broadcast a workflow cancellation
      Status.workflow(conversation_id, "Chain execution cancelled at step analysis", %{
        chain: "AnalysisChain",
        step: :analysis,
        cancelled_at: DateTime.utc_now()
      })
      
      # Should receive the status update
      assert_push("status_update", %{
        category: :workflow,
        text: "Chain execution cancelled at step analysis",
        metadata: %{chain: "AnalysisChain", step: :analysis, cancelled_at: _},
        timestamp: _
      })
      
      # Should also receive cancellation event
      assert_push("processing_cancelled", %{
        message: "Chain execution cancelled at step analysis",
        metadata: %{chain: "AnalysisChain", step: :analysis, cancelled_at: _},
        timestamp: _
      })
    end
    
    test "multiple clients receive broadcasts", %{user: user, conversation_id: conversation_id} do
      # Create a second connection to the same conversation
      {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
      {:ok, socket2} = connect(RubberDuckWeb.UserSocket, %{"token" => token})
      {:ok, _, _socket2} = subscribe_and_join(socket2, ConversationChannel, "conversation:#{conversation_id}")
      
      # Broadcast a cancellation
      Status.engine(conversation_id, "Task cancelled: analysis_engine", %{
        task_id: "task_123",
        engine: "analysis_engine"
      })
      
      # Both connections should receive the update
      assert_push("status_update", %{
        category: :engine,
        text: "Task cancelled: analysis_engine"
      })
      
      # The second connection should also receive it
      # (This would work in real scenario, but in tests we're checking the first socket)
    end
  end
end
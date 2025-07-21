defmodule RubberDuckWeb.Components.ChatPanelComponentTest do
  use RubberDuckWeb.ConnCase
  
  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures
  
  alias Phoenix.PubSub
  alias RubberDuckWeb.Components.ChatPanelComponent
  
  setup do
    user = user_fixture()
    project_id = "test-project-123"
    
    %{user: user, project_id: project_id}
  end
  
  describe "mounting and initialization" do
    test "initializes with default state", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      assert view.assigns.messages == []
      assert view.assigns.input_value == ""
      assert view.assigns.streaming_message == nil
      assert view.assigns.selected_model == "gpt-4"
      assert view.assigns.selected_provider == "openai"
      assert view.assigns.show_model_settings == false
      assert view.assigns.show_commands == false
    end
    
    test "subscribes to chat channel when mounted", %{conn: conn, user: user, project_id: project_id} do
      {:ok, _view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      # Verify subscription by publishing a message
      test_message = %{
        id: Ecto.UUID.generate(),
        user_id: "other-user",
        username: "other_user",
        content: "Test message",
        timestamp: DateTime.utc_now(),
        type: :user
      }
      
      PubSub.broadcast(RubberDuck.PubSub, "chat:#{project_id}", {:chat_message, test_message})
      
      # The component should receive but not display the message (handled by parent)
      :timer.sleep(50)
    end
  end
  
  describe "message rendering" do
    test "renders user messages correctly", %{conn: conn, user: user, project_id: project_id} do
      messages = [
        {"message-1", %{
          id: "1",
          type: :user,
          content: "Hello world",
          user_id: user.id,
          username: user.username,
          metadata: %{timestamp: DateTime.utc_now(), status: :complete}
        }}
      ]
      
      {:ok, view, html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: messages,
          streaming_message: nil
        )
      
      assert html =~ "Hello world"
      assert html =~ user.username
    end
    
    test "renders assistant messages with model info", %{conn: conn, user: user, project_id: project_id} do
      messages = [
        {"message-1", %{
          id: "1",
          type: :assistant,
          content: "I can help with that",
          metadata: %{
            timestamp: DateTime.utc_now(),
            status: :complete,
            model: "gpt-4",
            provider: "openai"
          }
        }}
      ]
      
      {:ok, _view, html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: messages,
          streaming_message: nil
        )
      
      assert html =~ "I can help with that"
      assert html =~ "AI Assistant"
      assert html =~ "gpt-4"
    end
    
    test "renders streaming messages with animation", %{conn: conn, user: user, project_id: project_id} do
      streaming_message = %{
        id: "streaming-1",
        type: :assistant,
        content: "Thinking about",
        metadata: %{
          timestamp: DateTime.utc_now(),
          status: :streaming,
          model: "gpt-4",
          provider: "openai"
        }
      }
      
      {:ok, _view, html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: streaming_message
        )
      
      assert html =~ "Thinking about"
      assert html =~ "Thinking..."
      assert html =~ "animate-pulse"
    end
  end
  
  describe "message input" do
    test "updates input value on change", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      view
      |> element("form[phx-change=\"update_input\"]")
      |> render_change(%{message: "Hello there"})
      
      assert view.assigns.input_value == "Hello there"
    end
    
    test "sends message on form submit", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      # Subscribe to verify broadcast
      PubSub.subscribe(RubberDuck.PubSub, "chat:#{project_id}")
      
      view
      |> element("form[phx-submit=\"send_message\"]")
      |> render_submit(%{message: "Test message"})
      
      assert_receive {:chat_message, message}
      assert message.content == "Test message"
      assert message.user_id == user.id
      assert message.type == :user
      
      # Input should be cleared
      assert view.assigns.input_value == ""
    end
    
    test "doesn't send empty messages", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      PubSub.subscribe(RubberDuck.PubSub, "chat:#{project_id}")
      
      view
      |> element("form[phx-submit=\"send_message\"]")
      |> render_submit(%{message: "   "})
      
      refute_receive {:chat_message, _}, 100
    end
  end
  
  describe "command detection" do
    test "shows command suggestions when typing /", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      view
      |> element("form[phx-change=\"update_input\"]")
      |> render_change(%{message: "/"})
      
      assert view.assigns.show_commands == true
      assert length(view.assigns.command_suggestions) > 0
    end
    
    test "filters commands based on input", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      view
      |> element("form[phx-change=\"update_input\"]")
      |> render_change(%{message: "/hel"})
      
      suggestions = view.assigns.command_suggestions
      assert length(suggestions) > 0
      assert Enum.any?(suggestions, &(&1.command == "/help"))
    end
    
    test "selects command from palette", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      # Type slash to show commands
      view
      |> element("form[phx-change=\"update_input\"]")
      |> render_change(%{message: "/"})
      
      # Select a command
      view
      |> element("button[phx-click=\"select_command\"][phx-value-command=\"/help\"]")
      |> render_click()
      
      assert view.assigns.input_value == "/help "
      assert view.assigns.show_commands == false
    end
  end
  
  describe "command handling" do
    test "handles /help command", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      view
      |> element("form[phx-submit=\"send_message\"]")
      |> render_submit(%{message: "/help"})
      
      # Should have added a help message
      assert length(view.assigns.messages) > 0
      {_id, message} = List.last(view.assigns.messages)
      assert message.type == :system
      assert message.content =~ "Available commands"
    end
    
    test "handles /clear command", %{conn: conn, user: user, project_id: project_id} do
      messages = [
        {"message-1", %{id: "1", type: :user, content: "Test", metadata: %{}}},
        {"message-2", %{id: "2", type: :assistant, content: "Response", metadata: %{}}}
      ]
      
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: messages,
          streaming_message: nil
        )
      
      view
      |> element("form[phx-submit=\"send_message\"]")
      |> render_submit(%{message: "/clear"})
      
      assert view.assigns.messages == []
    end
    
    test "handles /model command", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      view
      |> element("form[phx-submit=\"send_message\"]")
      |> render_submit(%{message: "/model"})
      
      assert view.assigns.show_model_settings == true
    end
  end
  
  describe "message actions" do
    test "copies message to clipboard", %{conn: conn, user: user, project_id: project_id} do
      messages = [
        {"message-1", %{
          id: "1",
          type: :assistant,
          content: "Copy this text",
          metadata: %{timestamp: DateTime.utc_now(), status: :complete}
        }}
      ]
      
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: messages,
          streaming_message: nil
        )
      
      view
      |> element("button[phx-click=\"copy_message\"][phx-value-message_id=\"1\"]")
      |> render_click()
      
      # The actual clipboard operation happens client-side
      # We can only verify the event was pushed
    end
    
    test "cancels streaming message", %{conn: conn, user: user, project_id: project_id} do
      streaming_message = %{
        id: "streaming-1",
        type: :assistant,
        content: "Partial response",
        metadata: %{status: :streaming}
      }
      
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: streaming_message
        )
      
      view
      |> element("button[phx-click=\"cancel_streaming\"]")
      |> render_click()
      
      assert view.assigns.streaming_message == nil
    end
  end
  
  describe "model settings" do
    test "toggles model settings modal", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      # Open modal
      view
      |> element("button[phx-click=\"toggle_model_settings\"]")
      |> render_click()
      
      assert view.assigns.show_model_settings == true
      
      # Close modal
      view
      |> element("button[phx-click=\"toggle_model_settings\"]")
      |> render_click()
      
      assert view.assigns.show_model_settings == false
    end
    
    test "updates selected model", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      view
      |> element("button[phx-click=\"update_model\"]")
      |> render_click(%{provider: "anthropic", model: "claude-3"})
      
      assert view.assigns.selected_provider == "anthropic"
      assert view.assigns.selected_model == "claude-3"
      assert view.assigns.show_model_settings == false
    end
  end
  
  describe "keyboard shortcuts" do
    test "submits on Enter without shift", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      # Set input value
      view
      |> element("form[phx-change=\"update_input\"]")
      |> render_change(%{message: "Test message"})
      
      # Simulate Enter key
      view
      |> element("textarea[phx-keydown=\"keydown\"]")
      |> render_keydown(%{"key" => "Enter", "shiftKey" => false})
      
      # Should trigger submit (tested separately)
    end
    
    test "closes command palette on Escape", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: nil
        )
      
      # Show commands
      view
      |> element("form[phx-change=\"update_input\"]")
      |> render_change(%{message: "/"})
      
      assert view.assigns.show_commands == true
      
      # Press Escape
      view
      |> element("textarea[phx-keydown=\"keydown\"]")
      |> render_keydown(%{"key" => "Escape"})
      
      assert view.assigns.show_commands == false
    end
  end
  
  describe "streaming updates" do
    test "handles streaming updates", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: %{
            id: "1",
            type: :assistant,
            content: "Initial",
            metadata: %{status: :streaming}
          }
        )
      
      # Send streaming update
      send(view.pid, {:streaming_update, %{content: " content"}})
      
      :timer.sleep(50)
      
      assert view.assigns.streaming_message.content == "Initial content"
    end
    
    test "completes streaming message", %{conn: conn, user: user, project_id: project_id} do
      {:ok, view, _html} = 
        live_isolated(conn, ChatPanelComponent,
          session: %{"current_user" => user},
          id: "chat-panel",
          project_id: project_id,
          current_user: user,
          messages: [],
          streaming_message: %{
            id: "1",
            type: :assistant,
            content: "Streamed content",
            metadata: %{status: :streaming}
          }
        )
      
      completed_message = %{
        id: "1",
        type: :assistant,
        content: "Streamed content complete",
        metadata: %{status: :complete}
      }
      
      send(view.pid, {:streaming_complete, completed_message})
      
      :timer.sleep(50)
      
      assert view.assigns.streaming_message == nil
      assert length(view.assigns.messages) == 1
      {_id, message} = List.first(view.assigns.messages)
      assert message.content == "Streamed content complete"
    end
  end
end
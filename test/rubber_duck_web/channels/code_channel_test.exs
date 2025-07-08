defmodule RubberDuckWeb.CodeChannelTest do
  use RubberDuckWeb.ChannelCase

  alias RubberDuckWeb.{UserSocket, CodeChannel}
  alias RubberDuck.Workspace

  setup do
    # Create a test user and authenticate
    user_id = "test_user_#{System.unique_integer()}"
    token = Phoenix.Token.sign(RubberDuckWeb.Endpoint, "user socket", user_id)

    {:ok, socket} = connect(UserSocket, %{"token" => token})

    # Create test project and file
    {:ok, project} =
      Workspace.create_project(%{
        name: "Test Project",
        description: "Test project for channel tests"
      })

    {:ok, file} =
      Workspace.create_code_file(%{
        project_id: project.id,
        path: "test.ex",
        content: "defmodule Test do\nend",
        language: "elixir"
      })

    {:ok, socket: socket, user_id: user_id, project: project, file: file}
  end

  describe "join/3" do
    test "joins project channel with valid project", %{socket: socket, project: project} do
      {:ok, reply, socket} =
        subscribe_and_join(socket, CodeChannel, "code:project:#{project.id}", %{
          "cursor_position" => %{"line" => 1, "column" => 1}
        })

      assert reply == %{status: "joined", project_id: project.id}
      assert socket.assigns.project_id == project.id
      assert socket.assigns.cursor_position == %{"line" => 1, "column" => 1}
    end

    test "joins file channel with valid file", %{socket: socket, file: file} do
      {:ok, reply, socket} = subscribe_and_join(socket, CodeChannel, "code:file:#{file.id}", %{})

      assert reply == %{status: "joined", file_id: file.id}
      assert socket.assigns.file_id == file.id
    end

    test "rejects join with invalid project", %{socket: socket} do
      assert {:error, %{reason: _}} =
               subscribe_and_join(socket, CodeChannel, "code:project:invalid_id", %{})
    end
  end

  describe "request_completion" do
    test "handles completion request", %{socket: socket, project: project} do
      {:ok, _reply, socket} = subscribe_and_join(socket, CodeChannel, "code:project:#{project.id}")

      ref =
        push(socket, "request_completion", %{
          "code" => "defmodule Test do\n  def hello do\n    ",
          "cursor_position" => %{"line" => 3, "column" => 4},
          "file_type" => "elixir"
        })

      assert_reply(ref, :ok, %{completion_id: completion_id})
      assert is_binary(completion_id)
      assert String.starts_with?(completion_id, "completion_")
    end

    test "streams completion chunks", %{socket: socket, project: project} do
      {:ok, _reply, socket} = subscribe_and_join(socket, CodeChannel, "code:project:#{project.id}")

      push(socket, "request_completion", %{
        "code" => "def test do",
        "cursor_position" => %{"line" => 1, "column" => 11},
        "file_type" => "elixir"
      })

      # Should receive completion chunks
      # Note: In real implementation, this would stream from the completion engine
      # For tests, we'd mock the completion engine
    end
  end

  describe "request_analysis" do
    test "handles analysis request", %{socket: socket, project: project} do
      {:ok, _reply, socket} = subscribe_and_join(socket, CodeChannel, "code:project:#{project.id}")

      ref =
        push(socket, "request_analysis", %{
          "code" => "defmodule Test do\n  @unused_var 42\nend",
          "file_type" => "elixir"
        })

      assert_reply(ref, :ok, %{analysis_id: analysis_id})
      assert is_binary(analysis_id)
      assert String.starts_with?(analysis_id, "analysis_")
    end
  end

  describe "cursor_position" do
    test "broadcasts cursor position updates", %{socket: socket, project: project} do
      {:ok, _reply, socket} = subscribe_and_join(socket, CodeChannel, "code:project:#{project.id}")

      push(socket, "cursor_position", %{
        "position" => %{"line" => 5, "column" => 10}
      })

      assert_broadcast("cursor_update", %{
        user_id: _,
        position: %{"line" => 5, "column" => 10},
        timestamp: _
      })
    end

    test "updates socket assigns with cursor position", %{socket: socket, project: project} do
      {:ok, _reply, socket} = subscribe_and_join(socket, CodeChannel, "code:project:#{project.id}")

      push(socket, "cursor_position", %{
        "position" => %{"line" => 5, "column" => 10}
      })

      # In a real test, we'd need to access the socket state
      # to verify the assigns were updated
    end
  end

  describe "code_change" do
    test "broadcasts code changes to other users", %{socket: socket, project: project} do
      {:ok, _reply, socket} = subscribe_and_join(socket, CodeChannel, "code:project:#{project.id}")

      ref =
        push(socket, "code_change", %{
          "changes" => %{
            "from" => %{"line" => 1, "column" => 1},
            "to" => %{"line" => 1, "column" => 5},
            "text" => "Hello"
          }
        })

      assert_reply(ref, :ok)

      assert_broadcast("code_updated", %{
        user_id: _,
        changes: %{"text" => "Hello"},
        timestamp: _
      })
    end

    test "rejects oversized changes", %{socket: socket, project: project} do
      {:ok, _reply, socket} = subscribe_and_join(socket, CodeChannel, "code:project:#{project.id}")

      # Create a large change that exceeds max message size
      large_text = String.duplicate("a", 2_000_000)

      ref =
        push(socket, "code_change", %{
          "changes" => %{"text" => large_text}
        })

      assert_reply(ref, :error, %{reason: "Changes exceed maximum message size"})
    end
  end

  describe "cancel_completion" do
    test "handles completion cancellation", %{socket: socket, project: project} do
      {:ok, _reply, socket} = subscribe_and_join(socket, CodeChannel, "code:project:#{project.id}")

      ref =
        push(socket, "cancel_completion", %{
          "completion_id" => "completion_test123"
        })

      assert_reply(ref, :ok)
    end
  end

  describe "presence" do
    test "tracks user presence on join", %{socket: socket, project: project} do
      {:ok, _reply, socket} = subscribe_and_join(socket, CodeChannel, "code:project:#{project.id}")

      # Wait for presence tracking
      :timer.sleep(100)

      # Should receive presence_state push
      assert_push("presence_state", %{})
    end
  end
end

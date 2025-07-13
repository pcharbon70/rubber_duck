defmodule RubberDuck.CLIClient.ConversationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  alias RubberDuck.CLIClient.Main

  describe "conversation command parsing" do
    test "shows help for conversation command" do
      output = capture_io(fn ->
        try do
          Main.main(["help", "conversation"])
        catch
          :exit, _ -> :ok
        end
      end)
      
      assert output =~ "Manage AI conversations"
      assert output =~ "SUBCOMMANDS"
    end

    test "lists conversation subcommands" do
      output = capture_io(fn ->
        try do
          Main.main(["help", "conversation"])
        catch
          :exit, _ -> :ok
        end
      end)
      
      assert output =~ "start"
      assert output =~ "list"
      assert output =~ "show"
      assert output =~ "send"
      assert output =~ "delete"
      assert output =~ "chat"
    end

    test "shows help for conversation start subcommand" do
      output = capture_io(fn ->
        try do
          Main.main(["help", "conversation", "start"])
        catch
          :exit, _ -> :ok
        end
      end)
      
      assert output =~ "Start a new conversation"
      assert output =~ "TITLE"
      assert output =~ "--type"
    end
  end
end
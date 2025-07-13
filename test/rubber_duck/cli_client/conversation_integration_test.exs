defmodule RubberDuck.CLIClient.ConversationIntegrationTest do
  use ExUnit.Case, async: false
  
  import ExUnit.CaptureIO
  alias RubberDuck.CLIClient.Main
  
  @moduletag :integration
  
  describe "conversation command integration" do
    test "conversation list command requires authentication" do
      # Ensure no auth is configured for this test
      temp_dir = System.tmp_dir!()
      config_path = Path.join(temp_dir, ".rubber_duck_test_#{:rand.uniform(10000)}")
      
      # Capture all output  
      output = capture_io(fn ->
        capture_io(:stderr, fn ->
          try do
            System.put_env("HOME", temp_dir)
            System.put_env("RUBBER_DUCK_CONFIG_DIR", config_path)
            Main.main(["conversation", "list"])
          catch
            :exit, _ -> :ok
          end
        end) |> IO.write()
      end)
      
      # The conversation command should be recognized
      # But it should fail with auth error since no auth is configured
      assert output =~ "Not authenticated" || output =~ "Cannot connect"
    end
    
    test "conversation subcommands show in help" do
      output = capture_io(fn ->
        try do
          Main.main(["help", "conversation"])
        catch
          :exit, _ -> :ok
        end
      end)
      
      assert output =~ "Manage AI conversations"
      assert output =~ "start"
      assert output =~ "list"
      assert output =~ "show"
      assert output =~ "send"
      assert output =~ "delete"
      assert output =~ "chat"
    end
    
    test "conversation start help shows options" do
      output = capture_io(fn ->
        try do
          Main.main(["help", "conversation", "start"])
        catch
          :exit, _ -> :ok
        end
      end)
      
      assert output =~ "Start a new conversation"
      assert output =~ "--type"
      assert output =~ "general, coding, debugging"
    end
    
    test "conversation chat help shows interactive mode info" do
      output = capture_io(fn ->
        try do
          Main.main(["help", "conversation", "chat"])
        catch
          :exit, _ -> :ok
        end
      end)
      
      assert output =~ "Enter interactive chat mode"
      assert output =~ "--title"
    end
  end
end
defmodule RubberDuck.TowerConfigTest do
  use ExUnit.Case, async: false
  
  describe "Tower reporter configuration" do
    test "Tower reporters should be configured as module atoms, not keyword lists" do
      # Arrange
      current_reporters = Application.get_env(:tower, :reporters, [])
      
      # Act - Check if reporters are properly configured
      invalid_reporters = Enum.filter(current_reporters, fn reporter ->
        # Reporters should be module atoms or maps with :module key
        # Not keyword lists
        is_list(reporter) and Keyword.keyword?(reporter)
      end)
      
      # Assert - This test should FAIL in the current state
      assert invalid_reporters == [], 
        "Found invalid reporter configurations: #{inspect(invalid_reporters)}. " <>
        "Reporters should be module atoms like Tower.LogReporter, not keyword lists."
    end
  end
end
defmodule RubberDuck.TowerConfigTest do
  use ExUnit.Case, async: false
  
  describe "Tower reporter configuration" do
    test "Tower reporters should be configured as module atoms, not keyword lists" do
      # Arrange
      current_reporters = Application.get_env(:tower, :reporters, [])
      
      # Act - Check if reporters are properly configured
      invalid_reporters = Enum.filter(current_reporters, fn reporter ->
        # Reporters should be module atoms
        # Not keyword lists or maps
        not is_atom(reporter) or (is_list(reporter) and Keyword.keyword?(reporter))
      end)
      
      # Assert
      assert invalid_reporters == [], 
        "Found invalid reporter configurations: #{inspect(invalid_reporters)}. " <>
        "Reporters should be module atoms like Tower.LogReporter."
    end
    
    test "Tower reporters should all be valid module atoms" do
      # Arrange
      current_reporters = Application.get_env(:tower, :reporters, [])
      
      # Act - Check each reporter is a valid module atom
      valid_reporters = Enum.all?(current_reporters, fn reporter ->
        is_atom(reporter) and Code.ensure_loaded?(reporter)
      end)
      
      # Assert
      assert valid_reporters, "All Tower reporters should be valid module atoms that can be loaded"
    end
  end
end
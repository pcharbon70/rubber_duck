defmodule RubberDuck.EngineSystem.Transformers.ValidateEnginesTest do
  use ExUnit.Case, async: true

  # Test duplicate names
  test "raises compile error for duplicate engine names" do
    assert_raise RuntimeError, ~r/Duplicate engine names found/, fn ->
      defmodule DuplicateEngines do
        use RubberDuck.EngineSystem

        engines do
          engine :duplicate do
            module TestModule1
          end

          engine :duplicate do
            module TestModule2
          end
        end
      end
    end
  end

  # Test invalid priority
  test "raises compile error for invalid priority" do
    assert_raise RuntimeError, ~r/Invalid priority values/, fn ->
      defmodule InvalidPriorityEngine do
        use RubberDuck.EngineSystem

        engines do
          engine :invalid_priority do
            module TestModule
            priority(-1)
          end
        end
      end
    end
  end

  test "raises compile error for priority over 1000" do
    assert_raise RuntimeError, ~r/Invalid priority values/, fn ->
      defmodule HighPriorityEngine do
        use RubberDuck.EngineSystem

        engines do
          engine :high_priority do
            module TestModule
            priority(1001)
          end
        end
      end
    end
  end

  # Test valid configurations compile successfully
  test "valid engine configuration compiles" do
    defmodule ValidEngines do
      use RubberDuck.EngineSystem

      engines do
        engine :valid1 do
          module ValidModule1
          priority(0)
        end

        engine :valid2 do
          module ValidModule2
          priority(1000)
        end
      end
    end

    # If we get here, compilation succeeded
    assert true
  end
end

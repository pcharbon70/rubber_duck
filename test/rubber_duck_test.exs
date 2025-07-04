defmodule RubberDuckTest do
  use ExUnit.Case
  doctest RubberDuck

  describe "module structure" do
    test "RubberDuck module exists" do
      assert Code.ensure_loaded?(RubberDuck)
    end

    test "version/0 returns application version" do
      version = RubberDuck.version()
      assert is_binary(version)
      assert version == "0.1.0"
    end
  end
end

defmodule RubberDuckCoreTest do
  use ExUnit.Case
  doctest RubberDuckCore

  test "greets the world" do
    assert RubberDuckCore.hello() == :world
  end
end

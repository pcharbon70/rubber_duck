defmodule RubberDuckTest do
  use ExUnit.Case
  doctest RubberDuck

  test "greets the world" do
    assert RubberDuck.hello() == :world
  end
end

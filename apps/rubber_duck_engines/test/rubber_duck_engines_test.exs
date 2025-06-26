defmodule RubberDuckEnginesTest do
  use ExUnit.Case
  doctest RubberDuckEngines

  test "greets the world" do
    assert RubberDuckEngines.hello() == :world
  end
end

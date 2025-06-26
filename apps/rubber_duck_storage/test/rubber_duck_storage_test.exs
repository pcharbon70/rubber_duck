defmodule RubberDuckStorageTest do
  use ExUnit.Case
  doctest RubberDuckStorage

  test "greets the world" do
    assert RubberDuckStorage.hello() == :world
  end
end

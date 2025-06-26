defmodule RubberDuckWebTest do
  use ExUnit.Case
  doctest RubberDuckWeb

  test "greets the world" do
    assert RubberDuckWeb.hello() == :world
  end
end

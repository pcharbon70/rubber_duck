defmodule RubberDuck.CoTSimpleTest do
  use ExUnit.Case

  # Minimal test module
  defmodule SimpleChain do
    use Spark.Dsl, default_extensions: [extensions: [RubberDuck.CoT.Dsl]]

    reasoning_chain do
      name :simple
    end
  end

  test "can define a simple chain" do
    # Just check if it compiles
    assert SimpleChain
  end
end

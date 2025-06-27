defmodule RubberDuckWeb.CodingChannelTest do
  use ExUnit.Case, async: true

  test "channel module exists and is loadable" do
    # Test that the channel module exists and can be loaded
    assert Code.ensure_loaded?(RubberDuckWeb.CodingChannel)
  end

  test "channel module follows Phoenix.Channel behavior" do
    # Test that the module uses Phoenix.Channel
    assert Code.ensure_loaded?(RubberDuckWeb.CodingChannel)

    # Check if it's a valid Phoenix.Channel implementation
    behaviours = RubberDuckWeb.CodingChannel.module_info(:attributes)[:behaviour] || []
    assert Phoenix.Channel in behaviours
  end
end

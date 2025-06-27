defmodule RubberDuckCore.ApplicationTest do
  use ExUnit.Case, async: true

  test "application is started" do
    # This test ensures the application is running with a proper supervision tree
    # Since the application is started automatically by OTP, we check it's running
    assert Process.whereis(RubberDuckCore.Application.Supervisor) != nil
  end

  test "application has a supervisor" do
    # Test that the application supervisor is properly configured
    children = RubberDuckCore.Application.children()
    assert is_list(children)
    assert length(children) > 0
  end

  test "registry is running" do
    # Test that the Registry process is started and accessible
    assert Process.whereis(RubberDuckCore.Registry) != nil
  end

  test "core supervisor is running" do
    # Test that the core supervisor is started
    assert Process.whereis(RubberDuckCore.Supervisor) != nil
  end
end

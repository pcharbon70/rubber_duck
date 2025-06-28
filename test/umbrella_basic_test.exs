defmodule UmbrellaBasicTest do
  @moduledoc """
  Basic test to verify umbrella-level tests work.
  """
  
  use ExUnit.Case

  test "umbrella project structure exists" do
    assert File.exists?("mix.exs")
    assert File.dir?("apps")
    assert File.dir?("config")
  end

  test "all umbrella apps exist" do
    expected_apps = ["rubber_duck_core", "rubber_duck_storage", "rubber_duck_engines", "rubber_duck_web"]
    
    Enum.each(expected_apps, fn app ->
      assert File.dir?("apps/#{app}"), "App directory apps/#{app} does not exist"
      assert File.exists?("apps/#{app}/mix.exs"), "App #{app} missing mix.exs file"
    end)
  end
end
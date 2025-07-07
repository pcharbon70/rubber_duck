defmodule RubberDuck.ExampleEnginesTest do
  use ExUnit.Case, async: true

  alias RubberDuck.EngineSystem
  alias RubberDuck.ExampleEngines

  describe "example engines configuration" do
    test "engines are properly configured" do
      engines = EngineSystem.engines(ExampleEngines)

      assert length(engines) == 2
      assert Enum.map(engines, & &1.name) == [:echo, :reverse]
    end

    test "echo engine has correct configuration" do
      engine = EngineSystem.get_engine(ExampleEngines, :echo)

      assert engine.module == ExampleEngines.Echo
      assert engine.priority == 10
      assert engine.timeout == 1_000
      assert engine.config == [prefix: "[ECHO]"]
    end

    test "reverse engine has correct configuration" do
      engine = EngineSystem.get_engine(ExampleEngines, :reverse)

      assert engine.module == ExampleEngines.Reverse
      assert engine.priority == 20
      assert engine.timeout == 2_000
    end
  end

  describe "echo engine behavior" do
    test "initializes with config" do
      {:ok, state} = ExampleEngines.Echo.init(prefix: "[TEST]")
      assert state == %{prefix: "[TEST]"}
    end

    test "echoes text with prefix from config" do
      {:ok, state} = ExampleEngines.Echo.init(prefix: "[ECHO]")
      {:ok, result} = ExampleEngines.Echo.execute(%{text: "Hello"}, state)

      assert result == "[ECHO] Hello"
    end

    test "echoes text without prefix if not configured" do
      {:ok, state} = ExampleEngines.Echo.init([])
      {:ok, result} = ExampleEngines.Echo.execute(%{text: "Hello"}, state)

      assert result == "Hello"
    end

    test "returns error for missing text" do
      {:ok, state} = ExampleEngines.Echo.init([])
      {:error, msg} = ExampleEngines.Echo.execute(%{}, state)

      assert msg == "Missing required :text key in input"
    end

    test "provides correct capabilities" do
      assert ExampleEngines.Echo.capabilities() == [:echo, :text_processing]
    end
  end

  describe "reverse engine behavior" do
    test "initializes with empty state" do
      {:ok, state} = ExampleEngines.Reverse.init([])
      assert state == %{}
    end

    test "reverses text" do
      {:ok, state} = ExampleEngines.Reverse.init([])
      {:ok, result} = ExampleEngines.Reverse.execute(%{text: "Hello"}, state)

      assert result == "olleH"
    end

    test "returns error for missing text" do
      {:ok, state} = ExampleEngines.Reverse.init([])
      {:error, msg} = ExampleEngines.Reverse.execute(%{}, state)

      assert msg == "Missing required :text key in input or text is not a string"
    end

    test "returns error for non-string text" do
      {:ok, state} = ExampleEngines.Reverse.init([])
      {:error, msg} = ExampleEngines.Reverse.execute(%{text: 123}, state)

      assert msg == "Missing required :text key in input or text is not a string"
    end

    test "provides correct capabilities" do
      assert ExampleEngines.Reverse.capabilities() == [:reverse, :text_processing]
    end
  end

  describe "engine system queries" do
    test "finds engines by capability" do
      engines = EngineSystem.engines_by_capability(ExampleEngines, :text_processing)

      assert length(engines) == 2
      assert :echo in Enum.map(engines, & &1.name)
      assert :reverse in Enum.map(engines, & &1.name)
    end

    test "finds specific capability" do
      engines = EngineSystem.engines_by_capability(ExampleEngines, :echo)

      assert length(engines) == 1
      assert hd(engines).name == :echo
    end

    test "engines sorted by priority" do
      engines = EngineSystem.engines_by_priority(ExampleEngines)

      # Higher priority first
      assert Enum.map(engines, & &1.name) == [:reverse, :echo]
      assert Enum.map(engines, & &1.priority) == [20, 10]
    end
  end
end

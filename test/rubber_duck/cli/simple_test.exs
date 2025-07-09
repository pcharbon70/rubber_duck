defmodule RubberDuck.CLI.SimpleTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias RubberDuck.CLI.{Config, Formatter}
  alias RubberDuck.CLI.Formatter.{Plain, Json, Table}

  describe "Config" do
    test "creates config from parsed args" do
      parsed = %{
        options: %{format: :json},
        flags: %{verbose: true}
      }

      config = Config.from_parsed_args(parsed)

      assert config.format == :json
      assert config.verbose == true
    end
  end

  describe "Formatter" do
    test "formats results based on type" do
      result = %{type: :error, message: "Test error"}

      assert {:ok, "Error: Test error"} = Plain.format(result)
      assert {:ok, json} = Json.format(result)
      assert json =~ "\"type\": \"error\""
    end
  end

  describe "Plain formatter" do
    test "formats completion results" do
      result = %{
        type: :completion,
        suggestions: [
          %{text: "def hello"},
          %{text: "defp hello"}
        ]
      }

      assert {:ok, output} = Plain.format(result)
      assert output =~ "1. def hello"
      assert output =~ "2. defp hello"
    end
  end

  describe "Table formatter" do
    test "formats completion results as table" do
      result = %{
        type: :completion,
        suggestions: [
          %{text: "def hello", score: 0.95}
        ]
      }

      assert {:ok, output} = Table.format(result)
      assert output =~ "| #"
      assert output =~ "| Completion"
      assert output =~ "| Score"
      assert output =~ "0.95"
    end
  end
end

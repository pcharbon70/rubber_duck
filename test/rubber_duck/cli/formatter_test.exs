defmodule RubberDuck.CLI.FormatterTest do
  use ExUnit.Case, async: true

  alias RubberDuck.CLI.Formatter

  describe "format/2" do
    test "delegates to correct formatter based on format type" do
      result = %{type: :test, data: "test"}

      assert {:ok, _} = Formatter.format(result, :plain)
      assert {:ok, _} = Formatter.format(result, :json)
      assert {:ok, _} = Formatter.format(result, :table)
    end

    test "returns error for unknown format" do
      result = %{type: :test}

      assert {:error, "Unknown format: invalid"} = Formatter.format(result, :invalid)
    end
  end
end

defmodule RubberDuck.CLI.Formatter.PlainTest do
  use ExUnit.Case, async: true

  alias RubberDuck.CLI.Formatter.Plain

  describe "format/1 for analysis results" do
    test "formats analysis results correctly" do
      result = %{
        type: :analysis,
        results: [
          %{
            file: "lib/test.ex",
            severity: :warning,
            issues: [
              %{
                line: 10,
                column: 5,
                message: "Unused variable 'x'"
              }
            ]
          }
        ]
      }

      assert {:ok, output} = Plain.format(result)
      assert output =~ "File: lib/test.ex"
      assert output =~ "Severity: warning"
      assert output =~ "[10:5] Unused variable 'x'"
    end
  end

  describe "format/1 for completions" do
    test "formats completion suggestions correctly" do
      result = %{
        type: :completion,
        suggestions: [
          %{text: "def hello do"},
          %{text: "defp hello do"},
          %{text: "defmodule Hello do"}
        ]
      }

      assert {:ok, output} = Plain.format(result)
      assert output =~ "1. def hello do"
      assert output =~ "2. defp hello do"
      assert output =~ "3. defmodule Hello do"
    end
  end

  describe "format/1 for generation" do
    test "formats generated code correctly" do
      result = %{
        type: :generation,
        code: "def hello, do: :world",
        language: "elixir"
      }

      assert {:ok, output} = Plain.format(result)
      assert output =~ "Generated elixir code:"
      assert output =~ "def hello, do: :world"
    end
  end

  describe "format/1 for errors" do
    test "formats error messages correctly" do
      result = %{
        type: :error,
        message: "Something went wrong"
      }

      assert {:ok, output} = Plain.format(result)
      assert output == "Error: Something went wrong"
    end
  end
end

defmodule RubberDuck.CLI.Formatter.JsonTest do
  use ExUnit.Case, async: true

  alias RubberDuck.CLI.Formatter.Json

  describe "format/1" do
    test "formats any result as JSON" do
      result = %{
        type: :test,
        data: ["item1", "item2"],
        number: 42
      }

      assert {:ok, json} = Json.format(result)

      decoded = Jason.decode!(json)
      assert decoded["type"] == "test"
      assert decoded["data"] == ["item1", "item2"]
      assert decoded["number"] == 42
    end

    test "handles complex nested structures" do
      result = %{
        type: :analysis,
        results: [
          %{
            file: "test.ex",
            issues: [
              %{line: 1, message: "Issue 1"},
              %{line: 2, message: "Issue 2"}
            ]
          }
        ]
      }

      assert {:ok, json} = Json.format(result)
      assert json =~ "\"type\": \"analysis\""
      assert json =~ "\"file\": \"test.ex\""
    end
  end
end

defmodule RubberDuck.CLI.Formatter.TableTest do
  use ExUnit.Case, async: true

  alias RubberDuck.CLI.Formatter.Table

  describe "format/1 for analysis results" do
    test "formats analysis results as table" do
      result = %{
        type: :analysis,
        results: [
          %{
            file: "lib/very/long/path/to/file.ex",
            issues: [
              %{
                line: 10,
                column: 5,
                severity: :warning,
                message: "This is a very long warning message that should be truncated"
              }
            ]
          }
        ]
      }

      assert {:ok, output} = Table.format(result)

      # Check table structure
      assert output =~ "| File"
      assert output =~ "| Line"
      assert output =~ "| Column"
      assert output =~ "| Severity"
      assert output =~ "| Issue"

      # Check content
      assert output =~ "lib/very/long/path/to/file.ex"
      assert output =~ "10"
      assert output =~ "5"
      assert output =~ "warning"

      # Check truncation
      assert output =~ "..."
    end
  end

  describe "format/1 for completions" do
    test "formats completions as table" do
      result = %{
        type: :completion,
        suggestions: [
          %{text: "def hello do", score: 0.95},
          %{text: "defp hello do", score: 0.87},
          %{text: "defmodule Hello do", score: nil}
        ]
      }

      assert {:ok, output} = Table.format(result)

      # Check headers
      assert output =~ "| #"
      assert output =~ "| Completion"
      assert output =~ "| Score"

      # Check content
      assert output =~ "| 1"
      assert output =~ "def hello do"
      assert output =~ "0.95"
      # For nil score
      assert output =~ "N/A"
    end
  end
end

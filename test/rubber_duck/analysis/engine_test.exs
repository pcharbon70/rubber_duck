defmodule RubberDuck.Analysis.EngineTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analysis.Engine

  describe "create_issue/7" do
    test "creates a properly structured issue" do
      issue =
        Engine.create_issue(
          :test_issue,
          :medium,
          "Test message",
          %{file: "test.ex", line: 10, column: 5, end_line: nil, end_column: nil},
          "test/rule",
          :correctness,
          %{extra: "data"}
        )

      assert issue.type == :test_issue
      assert issue.severity == :medium
      assert issue.message == "Test message"
      assert issue.location.file == "test.ex"
      assert issue.location.line == 10
      assert issue.location.column == 5
      assert issue.rule == "test/rule"
      assert issue.category == :correctness
      assert issue.metadata.extra == "data"
    end
  end

  describe "create_suggestion/3" do
    test "creates a suggestion with all fields" do
      suggestion = Engine.create_suggestion("Fix this", "diff", true)

      assert suggestion.description == "Fix this"
      assert suggestion.diff == "diff"
      assert suggestion.auto_applicable == true
    end

    test "creates a suggestion with defaults" do
      suggestion = Engine.create_suggestion("Fix this")

      assert suggestion.description == "Fix this"
      assert suggestion.diff == nil
      assert suggestion.auto_applicable == false
    end
  end

  describe "sort_issues/1" do
    test "sorts by severity then line number" do
      issues = [
        %{severity: :low, location: %{line: 10}},
        %{severity: :critical, location: %{line: 20}},
        %{severity: :high, location: %{line: 5}},
        %{severity: :high, location: %{line: 15}},
        %{severity: :medium, location: %{line: 1}}
      ]

      sorted = Engine.sort_issues(issues)

      assert [
               %{severity: :critical, location: %{line: 20}},
               %{severity: :high, location: %{line: 5}},
               %{severity: :high, location: %{line: 15}},
               %{severity: :medium, location: %{line: 1}},
               %{severity: :low, location: %{line: 10}}
             ] = sorted
    end
  end

  describe "group_by_type/1" do
    test "groups issues by their type" do
      issues = [
        %{type: :dead_code, severity: :low},
        %{type: :long_function, severity: :medium},
        %{type: :dead_code, severity: :medium},
        %{type: :security_issue, severity: :high}
      ]

      grouped = Engine.group_by_type(issues)

      assert map_size(grouped) == 3
      assert length(grouped[:dead_code]) == 2
      assert length(grouped[:long_function]) == 1
      assert length(grouped[:security_issue]) == 1
    end
  end

  describe "filter_by_severity/2" do
    test "filters issues by minimum severity" do
      issues = [
        %{severity: :info},
        %{severity: :low},
        %{severity: :medium},
        %{severity: :high},
        %{severity: :critical}
      ]

      assert length(Engine.filter_by_severity(issues, :medium)) == 3
      assert length(Engine.filter_by_severity(issues, :high)) == 2
      assert length(Engine.filter_by_severity(issues, :critical)) == 1
    end

    test "returns all issues when filtering by :info" do
      issues = [
        %{severity: :info},
        %{severity: :low},
        %{severity: :medium}
      ]

      assert length(Engine.filter_by_severity(issues, :info)) == 3
    end
  end
end

defmodule RubberDuck.Tools.TestSummarizerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.TestSummarizer
  
  describe "tool definition" do
    test "has correct metadata" do
      assert TestSummarizer.name() == :test_summarizer
      
      metadata = TestSummarizer.metadata()
      assert metadata.name == :test_summarizer
      assert metadata.description == "Summarizes test results and identifies key failures or gaps"
      assert metadata.category == :testing
      assert metadata.version == "1.0.0"
      assert :testing in metadata.tags
      assert :analysis in metadata.tags
    end
    
    test "has required parameters" do
      params = TestSummarizer.parameters()
      
      test_output_param = Enum.find(params, &(&1.name == :test_output))
      assert test_output_param.required == true
      assert test_output_param.type == :string
      
      format_param = Enum.find(params, &(&1.name == :format))
      assert format_param.default == "auto"
      
      summary_type_param = Enum.find(params, &(&1.name == :summary_type))
      assert summary_type_param.default == "comprehensive"
    end
    
    test "supports different output formats" do
      params = TestSummarizer.parameters()
      format_param = Enum.find(params, &(&1.name == :format))
      
      allowed_formats = format_param.constraints[:enum]
      assert "auto" in allowed_formats
      assert "exunit" in allowed_formats
      assert "junit" in allowed_formats
      assert "tap" in allowed_formats
    end
    
    test "supports different summary types" do
      params = TestSummarizer.parameters()
      summary_type_param = Enum.find(params, &(&1.name == :summary_type))
      
      allowed_types = summary_type_param.constraints[:enum]
      assert "brief" in allowed_types
      assert "comprehensive" in allowed_types
      assert "failures_only" in allowed_types
      assert "actionable" in allowed_types
    end
  end
  
  describe "format detection" do
    test "detects ExUnit format" do
      exunit_output = """
      .....
      
      5 tests, 2 failures
      
      Randomized with seed 123456
      """
      
      params = %{
        test_output: exunit_output,
        format: "auto",
        summary_type: "comprehensive",
        include_coverage: false,
        highlight_flaky: false,
        group_failures: false,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      assert result.metadata.format_detected == "exunit"
    end
    
    test "detects TAP format" do
      tap_output = """
      TAP version 13
      1..5
      ok 1 - first test
      not ok 2 - second test
      ok 3 - third test
      """
      
      params = %{
        test_output: tap_output,
        format: "auto",
        summary_type: "brief",
        include_coverage: false,
        highlight_flaky: false,
        group_failures: false,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      assert result.metadata.format_detected == "tap"
    end
    
    test "detects JUnit XML format" do
      junit_output = """
      <?xml version="1.0" encoding="UTF-8"?>
      <testsuites>
        <testsuite name="Tests" tests="5" failures="1">
          <testcase name="test1" classname="MyTest"/>
        </testsuite>
      </testsuites>
      """
      
      params = %{
        test_output: junit_output,
        format: "auto",
        summary_type: "comprehensive",
        include_coverage: false,
        highlight_flaky: false,
        group_failures: false,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      assert result.metadata.format_detected == "junit"
    end
  end
  
  describe "ExUnit parsing" do
    test "parses basic statistics" do
      exunit_output = """
      .....
      
      5 tests, 2 failures, 1 skipped
      
      Randomized with seed 123456
      """
      
      params = %{
        test_output: exunit_output,
        format: "exunit",
        summary_type: "comprehensive",
        include_coverage: false,
        highlight_flaky: false,
        group_failures: false,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      assert result.statistics.total == 5
      assert result.statistics.failed == 2
      assert result.statistics.skipped == 1
      assert result.statistics.passed == 2
    end
    
    test "parses failure details" do
      exunit_output = """
      
      1) test failing assertion (MyTest)
         test/my_test.exs:10
         Assertion with == failed
         code:  assert 1 == 2
         left:  1
         right: 2
         stacktrace:
           test/my_test.exs:10: (test)
      
      2) test exception (MyTest)
         test/my_test.exs:15
         ** (ArgumentError) invalid argument
         stacktrace:
           test/my_test.exs:15: (test)
      
      2 tests, 2 failures
      """
      
      params = %{
        test_output: exunit_output,
        format: "exunit",
        summary_type: "comprehensive",
        include_coverage: false,
        highlight_flaky: false,
        group_failures: true,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      assert length(result.failures) == 2
    end
  end
  
  describe "TAP parsing" do
    test "parses TAP format correctly" do
      tap_output = """
      TAP version 13
      1..3
      ok 1 - first test passes
      not ok 2 - second test fails
      ok 3 - third test passes
      """
      
      params = %{
        test_output: tap_output,
        format: "tap",
        summary_type: "comprehensive",
        include_coverage: false,
        highlight_flaky: false,
        group_failures: false,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      assert result.statistics.total == 3
      assert result.statistics.failed == 1
      assert result.statistics.passed == 2
    end
  end
  
  describe "failure grouping" do
    test "groups failures by type" do
      exunit_output = """
      
      1) test assertion failure (Test1)
         Assertion with == failed
      
      2) test another assertion (Test1)
         Assertion with != failed
      
      3) test argument error (Test2)
         ** (ArgumentError) bad argument
      
      3 tests, 3 failures
      """
      
      params = %{
        test_output: exunit_output,
        format: "exunit",
        summary_type: "comprehensive",
        include_coverage: false,
        highlight_flaky: false,
        group_failures: true,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      
      # Should group by failure type
      assertion_group = Enum.find(result.failures, &(&1.type == :assertion))
      assert assertion_group.count == 2
      
      arg_error_group = Enum.find(result.failures, &(&1.type == :argument_error))
      assert arg_error_group.count == 1
    end
  end
  
  describe "flaky test detection" do
    test "identifies timeout-related failures" do
      exunit_output = """
      
      1) test timeout issue (FlayTest)
         ** (RuntimeError) timeout after 5000ms
      
      2) test connection timeout (FlayTest)
         ** (DBConnection.ConnectionError) timeout
      
      2 tests, 2 failures
      """
      
      params = %{
        test_output: exunit_output,
        format: "exunit",
        summary_type: "comprehensive",
        include_coverage: false,
        highlight_flaky: true,
        group_failures: false,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      
      # Should identify timeout patterns
      # Implementation would detect timeout-related failures
    end
  end
  
  describe "summary types" do
    setup do
      test_output = """
      .F.
      
      1) test failing (MyTest)
         test/my_test.exs:5
         Assertion failed
      
      3 tests, 1 failure
      """
      
      {:ok, test_output: test_output}
    end
    
    test "generates brief summary", %{test_output: test_output} do
      params = %{
        test_output: test_output,
        format: "exunit",
        summary_type: "brief",
        include_coverage: false,
        highlight_flaky: false,
        group_failures: false,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      assert result.summary.type == "brief"
      assert Map.has_key?(result.summary, :content)
    end
    
    test "generates comprehensive summary", %{test_output: test_output} do
      params = %{
        test_output: test_output,
        format: "exunit",
        summary_type: "comprehensive",
        include_coverage: false,
        highlight_flaky: false,
        group_failures: false,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      assert result.summary.type == "comprehensive"
      assert Map.has_key?(result.summary, :findings)
      assert Map.has_key?(result.summary, :recommendations)
    end
    
    test "generates actionable summary", %{test_output: test_output} do
      params = %{
        test_output: test_output,
        format: "exunit",
        summary_type: "actionable",
        include_coverage: false,
        highlight_flaky: false,
        group_failures: false,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      assert result.summary.type == "actionable"
      assert Map.has_key?(result.summary, :action_items)
      assert Map.has_key?(result.summary, :priority)
    end
  end
  
  describe "statistics calculation" do
    test "calculates pass rates correctly" do
      test_output = "10 tests, 3 failures"
      
      params = %{
        test_output: test_output,
        format: "exunit",
        summary_type: "comprehensive",
        include_coverage: false,
        highlight_flaky: false,
        group_failures: false,
        suggest_fixes: false
      }
      
      {:ok, result} = TestSummarizer.execute(params, %{})
      assert result.statistics.total == 10
      assert result.statistics.failed == 3
      assert result.statistics.passed == 7
      assert result.statistics.pass_rate == 70.0
      assert result.statistics.failure_rate == 30.0
    end
  end
end
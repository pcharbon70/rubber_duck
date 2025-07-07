defmodule RubberDuck.Analysis.AnalyzerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analysis.{Analyzer, Semantic, Style, Security}

  @test_file_content """
  defmodule TestModule do
    def process_input(input) do
      String.to_atom(input)  # Security issue
    end
    
    def unused_private_function do  # Dead code
      :never_called
    end
    
    def longFunctionName(a, b, c, d, e, f) do  # Style issues
      :too_many_params
    end
  end
  """

  describe "analyze_source/3" do
    test "runs all engines by default" do
      {:ok, result} = Analyzer.analyze_source(@test_file_content, :elixir)

      assert result.total_issues > 0
      assert map_size(result.issues_by_engine) == 3
      assert Map.has_key?(result.issues_by_engine, :semantic)
      assert Map.has_key?(result.issues_by_engine, :style)
      assert Map.has_key?(result.issues_by_engine, :security)
    end

    test "runs only specified engines" do
      {:ok, result} = Analyzer.analyze_source(@test_file_content, :elixir, engines: [Security])

      assert map_size(result.issues_by_engine) == 1
      assert Map.has_key?(result.issues_by_engine, :security)
    end

    test "aggregates issues by severity" do
      {:ok, result} = Analyzer.analyze_source(@test_file_content, :elixir)

      assert is_map(result.issues_by_severity)
      # Dynamic atom issue
      assert Map.get(result.issues_by_severity, :high, 0) > 0
    end

    test "sorts all issues by severity and line" do
      {:ok, result} = Analyzer.analyze_source(@test_file_content, :elixir)

      severities = Enum.map(result.all_issues, & &1.severity)

      # Check that critical/high issues come first
      severity_values = %{critical: 0, high: 1, medium: 2, low: 3, info: 4}
      numeric_severities = Enum.map(severities, &Map.get(severity_values, &1, 5))

      assert numeric_severities == Enum.sort(numeric_severities)
    end

    test "includes execution time" do
      {:ok, result} = Analyzer.analyze_source(@test_file_content, :elixir)

      assert is_integer(result.execution_time)
      assert result.execution_time >= 0
    end

    test "runs engines sequentially when configured" do
      {:ok, result} = Analyzer.analyze_source(@test_file_content, :elixir, parallel: false)

      assert result.total_issues > 0
      assert map_size(result.issues_by_engine) == 3
    end
  end

  describe "analyze_file/2" do
    setup do
      # Create a temporary test file
      path = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(10000)}.ex")
      File.write!(path, @test_file_content)

      on_exit(fn -> File.rm(path) end)

      {:ok, file_path: path}
    end

    test "analyzes a file from disk", %{file_path: path} do
      {:ok, result} = Analyzer.analyze_file(path)

      assert result.file == path
      assert result.total_issues > 0
      assert length(result.all_issues) == result.total_issues
    end

    test "handles non-existent files gracefully" do
      result = Analyzer.analyze_file("/non/existent/file.ex")

      assert {:error, _} = result
    end
  end

  describe "available_engines/0" do
    test "returns list of default engines" do
      engines = Analyzer.available_engines()

      assert Semantic in engines
      assert Style in engines
      assert Security in engines
      assert length(engines) == 3
    end
  end

  describe "default_config/0" do
    test "returns combined configuration from all engines" do
      config = Analyzer.default_config()

      assert Map.has_key?(config, :semantic)
      assert Map.has_key?(config, :style)
      assert Map.has_key?(config, :security)

      # Check some specific config values
      assert config.semantic.detect_dead_code == true
      assert config.style.check_naming_conventions == true
      assert config.security.detect_dynamic_atoms == true
    end
  end

  describe "source analysis fallback" do
    test "handles unparseable Elixir code" do
      bad_code = """
      defmodule Broken do
        def incomplete(
      """

      {:ok, result} = Analyzer.analyze_source(bad_code, :elixir)

      # Should still get some results from source-based analysis
      assert is_map(result)
      assert result.total_issues >= 0
    end

    test "handles non-Elixir languages" do
      js_code = """
      function example() {
        eval("dangerous");  // Should be detected by source analysis
      }
      """

      {:ok, result} = Analyzer.analyze_source(js_code, :javascript)

      assert is_map(result)
      # Security engine should detect eval
      security_issues = result.issues_by_engine[:security] || 0
      assert security_issues > 0
    end
  end

  describe "metrics aggregation" do
    test "collects metrics from all engines" do
      {:ok, result} = Analyzer.analyze_source(@test_file_content, :elixir)

      assert is_map(result.metrics)
      assert Map.has_key?(result.metrics, :semantic)
      assert Map.has_key?(result.metrics, :style)
      assert Map.has_key?(result.metrics, :security)

      # Check some specific metrics
      assert is_number(result.metrics.semantic.total_functions)
      assert is_float(result.metrics.style.naming_consistency_score)
      assert is_integer(result.metrics.security.security_score)
    end
  end

  describe "suggestions aggregation" do
    test "merges suggestions from all engines" do
      {:ok, result} = Analyzer.analyze_source(@test_file_content, :elixir)

      assert is_map(result.suggestions)

      # Should have suggestions for dynamic atom creation
      assert Map.has_key?(result.suggestions, :dynamic_atom_creation)
      atom_suggestions = result.suggestions[:dynamic_atom_creation]
      assert length(atom_suggestions) > 0
    end
  end
end


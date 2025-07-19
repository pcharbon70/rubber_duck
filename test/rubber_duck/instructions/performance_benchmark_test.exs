defmodule RubberDuck.Instructions.PerformanceBenchmarkTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Instructions.{PerformanceBenchmark, RateLimiter}

  setup do
    # Clear rate limiter before each test
    RateLimiter.clear_all()
    :ok
  end

  describe "Performance Benchmark" do
    test "can run basic benchmark" do
      # Use small iteration count for tests
      opts = [iterations: 10]

      assert {:ok, results} = PerformanceBenchmark.run_benchmark(opts)

      # Verify structure
      assert %{
               benchmark_started: %DateTime{},
               iterations: 10,
               templates: template_count,
               results: %{
                 security_pipeline: security_results,
                 template_processor_only: processor_results
               },
               analysis: analysis
             } = results

      # Should have some templates
      assert template_count > 0

      # Security results should have proper structure
      assert %{
               individual_results: security_individual,
               aggregate: security_aggregate
             } = security_results

      # Processor results should have proper structure
      assert %{
               individual_results: processor_individual,
               aggregate: processor_aggregate
             } = processor_results

      # Should have analysis
      assert %{
               performance_impact: impact,
               recommendation: recommendation,
               acceptable_performance: acceptable
             } = analysis

      # Results should be lists
      assert is_list(security_individual)
      assert is_list(processor_individual)

      # Should have same number of results
      assert length(security_individual) == length(processor_individual)

      # Aggregate should have expected fields
      assert %{
               total_time_ms: _,
               avg_time_ms: _,
               avg_success_rate: _,
               total_throughput_per_sec: _
             } = security_aggregate

      assert %{
               total_time_ms: _,
               avg_time_ms: _,
               avg_success_rate: _,
               total_throughput_per_sec: _
             } = processor_aggregate

      # Performance impact should have expected fields
      assert %{
               time_overhead_ms: _,
               time_overhead_percent: _,
               throughput_reduction_per_sec: _,
               throughput_reduction_percent: _
             } = impact

      # Recommendation should be a string
      assert is_binary(recommendation)

      # Acceptable performance should be a boolean
      assert is_boolean(acceptable)
    end

    test "can measure memory usage" do
      template = "Hello {{ name }}"
      variables = %{"name" => "World"}

      assert results = PerformanceBenchmark.measure_memory_usage(template, variables, 10)

      # Should have proper structure
      assert %{
               with_security: with_security,
               without_security: without_security,
               overhead: overhead
             } = results

      # Each measurement should have expected fields
      assert %{
               time_ms: _,
               memory_bytes: _,
               memory_per_request: _
             } = with_security

      assert %{
               time_ms: _,
               memory_bytes: _,
               memory_per_request: _
             } = without_security

      # Overhead should have expected fields
      assert %{
               time_overhead_ms: _,
               memory_overhead_bytes: _,
               time_overhead_percent: _,
               memory_overhead_percent: _
             } = overhead
    end

    test "can run stress test" do
      opts = [
        concurrent_processes: 2,
        requests_per_process: 5,
        template: "Hello {{ name }}",
        variables: %{"name" => "World"}
      ]

      assert results = PerformanceBenchmark.stress_test(opts)

      # Should have proper structure
      assert %{
               test_config: config,
               timing: timing,
               success_rate: success_rate,
               percentiles: percentiles
             } = results

      # Config should match what we passed
      assert %{
               concurrent_processes: 2,
               requests_per_process: 5,
               total_requests: 10
             } = config

      # Timing should have expected fields
      assert %{
               total_time_ms: _,
               avg_request_time_ms: _,
               min_request_time_ms: _,
               max_request_time_ms: _,
               throughput_per_sec: _
             } = timing

      # Success rate should have expected fields
      assert %{
               successes: _,
               failures: _,
               success_rate: _
             } = success_rate

      # Percentiles should have expected fields
      assert %{
               p50: _,
               p75: _,
               p90: _,
               p95: _,
               p99: _
             } = percentiles
    end

    test "benchmarks individual templates" do
      templates = [
        {"simple", "Hello {{ name }}", %{"name" => "World"}},
        {"with_filter", "{{ message | upcase }}", %{"message" => "hello"}}
      ]

      assert results = PerformanceBenchmark.benchmark_security_pipeline(templates, 5)

      # Should have proper structure
      assert %{
               individual_results: individual,
               aggregate: aggregate
             } = results

      # Should have results for each template
      assert length(individual) == 2

      # Each result should have expected fields
      Enum.each(individual, fn result ->
        assert %{
                 template_name: _,
                 total_time_ms: _,
                 avg_time_ms: _,
                 success_rate: _,
                 throughput_per_sec: _
               } = result
      end)
    end
  end
end

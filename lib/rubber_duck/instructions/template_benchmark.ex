defmodule RubberDuck.Instructions.TemplateBenchmark do
  @moduledoc """
  Template benchmarking utilities for performance testing and optimization.

  Provides comprehensive benchmarking features including:
  - Performance measurement
  - Memory usage tracking
  - Throughput testing
  - Comparative analysis
  - Load testing
  """

  alias RubberDuck.Instructions.TemplateProcessor

  @type benchmark_result :: %{
          duration: non_neg_integer(),
          memory_usage: non_neg_integer(),
          throughput: float(),
          errors: non_neg_integer(),
          metadata: map()
        }

  @doc """
  Benchmarks a single template with various configurations.
  """
  @spec benchmark_template(String.t(), map(), keyword()) :: benchmark_result()
  def benchmark_template(template_content, variables \\ %{}, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 1000)
    warmup = Keyword.get(opts, :warmup, 100)

    # Warmup runs
    run_warmup(template_content, variables, warmup)

    # Actual benchmark
    {duration, memory_usage, errors} = run_benchmark(template_content, variables, iterations)

    throughput = iterations / (duration / 1_000_000)

    %{
      duration: duration,
      memory_usage: memory_usage,
      throughput: throughput,
      errors: errors,
      metadata: %{
        iterations: iterations,
        template_size: String.length(template_content),
        variable_count: map_size(variables),
        timestamp: DateTime.utc_now()
      }
    }
  end

  @doc """
  Compares performance between different templates.
  """
  @spec compare_templates([{String.t(), String.t(), map()}], keyword()) :: map()
  def compare_templates(templates, opts \\ []) do
    results =
      templates
      |> Enum.with_index()
      |> Enum.map(fn {{name, template, variables}, index} ->
        result = benchmark_template(template, variables, opts)
        {name || "Template #{index + 1}", result}
      end)
      |> Enum.into(%{})

    %{
      results: results,
      comparison: generate_comparison(results),
      summary: generate_summary(results)
    }
  end

  @doc """
  Performs load testing with concurrent template processing.
  """
  @spec load_test(String.t(), map(), keyword()) :: map()
  def load_test(template_content, variables \\ %{}, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 10)
    duration_ms = Keyword.get(opts, :duration_ms, 10_000)

    start_time = System.monotonic_time(:millisecond)

    # Start concurrent workers
    workers =
      1..concurrency
      |> Enum.map(fn _ ->
        Task.async(fn ->
          worker_loop(template_content, variables, start_time, duration_ms)
        end)
      end)

    # Collect results
    results = Enum.map(workers, &Task.await/1)

    total_requests = Enum.sum(Enum.map(results, & &1.requests))
    total_errors = Enum.sum(Enum.map(results, & &1.errors))
    actual_duration = Enum.max(Enum.map(results, & &1.duration))

    %{
      total_requests: total_requests,
      total_errors: total_errors,
      success_rate: (total_requests - total_errors) / total_requests,
      requests_per_second: total_requests / (actual_duration / 1000),
      actual_duration: actual_duration,
      concurrency: concurrency,
      worker_results: results
    }
  end

  @doc """
  Benchmarks template processing with different variable sizes.
  """
  @spec benchmark_variable_sizes(String.t(), keyword()) :: map()
  def benchmark_variable_sizes(template_content, opts \\ []) do
    variable_sizes = Keyword.get(opts, :sizes, [1, 10, 100, 1000])
    iterations = Keyword.get(opts, :iterations, 100)

    results =
      variable_sizes
      |> Enum.map(fn size ->
        variables = generate_variables(size)
        result = benchmark_template(template_content, variables, iterations: iterations)
        {size, result}
      end)
      |> Enum.into(%{})

    %{
      results: results,
      analysis: analyze_variable_scaling(results)
    }
  end

  @doc """
  Benchmarks template processing with different template sizes.
  """
  @spec benchmark_template_sizes(keyword()) :: map()
  def benchmark_template_sizes(opts \\ []) do
    sizes = Keyword.get(opts, :sizes, [100, 1000, 10_000, 50_000])
    iterations = Keyword.get(opts, :iterations, 100)

    results =
      sizes
      |> Enum.map(fn size ->
        template = generate_template(size)
        variables = %{"name" => "test", "value" => "data"}
        result = benchmark_template(template, variables, iterations: iterations)
        {size, result}
      end)
      |> Enum.into(%{})

    %{
      results: results,
      analysis: analyze_template_scaling(results)
    }
  end

  @doc """
  Generates a performance report from benchmark results.
  """
  @spec generate_report(map()) :: String.t()
  def generate_report(results) do
    case results do
      %{results: template_results, comparison: comparison} ->
        generate_comparison_report(template_results, comparison)

      %{total_requests: _} ->
        generate_load_test_report(results)

      %{duration: _} ->
        generate_single_benchmark_report(results)

      _ ->
        "Unknown benchmark result format"
    end
  end

  # Private functions

  defp run_warmup(template_content, variables, warmup_runs) do
    1..warmup_runs
    |> Enum.each(fn _ ->
      TemplateProcessor.process_template(template_content, variables)
    end)
  end

  defp run_benchmark(template_content, variables, iterations) do
    start_time = System.monotonic_time(:microsecond)
    {memory_before, _} = :erlang.process_info(self(), :memory)

    errors =
      1..iterations
      |> Enum.count(fn _ ->
        case TemplateProcessor.process_template(template_content, variables) do
          {:ok, _} -> false
          {:error, _} -> true
        end
      end)

    {memory_after, _} = :erlang.process_info(self(), :memory)
    end_time = System.monotonic_time(:microsecond)

    duration = end_time - start_time
    memory_usage = memory_after - memory_before

    {duration, memory_usage, errors}
  end

  defp worker_loop(template_content, variables, start_time, duration_ms) do
    worker_loop(template_content, variables, start_time, duration_ms, 0, 0)
  end

  defp worker_loop(template_content, variables, start_time, duration_ms, requests, errors) do
    current_time = System.monotonic_time(:millisecond)

    if current_time - start_time < duration_ms do
      new_errors =
        case TemplateProcessor.process_template(template_content, variables) do
          {:ok, _} -> errors
          {:error, _} -> errors + 1
        end

      worker_loop(template_content, variables, start_time, duration_ms, requests + 1, new_errors)
    else
      %{
        requests: requests,
        errors: errors,
        duration: current_time - start_time
      }
    end
  end

  defp generate_variables(count) do
    1..count
    |> Enum.map(fn i -> {"var#{i}", "value#{i}"} end)
    |> Enum.into(%{})
  end

  defp generate_template(size) do
    base_template = "Hello {{ name }}, your value is {{ value }}."
    repetitions = div(size, String.length(base_template))

    1..repetitions
    |> Enum.map(fn i ->
      String.replace(base_template, "{{ name }}", "{{ name#{i} }}")
    end)
    |> Enum.join("\n")
  end

  defp generate_comparison(results) do
    sorted_results = Enum.sort_by(results, fn {_, result} -> result.throughput end, :desc)

    %{
      fastest: List.first(sorted_results),
      slowest: List.last(sorted_results),
      rankings: Enum.with_index(sorted_results, 1),
      performance_ratios: calculate_performance_ratios(sorted_results)
    }
  end

  defp calculate_performance_ratios(sorted_results) do
    {_fastest_name, fastest_result} = List.first(sorted_results)

    sorted_results
    |> Enum.map(fn {name, result} ->
      ratio = fastest_result.throughput / result.throughput
      {name, ratio}
    end)
    |> Enum.into(%{})
  end

  defp generate_summary(results) do
    throughputs = Enum.map(results, fn {_, result} -> result.throughput end)
    durations = Enum.map(results, fn {_, result} -> result.duration end)

    %{
      average_throughput: Enum.sum(throughputs) / length(throughputs),
      total_duration: Enum.sum(durations),
      template_count: length(results)
    }
  end

  defp analyze_variable_scaling(results) do
    sorted_results = Enum.sort_by(results, fn {size, _} -> size end)

    %{
      scaling_factor: calculate_scaling_factor(sorted_results),
      performance_degradation: calculate_performance_degradation(sorted_results)
    }
  end

  defp analyze_template_scaling(results) do
    sorted_results = Enum.sort_by(results, fn {size, _} -> size end)

    %{
      scaling_factor: calculate_scaling_factor(sorted_results),
      memory_scaling: calculate_memory_scaling(sorted_results)
    }
  end

  defp calculate_scaling_factor(sorted_results) do
    if length(sorted_results) < 2 do
      1.0
    else
      [{_size1, result1} | _] = sorted_results
      {_size2, result2} = List.last(sorted_results)

      result1.throughput / result2.throughput
    end
  end

  defp calculate_performance_degradation(sorted_results) do
    if length(sorted_results) < 2 do
      0.0
    else
      [{_size1, result1} | _] = sorted_results
      {_size2, result2} = List.last(sorted_results)

      (result1.throughput - result2.throughput) / result1.throughput * 100
    end
  end

  defp calculate_memory_scaling(sorted_results) do
    if length(sorted_results) < 2 do
      1.0
    else
      [{_size1, result1} | _] = sorted_results
      {_size2, result2} = List.last(sorted_results)

      result2.memory_usage / result1.memory_usage
    end
  end

  defp generate_single_benchmark_report(result) do
    """
    # Template Benchmark Report

    ## Performance Metrics
    - Duration: #{result.duration}μs
    - Memory Usage: #{result.memory_usage} bytes
    - Throughput: #{Float.round(result.throughput, 2)} templates/second
    - Error Rate: #{result.errors}/#{result.metadata.iterations} (#{Float.round(result.errors / result.metadata.iterations * 100, 2)}%)

    ## Template Information
    - Template Size: #{result.metadata.template_size} characters
    - Variables: #{result.metadata.variable_count}
    - Timestamp: #{result.metadata.timestamp}
    """
  end

  defp generate_comparison_report(_results, comparison) do
    {fastest_name, fastest_result} = comparison.fastest
    {slowest_name, slowest_result} = comparison.slowest

    """
    # Template Comparison Report

    ## Performance Rankings
    #{Enum.map(comparison.rankings, fn {{name, result}, rank} -> "#{rank}. #{name}: #{Float.round(result.throughput, 2)} templates/second" end) |> Enum.join("\n")}

    ## Fastest Template
    - Name: #{fastest_name}
    - Throughput: #{Float.round(fastest_result.throughput, 2)} templates/second
    - Duration: #{fastest_result.duration}μs

    ## Slowest Template
    - Name: #{slowest_name}
    - Throughput: #{Float.round(slowest_result.throughput, 2)} templates/second
    - Duration: #{slowest_result.duration}μs

    ## Performance Ratios
    #{Enum.map(comparison.performance_ratios, fn {name, ratio} -> "- #{name}: #{Float.round(ratio, 2)}x slower than fastest" end) |> Enum.join("\n")}
    """
  end

  defp generate_load_test_report(results) do
    """
    # Load Test Report

    ## Test Configuration
    - Concurrency: #{results.concurrency}
    - Duration: #{results.actual_duration}ms

    ## Results
    - Total Requests: #{results.total_requests}
    - Total Errors: #{results.total_errors}
    - Success Rate: #{Float.round(results.success_rate * 100, 2)}%
    - Requests per Second: #{Float.round(results.requests_per_second, 2)}

    ## Worker Performance
    #{Enum.with_index(results.worker_results, 1) |> Enum.map(fn {worker, i} -> "Worker #{i}: #{worker.requests} requests, #{worker.errors} errors" end) |> Enum.join("\n")}
    """
  end
end

defmodule RubberDuck.Instructions.PerformanceBenchmark do
  @moduledoc """
  Performance benchmarking utilities for the Security Pipeline.

  Provides tools to measure and compare performance of template processing
  with and without security features enabled.
  """

  alias RubberDuck.Instructions.{SecurityPipeline, TemplateProcessor}

  @doc """
  Runs a comprehensive performance benchmark.
  """
  def run_benchmark(opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 1000)
    templates = Keyword.get(opts, :templates, default_templates())

    results = %{
      benchmark_started: DateTime.utc_now(),
      iterations: iterations,
      templates: length(templates),
      results: %{
        security_pipeline: benchmark_security_pipeline(templates, iterations),
        template_processor_only: benchmark_template_processor(templates, iterations)
      }
    }

    analysis = analyze_results(results)

    {:ok, Map.put(results, :analysis, analysis)}
  end

  @doc """
  Benchmarks the SecurityPipeline with full security features.
  """
  def benchmark_security_pipeline(templates, iterations) do
    results =
      Enum.map(templates, fn {name, template, variables} ->
        {time, success_count} = benchmark_template_with_security(template, variables, iterations)

        %{
          template_name: name,
          total_time_ms: time,
          avg_time_ms: time / iterations,
          success_rate: success_count / iterations,
          throughput_per_sec: iterations / time * 1000
        }
      end)

    %{
      individual_results: results,
      aggregate: calculate_aggregate_stats(results)
    }
  end

  @doc """
  Benchmarks the TemplateProcessor without security features.
  """
  def benchmark_template_processor(templates, iterations) do
    results =
      Enum.map(templates, fn {name, template, variables} ->
        {time, success_count} = benchmark_template_without_security(template, variables, iterations)

        %{
          template_name: name,
          total_time_ms: time,
          avg_time_ms: time / iterations,
          success_rate: success_count / iterations,
          throughput_per_sec: iterations / time * 1000
        }
      end)

    %{
      individual_results: results,
      aggregate: calculate_aggregate_stats(results)
    }
  end

  @doc """
  Measures memory usage during template processing.
  """
  def measure_memory_usage(template, variables, iterations \\ 100) do
    # Measure with security
    {time_with_security, memory_with_security} =
      measure_with_memory(fn ->
        Enum.each(1..iterations, fn _ ->
          SecurityPipeline.process(template, variables)
        end)
      end)

    # Measure without security
    {time_without_security, memory_without_security} =
      measure_with_memory(fn ->
        Enum.each(1..iterations, fn _ ->
          TemplateProcessor.process_template(template, variables)
        end)
      end)

    %{
      with_security: %{
        time_ms: time_with_security,
        memory_bytes: memory_with_security,
        memory_per_request: memory_with_security / iterations
      },
      without_security: %{
        time_ms: time_without_security,
        memory_bytes: memory_without_security,
        memory_per_request: memory_without_security / iterations
      },
      overhead: %{
        time_overhead_ms: time_with_security - time_without_security,
        memory_overhead_bytes: memory_with_security - memory_without_security,
        time_overhead_percent: (time_with_security - time_without_security) / time_without_security * 100,
        memory_overhead_percent: (memory_with_security - memory_without_security) / memory_without_security * 100
      }
    }
  end

  @doc """
  Stress tests the security pipeline with high load.
  """
  def stress_test(opts \\ []) do
    concurrent_processes = Keyword.get(opts, :concurrent_processes, 10)
    requests_per_process = Keyword.get(opts, :requests_per_process, 100)
    template = Keyword.get(opts, :template, "Hello {{ name }}")
    variables = Keyword.get(opts, :variables, %{"name" => "World"})

    start_time = System.monotonic_time(:millisecond)

    # Spawn concurrent processes
    tasks =
      Enum.map(1..concurrent_processes, fn process_id ->
        Task.async(fn ->
          process_results =
            Enum.map(1..requests_per_process, fn request_id ->
              request_start = System.monotonic_time(:millisecond)

              result = SecurityPipeline.process(template, variables)

              request_end = System.monotonic_time(:millisecond)

              %{
                process_id: process_id,
                request_id: request_id,
                duration_ms: request_end - request_start,
                success: match?({:ok, _}, result),
                result: result
              }
            end)

          process_results
        end)
      end)

    # Collect results
    all_results = Task.await_many(tasks, 30_000) |> List.flatten()

    end_time = System.monotonic_time(:millisecond)
    total_time = end_time - start_time

    # Analyze stress test results
    successes = Enum.count(all_results, fn result -> result.success end)
    failures = length(all_results) - successes

    durations = Enum.map(all_results, fn result -> result.duration_ms end)

    %{
      test_config: %{
        concurrent_processes: concurrent_processes,
        requests_per_process: requests_per_process,
        total_requests: length(all_results)
      },
      timing: %{
        total_time_ms: total_time,
        avg_request_time_ms: Enum.sum(durations) / length(durations),
        min_request_time_ms: Enum.min(durations),
        max_request_time_ms: Enum.max(durations),
        throughput_per_sec: length(all_results) / total_time * 1000
      },
      success_rate: %{
        successes: successes,
        failures: failures,
        success_rate: successes / length(all_results) * 100
      },
      percentiles: calculate_percentiles(durations)
    }
  end

  ## Private Functions

  defp benchmark_template_with_security(template, variables, iterations) do
    successes =
      1..iterations
      |> Enum.map(fn _ ->
        case SecurityPipeline.process(template, variables) do
          {:ok, _} -> 1
          {:error, _} -> 0
        end
      end)
      |> Enum.sum()

    {time_ms, _} =
      :timer.tc(fn ->
        Enum.each(1..iterations, fn _ ->
          SecurityPipeline.process(template, variables)
        end)
      end)

    {time_ms / 1000, successes}
  end

  defp benchmark_template_without_security(template, variables, iterations) do
    successes =
      1..iterations
      |> Enum.map(fn _ ->
        case TemplateProcessor.process_template(template, variables) do
          {:ok, _} -> 1
          {:error, _} -> 0
        end
      end)
      |> Enum.sum()

    {time_ms, _} =
      :timer.tc(fn ->
        Enum.each(1..iterations, fn _ ->
          TemplateProcessor.process_template(template, variables)
        end)
      end)

    {time_ms / 1000, successes}
  end

  defp measure_with_memory(fun) do
    # Force garbage collection before measurement
    :erlang.garbage_collect()

    # Get initial memory
    initial_memory = :erlang.memory(:total)

    # Measure execution time
    {time_microseconds, _result} = :timer.tc(fun)

    # Get final memory
    final_memory = :erlang.memory(:total)

    # Calculate memory difference
    memory_diff = final_memory - initial_memory

    {time_microseconds / 1000, memory_diff}
  end

  defp calculate_aggregate_stats(results) do
    total_time = Enum.sum(Enum.map(results, & &1.total_time_ms))
    avg_time = Enum.sum(Enum.map(results, & &1.avg_time_ms)) / length(results)
    avg_success_rate = Enum.sum(Enum.map(results, & &1.success_rate)) / length(results)
    total_throughput = Enum.sum(Enum.map(results, & &1.throughput_per_sec))

    %{
      total_time_ms: total_time,
      avg_time_ms: avg_time,
      avg_success_rate: avg_success_rate,
      total_throughput_per_sec: total_throughput
    }
  end

  defp analyze_results(results) do
    security_agg = results.results.security_pipeline.aggregate
    processor_agg = results.results.template_processor_only.aggregate

    time_overhead = security_agg.avg_time_ms - processor_agg.avg_time_ms
    time_overhead_percent = time_overhead / processor_agg.avg_time_ms * 100

    throughput_reduction = processor_agg.total_throughput_per_sec - security_agg.total_throughput_per_sec
    throughput_reduction_percent = throughput_reduction / processor_agg.total_throughput_per_sec * 100

    %{
      performance_impact: %{
        time_overhead_ms: time_overhead,
        time_overhead_percent: time_overhead_percent,
        throughput_reduction_per_sec: throughput_reduction,
        throughput_reduction_percent: throughput_reduction_percent
      },
      recommendation: generate_performance_recommendation(time_overhead_percent, throughput_reduction_percent),
      acceptable_performance: time_overhead_percent < 50 and throughput_reduction_percent < 30
    }
  end

  defp generate_performance_recommendation(time_overhead_percent, throughput_reduction_percent) do
    cond do
      time_overhead_percent > 100 or throughput_reduction_percent > 50 ->
        "High performance impact detected. Consider optimizing security pipeline or reducing security level."

      time_overhead_percent > 50 or throughput_reduction_percent > 30 ->
        "Moderate performance impact. Monitor in production and consider tuning security parameters."

      time_overhead_percent > 20 or throughput_reduction_percent > 15 ->
        "Low performance impact. Acceptable for most use cases."

      true ->
        "Minimal performance impact. Security features are well-optimized."
    end
  end

  defp calculate_percentiles(durations) do
    sorted = Enum.sort(durations)
    length = length(sorted)

    %{
      p50: percentile(sorted, length, 0.5),
      p75: percentile(sorted, length, 0.75),
      p90: percentile(sorted, length, 0.9),
      p95: percentile(sorted, length, 0.95),
      p99: percentile(sorted, length, 0.99)
    }
  end

  defp percentile(sorted_list, length, percentile) do
    index = max(0, min(length - 1, round(percentile * length)))
    Enum.at(sorted_list, index)
  end

  defp default_templates do
    [
      {"simple", "Hello {{ name }}", %{"name" => "World"}},
      {"with_filters", "{{ message | upcase | trim }}", %{"message" => "  hello world  "}},
      {"conditional", "{% if show_greeting %}Hello {{ name }}{% endif %}",
       %{"show_greeting" => true, "name" => "User"}},
      {"loop", "{% for item in items %}{{ item }}{% endfor %}", %{"items" => ["a", "b", "c"]}},
      {"complex",
       "{% if user.active %}Welcome {{ user.name | capitalize }}! You have {{ user.messages | size }} messages.{% endif %}",
       %{"user" => %{"active" => true, "name" => "john", "messages" => [1, 2, 3]}}}
    ]
  end
end

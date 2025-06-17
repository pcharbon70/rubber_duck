defmodule RubberDuck.Benchmarking.BenchmarkSuite do
  @moduledoc """
  Comprehensive benchmarking suite for RubberDuck performance validation.
  
  This module provides tools for measuring and validating the performance of:
  - CodeAnalyser engines (standard vs streaming)
  - File size management and processing strategies
  - LLM provider response times
  - Caching effectiveness
  - Memory usage patterns
  - Concurrent analysis performance
  
  ## Features
  
  - Automated benchmarking with configurable parameters
  - Performance regression detection
  - Statistical analysis and reporting
  - Baseline comparison and trend analysis
  - Memory profiling and leak detection
  - Concurrent load testing
  
  ## Usage
  
      # Run standard benchmarks
      {:ok, results} = BenchmarkSuite.run_standard_benchmarks()
      
      # Run custom benchmark
      config = %{duration: 60_000, concurrent_users: 10}
      {:ok, results} = BenchmarkSuite.run_benchmark(:code_analysis, config)
      
      # Compare with baseline
      BenchmarkSuite.compare_with_baseline(results, "baseline-2024-01.json")
  """

  use GenServer
  require Logger

  alias RubberDuck.CodingAssistant.Engines.{CodeAnalyser, StreamingAnalyser}
  alias RubberDuck.CodingAssistant.FileSizeManager
  alias RubberDuck.Benchmarking.{TestDataGenerator, StatisticalAnalyzer, ReportGenerator}

  defstruct [
    :benchmark_id,
    :config,
    :test_data,
    :results,
    :start_time,
    :statistics,
    :memory_snapshots,
    :active_benchmarks
  ]

  @type benchmark_type :: :code_analysis | :streaming_analysis | :file_size_management | 
                         :llm_performance | :caching | :concurrent_load | :memory_usage

  @type benchmark_config :: %{
    duration: pos_integer(),           # Duration in milliseconds
    concurrent_users: pos_integer(),   # Number of concurrent processes
    file_sizes: [pos_integer()],      # File sizes to test (in bytes)
    languages: [atom()],              # Programming languages to test
    iterations: pos_integer(),         # Number of iterations per test
    warmup_iterations: pos_integer(),  # Warmup iterations
    memory_tracking: boolean(),        # Enable memory tracking
    baseline_comparison: boolean(),    # Compare with baseline
    save_results: boolean()           # Save results to file
  }

  @default_config %{
    duration: 30_000,
    concurrent_users: 5,
    file_sizes: [1024, 10_240, 102_400, 1_024_000, 10_240_000],  # 1KB to 10MB
    languages: [:elixir, :javascript, :python],
    iterations: 100,
    warmup_iterations: 10,
    memory_tracking: true,
    baseline_comparison: false,
    save_results: true
  }

  ## Public API

  @doc """
  Start the benchmark suite server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Run standard benchmarks covering all major components.
  """
  def run_standard_benchmarks(opts \\ []) do
    config = Map.merge(@default_config, Map.new(opts))
    
    benchmark_types = [
      :code_analysis,
      :streaming_analysis,
      :file_size_management,
      :caching,
      :memory_usage
    ]
    
    GenServer.call(__MODULE__, {:run_benchmarks, benchmark_types, config}, :infinity)
  end

  @doc """
  Run a specific benchmark type.
  """
  def run_benchmark(type, config \\ %{}) when type in [:code_analysis, :streaming_analysis, :file_size_management, :llm_performance, :caching, :concurrent_load, :memory_usage] do
    merged_config = Map.merge(@default_config, config)
    GenServer.call(__MODULE__, {:run_benchmark, type, merged_config}, :infinity)
  end

  @doc """
  Run concurrent load testing.
  """
  def run_load_test(config \\ %{}) do
    load_config = Map.merge(@default_config, Map.merge(config, %{concurrent_users: 20, duration: 60_000}))
    GenServer.call(__MODULE__, {:run_benchmark, :concurrent_load, load_config}, :infinity)
  end

  @doc """
  Compare benchmark results with baseline.
  """
  def compare_with_baseline(results, baseline_file) do
    GenServer.call(__MODULE__, {:compare_baseline, results, baseline_file})
  end

  @doc """
  Get current benchmark status.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Generate performance report.
  """
  def generate_report(results, format \\ :markdown) do
    ReportGenerator.generate(results, format)
  end

  ## GenServer Implementation

  @impl GenServer
  def init(opts) do
    config = Keyword.get(opts, :config, @default_config)
    
    state = %__MODULE__{
      benchmark_id: generate_benchmark_id(),
      config: config,
      test_data: %{},
      results: %{},
      start_time: nil,
      statistics: %{},
      memory_snapshots: [],
      active_benchmarks: %{}
    }
    
    Logger.info("BenchmarkSuite initialized with ID: #{state.benchmark_id}")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:run_benchmarks, types, config}, _from, state) do
    Logger.info("Starting benchmark suite with types: #{inspect(types)}")
    
    # Update state with new benchmark session
    new_state = %{state |
      benchmark_id: generate_benchmark_id(),
      config: config,
      start_time: System.monotonic_time(:millisecond),
      results: %{},
      memory_snapshots: []
    }
    
    # Run benchmarks sequentially
    {results, final_state} = Enum.reduce(types, {%{}, new_state}, fn type, {acc_results, acc_state} ->
      Logger.info("Running #{type} benchmark...")
      
      case execute_benchmark(type, config, acc_state) do
        {:ok, benchmark_result, updated_state} ->
          {Map.put(acc_results, type, benchmark_result), updated_state}
        {:error, reason, updated_state} ->
          Logger.error("Benchmark #{type} failed: #{inspect(reason)}")
          {Map.put(acc_results, type, %{error: reason}), updated_state}
      end
    end)
    
    # Generate summary statistics
    summary = generate_summary_statistics(results, final_state)
    final_results = Map.put(results, :summary, summary)
    
    # Save results if configured
    if config.save_results do
      save_benchmark_results(final_results, final_state)
    end
    
    Logger.info("Benchmark suite completed in #{System.monotonic_time(:millisecond) - new_state.start_time}ms")
    {:reply, {:ok, final_results}, final_state}
  end

  @impl GenServer
  def handle_call({:run_benchmark, type, config}, _from, state) do
    Logger.info("Running single benchmark: #{type}")
    
    new_state = %{state |
      config: config,
      start_time: System.monotonic_time(:millisecond)
    }
    
    case execute_benchmark(type, config, new_state) do
      {:ok, result, updated_state} ->
        {:reply, {:ok, result}, updated_state}
      {:error, reason, updated_state} ->
        {:reply, {:error, reason}, updated_state}
    end
  end

  @impl GenServer
  def handle_call({:compare_baseline, results, baseline_file}, _from, state) do
    case load_baseline_results(baseline_file) do
      {:ok, baseline} ->
        comparison = StatisticalAnalyzer.compare_results(results, baseline)
        {:reply, {:ok, comparison}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      benchmark_id: state.benchmark_id,
      active_benchmarks: map_size(state.active_benchmarks),
      start_time: state.start_time,
      memory_snapshots: length(state.memory_snapshots)
    }
    {:reply, status, state}
  end

  ## Benchmark Execution Functions

  defp execute_benchmark(:code_analysis, config, state) do
    Logger.info("Executing code analysis benchmark")
    
    # Generate test data for different file sizes and languages
    test_data = generate_code_analysis_test_data(config)
    updated_state = %{state | test_data: Map.put(state.test_data, :code_analysis, test_data)}
    
    # Warmup
    perform_warmup(:code_analysis, config, updated_state)
    
    # Run benchmark iterations
    results = run_code_analysis_iterations(test_data, config)
    
    # Analyze results
    analyzed_results = StatisticalAnalyzer.analyze_performance_data(results)
    
    {:ok, analyzed_results, updated_state}
  end

  defp execute_benchmark(:streaming_analysis, config, state) do
    Logger.info("Executing streaming analysis benchmark")
    
    # Generate large test files for streaming
    test_data = generate_streaming_test_data(config)
    updated_state = %{state | test_data: Map.put(state.test_data, :streaming_analysis, test_data)}
    
    # Warmup
    perform_warmup(:streaming_analysis, config, updated_state)
    
    # Run streaming benchmarks
    results = run_streaming_analysis_iterations(test_data, config)
    
    # Compare streaming vs standard analysis
    comparison_results = compare_streaming_vs_standard(test_data, config)
    
    final_results = Map.merge(results, %{streaming_comparison: comparison_results})
    analyzed_results = StatisticalAnalyzer.analyze_performance_data(final_results)
    
    {:ok, analyzed_results, updated_state}
  end

  defp execute_benchmark(:file_size_management, config, state) do
    Logger.info("Executing file size management benchmark")
    
    # Test FileSizeManager performance across different file sizes
    test_sizes = config.file_sizes
    
    results = benchmark_file_size_operations(test_sizes, config)
    analyzed_results = StatisticalAnalyzer.analyze_performance_data(results)
    
    {:ok, analyzed_results, state}
  end

  defp execute_benchmark(:caching, config, state) do
    Logger.info("Executing caching benchmark")
    
    # Test cache performance: hit rates, miss penalties, eviction
    cache_results = benchmark_cache_performance(config)
    analyzed_results = StatisticalAnalyzer.analyze_performance_data(cache_results)
    
    {:ok, analyzed_results, state}
  end

  defp execute_benchmark(:memory_usage, config, state) do
    Logger.info("Executing memory usage benchmark")
    
    # Profile memory usage patterns
    memory_results = benchmark_memory_usage(config, state)
    analyzed_results = StatisticalAnalyzer.analyze_memory_data(memory_results)
    
    {:ok, analyzed_results, state}
  end

  defp execute_benchmark(:concurrent_load, config, state) do
    Logger.info("Executing concurrent load benchmark")
    
    # Test system performance under concurrent load
    load_results = benchmark_concurrent_load(config)
    analyzed_results = StatisticalAnalyzer.analyze_performance_data(load_results)
    
    {:ok, analyzed_results, state}
  end

  defp execute_benchmark(:llm_performance, config, state) do
    Logger.info("Executing LLM performance benchmark")
    
    # Test LLM provider response times and throughput
    llm_results = benchmark_llm_performance(config)
    analyzed_results = StatisticalAnalyzer.analyze_performance_data(llm_results)
    
    {:ok, analyzed_results, state}
  end

  ## Test Data Generation

  defp generate_code_analysis_test_data(config) do
    Enum.flat_map(config.languages, fn language ->
      Enum.map(config.file_sizes, fn size ->
        %{
          language: language,
          size: size,
          content: TestDataGenerator.generate_code_sample(language, size),
          file_path: "/tmp/test_#{language}_#{size}.#{extension_for_language(language)}"
        }
      end)
    end)
  end

  defp generate_streaming_test_data(config) do
    # Generate larger files specifically for streaming tests
    large_sizes = [1_024_000, 5_120_000, 10_240_000, 20_480_000]  # 1MB to 20MB
    
    Enum.flat_map(config.languages, fn language ->
      Enum.map(large_sizes, fn size ->
        %{
          language: language,
          size: size,
          content: TestDataGenerator.generate_large_code_sample(language, size),
          file_path: "/tmp/streaming_test_#{language}_#{size}.#{extension_for_language(language)}"
        }
      end)
    end)
  end

  ## Benchmark Execution Functions

  defp run_code_analysis_iterations(test_data, config) do
    iterations = config.iterations
    
    results = Enum.map(test_data, fn test_case ->
      iteration_results = Enum.map(1..iterations, fn _i ->
        measure_code_analysis_performance(test_case)
      end)
      
      %{
        test_case: test_case,
        iterations: iteration_results,
        statistics: calculate_iteration_statistics(iteration_results)
      }
    end)
    
    %{
      benchmark_type: :code_analysis,
      test_results: results,
      total_iterations: iterations * length(test_data),
      timestamp: DateTime.utc_now()
    }
  end

  defp run_streaming_analysis_iterations(test_data, config) do
    iterations = config.iterations
    
    results = Enum.map(test_data, fn test_case ->
      iteration_results = Enum.map(1..iterations, fn _i ->
        measure_streaming_analysis_performance(test_case)
      end)
      
      %{
        test_case: test_case,
        iterations: iteration_results,
        statistics: calculate_iteration_statistics(iteration_results)
      }
    end)
    
    %{
      benchmark_type: :streaming_analysis,
      test_results: results,
      total_iterations: iterations * length(test_data),
      timestamp: DateTime.utc_now()
    }
  end

  defp compare_streaming_vs_standard(test_data, _config) do
    Enum.map(test_data, fn test_case ->
      # Measure standard analysis
      standard_result = measure_code_analysis_performance(test_case)
      
      # Measure streaming analysis
      streaming_result = measure_streaming_analysis_performance(test_case)
      
      # Calculate performance difference
      performance_ratio = streaming_result.duration / standard_result.duration
      memory_ratio = streaming_result.memory_used / standard_result.memory_used
      
      %{
        test_case: test_case,
        standard: standard_result,
        streaming: streaming_result,
        performance_ratio: performance_ratio,
        memory_ratio: memory_ratio,
        streaming_advantage: performance_ratio < 1.0 and memory_ratio < 1.0
      }
    end)
  end

  ## Performance Measurement Functions

  defp measure_code_analysis_performance(test_case) do
    code_data = %{
      file_path: test_case.file_path,
      content: test_case.content,
      language: test_case.language
    }
    
    # Initialize CodeAnalyser
    {:ok, engine_state} = CodeAnalyser.init(%{languages: [test_case.language]})
    
    # Measure performance
    {memory_before, _} = Process.info(self(), :memory)
    start_time = System.monotonic_time(:microsecond)
    
    result = CodeAnalyser.process_real_time(code_data, engine_state)
    
    end_time = System.monotonic_time(:microsecond)
    {memory_after, _} = Process.info(self(), :memory)
    
    duration = end_time - start_time
    memory_used = memory_after - memory_before
    
    %{
      duration: duration,
      memory_used: memory_used,
      result_status: elem(result, 0),
      file_size: test_case.size,
      language: test_case.language,
      analysis_type: :standard
    }
  end

  defp measure_streaming_analysis_performance(test_case) do
    # Initialize StreamingAnalyser
    {:ok, streaming_state} = StreamingAnalyser.init(%{
      max_file_size: 50 * 1024 * 1024,
      chunk_size: 64 * 1024
    })
    
    streaming_request = %{
      file_path: test_case.file_path,
      content: test_case.content,
      options: %{
        analysis_mode: :streaming,
        language: test_case.language
      }
    }
    
    # Measure performance
    {memory_before, _} = Process.info(self(), :memory)
    start_time = System.monotonic_time(:microsecond)
    
    result = StreamingAnalyser.analyze(streaming_request, streaming_state)
    
    end_time = System.monotonic_time(:microsecond)
    {memory_after, _} = Process.info(self(), :memory)
    
    duration = end_time - start_time
    memory_used = memory_after - memory_before
    
    %{
      duration: duration,
      memory_used: memory_used,
      result_status: elem(result, 0),
      file_size: test_case.size,
      language: test_case.language,
      analysis_type: :streaming
    }
  end

  defp benchmark_file_size_operations(test_sizes, config) do
    iterations = config.iterations
    
    results = Enum.map(test_sizes, fn size ->
      iteration_results = Enum.map(1..iterations, fn _i ->
        measure_file_size_operations(size)
      end)
      
      %{
        file_size: size,
        iterations: iteration_results,
        statistics: calculate_iteration_statistics(iteration_results)
      }
    end)
    
    %{
      benchmark_type: :file_size_management,
      test_results: results,
      timestamp: DateTime.utc_now()
    }
  end

  defp measure_file_size_operations(size) do
    start_time = System.monotonic_time(:microsecond)
    
    # Test validation
    validation_result = FileSizeManager.validate_file_size(size, %{processing_mode: :standard})
    
    # Test strategy recommendation
    strategy_result = FileSizeManager.get_processing_strategy(size, :code)
    
    # Test quota operations
    quota_result = FileSizeManager.reserve_quota(size, :analysis)
    if quota_result == :ok do
      FileSizeManager.release_quota(size, :analysis)
    end
    
    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time
    
    %{
      duration: duration,
      file_size: size,
      validation_status: validation_result,
      strategy_type: strategy_result.type,
      quota_status: quota_result
    }
  end

  defp benchmark_cache_performance(config) do
    # Test cache hit rates, miss penalties, etc.
    # This would integrate with the CodeAnalyser cache
    iterations = config.iterations
    
    # Generate test data that will exercise cache
    test_content = TestDataGenerator.generate_code_sample(:elixir, 10240)  # 10KB
    
    cache_results = Enum.map(1..iterations, fn i ->
      measure_cache_performance(test_content, i)
    end)
    
    %{
      benchmark_type: :caching,
      test_results: cache_results,
      cache_statistics: calculate_cache_statistics(cache_results),
      timestamp: DateTime.utc_now()
    }
  end

  defp measure_cache_performance(content, iteration) do
    code_data = %{
      file_path: "/tmp/cache_test.ex",
      content: content,
      language: :elixir
    }
    
    {:ok, engine_state} = CodeAnalyser.init(%{languages: [:elixir]})
    
    start_time = System.monotonic_time(:microsecond)
    {:ok, _result, _new_state} = CodeAnalyser.process_real_time(code_data, engine_state)
    end_time = System.monotonic_time(:microsecond)
    
    %{
      iteration: iteration,
      duration: end_time - start_time,
      cache_key: "elixir:#{:crypto.hash(:md5, content) |> Base.encode16(case: :lower)}"
    }
  end

  defp benchmark_memory_usage(config, _state) do
    # Profile memory usage over time
    initial_memory = get_process_memory()
    memory_snapshots = [%{time: 0, memory: initial_memory, phase: :initial}]
    
    # Run various operations and track memory
    test_data = generate_code_analysis_test_data(config)
    
    snapshots_with_operations = Enum.reduce(test_data, memory_snapshots, fn test_case, acc_snapshots ->
      before_memory = get_process_memory()
      _result = measure_code_analysis_performance(test_case)
      after_memory = get_process_memory()
      
      [
        %{time: length(acc_snapshots), memory: after_memory, phase: :after_analysis, 
          test_case: test_case, memory_delta: after_memory - before_memory} | acc_snapshots
      ]
    end)
    
    # Force garbage collection and measure
    :erlang.garbage_collect()
    final_memory = get_process_memory()
    final_snapshots = [%{time: length(snapshots_with_operations), memory: final_memory, phase: :after_gc} | snapshots_with_operations]
    
    %{
      benchmark_type: :memory_usage,
      memory_snapshots: Enum.reverse(final_snapshots),
      memory_statistics: calculate_memory_statistics(final_snapshots),
      timestamp: DateTime.utc_now()
    }
  end

  defp benchmark_concurrent_load(config) do
    concurrent_users = config.concurrent_users
    duration = config.duration
    
    Logger.info("Starting concurrent load test with #{concurrent_users} users for #{duration}ms")
    
    # Generate test data
    test_data = generate_code_analysis_test_data(config)
    
    # Start concurrent processes
    start_time = System.monotonic_time(:millisecond)
    
    tasks = Enum.map(1..concurrent_users, fn user_id ->
      Task.async(fn ->
        run_concurrent_user_simulation(user_id, test_data, duration, start_time)
      end)
    end)
    
    # Wait for all tasks to complete
    results = Task.await_many(tasks, duration + 10_000)
    
    # Aggregate results
    %{
      benchmark_type: :concurrent_load,
      concurrent_users: concurrent_users,
      duration: duration,
      user_results: results,
      aggregate_statistics: calculate_concurrent_statistics(results),
      timestamp: DateTime.utc_now()
    }
  end

  defp benchmark_llm_performance(_config) do
    # This would benchmark LLM provider response times
    # For now, return a placeholder
    %{
      benchmark_type: :llm_performance,
      note: "LLM performance benchmarking requires active provider connections",
      timestamp: DateTime.utc_now()
    }
  end

  ## Helper Functions

  defp perform_warmup(benchmark_type, config, state) do
    Logger.info("Performing warmup for #{benchmark_type}")
    
    case benchmark_type do
      :code_analysis ->
        test_data = Map.get(state.test_data, :code_analysis, [])
        Enum.take(test_data, config.warmup_iterations)
        |> Enum.each(&measure_code_analysis_performance/1)
      
      :streaming_analysis ->
        test_data = Map.get(state.test_data, :streaming_analysis, [])
        Enum.take(test_data, config.warmup_iterations)
        |> Enum.each(&measure_streaming_analysis_performance/1)
      
      _ ->
        :ok
    end
    
    # Force garbage collection after warmup
    :erlang.garbage_collect()
  end

  defp run_concurrent_user_simulation(user_id, test_data, duration, start_time) do
    end_time = start_time + duration
    results = []
    
    simulate_user_load(user_id, test_data, end_time, results, 0)
  end

  defp simulate_user_load(user_id, test_data, end_time, results, iteration_count) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time < end_time do
      # Pick random test case
      test_case = Enum.random(test_data)
      
      # Measure performance
      result = measure_code_analysis_performance(test_case)
      updated_results = [Map.put(result, :user_id, user_id) | results]
      
      # Small delay to simulate realistic usage
      :timer.sleep(Enum.random(10..100))
      
      simulate_user_load(user_id, test_data, end_time, updated_results, iteration_count + 1)
    else
      %{
        user_id: user_id,
        total_iterations: iteration_count,
        results: results,
        statistics: calculate_iteration_statistics(results)
      }
    end
  end

  ## Statistical Analysis Helpers

  defp calculate_iteration_statistics(results) do
    durations = Enum.map(results, & &1.duration)
    memory_usage = Enum.map(results, & &1.memory_used)
    
    %{
      count: length(results),
      avg_duration: Enum.sum(durations) / length(durations),
      min_duration: Enum.min(durations),
      max_duration: Enum.max(durations),
      avg_memory: Enum.sum(memory_usage) / length(memory_usage),
      min_memory: Enum.min(memory_usage),
      max_memory: Enum.max(memory_usage),
      percentiles: calculate_percentiles(durations)
    }
  end

  defp calculate_cache_statistics(cache_results) do
    durations = Enum.map(cache_results, & &1.duration)
    first_run = List.first(durations)
    subsequent_runs = Enum.drop(durations, 1)
    
    %{
      first_run_duration: first_run,
      avg_subsequent_duration: if(length(subsequent_runs) > 0, do: Enum.sum(subsequent_runs) / length(subsequent_runs), else: 0),
      cache_speedup: if(length(subsequent_runs) > 0, do: first_run / (Enum.sum(subsequent_runs) / length(subsequent_runs)), else: 1.0),
      total_runs: length(cache_results)
    }
  end

  defp calculate_memory_statistics(snapshots) do
    memories = Enum.map(snapshots, & &1.memory)
    
    %{
      initial_memory: List.first(memories),
      final_memory: List.last(memories),
      peak_memory: Enum.max(memories),
      min_memory: Enum.min(memories),
      memory_growth: List.last(memories) - List.first(memories),
      avg_memory: Enum.sum(memories) / length(memories)
    }
  end

  defp calculate_concurrent_statistics(user_results) do
    all_durations = user_results
    |> Enum.flat_map(fn user -> Enum.map(user.results, & &1.duration) end)
    
    total_operations = Enum.sum(Enum.map(user_results, & &1.total_iterations))
    
    %{
      total_operations: total_operations,
      avg_operations_per_user: total_operations / length(user_results),
      overall_avg_duration: Enum.sum(all_durations) / length(all_durations),
      overall_min_duration: Enum.min(all_durations),
      overall_max_duration: Enum.max(all_durations),
      percentiles: calculate_percentiles(all_durations)
    }
  end

  defp calculate_percentiles(values) when length(values) > 0 do
    sorted = Enum.sort(values)
    count = length(sorted)
    
    %{
      p50: Enum.at(sorted, round(count * 0.50) - 1),
      p90: Enum.at(sorted, round(count * 0.90) - 1),
      p95: Enum.at(sorted, round(count * 0.95) - 1),
      p99: Enum.at(sorted, round(count * 0.99) - 1)
    }
  end
  defp calculate_percentiles(_), do: %{p50: 0, p90: 0, p95: 0, p99: 0}

  ## Utility Functions

  defp generate_benchmark_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "benchmark_#{timestamp}_#{random}"
  end

  defp extension_for_language(:elixir), do: "ex"
  defp extension_for_language(:javascript), do: "js"
  defp extension_for_language(:python), do: "py"
  defp extension_for_language(:erlang), do: "erl"
  defp extension_for_language(_), do: "txt"

  defp get_process_memory do
    {memory, _} = Process.info(self(), :memory)
    memory
  end

  defp generate_summary_statistics(results, state) do
    total_duration = System.monotonic_time(:millisecond) - state.start_time
    
    %{
      total_duration: total_duration,
      benchmarks_run: map_size(results) - 1,  # Exclude summary itself
      timestamp: DateTime.utc_now(),
      benchmark_id: state.benchmark_id,
      system_info: get_system_info()
    }
  end

  defp get_system_info do
    %{
      elixir_version: System.version(),
      otp_version: System.otp_release(),
      schedulers: System.schedulers(),
      schedulers_online: System.schedulers_online(),
      memory_total: :erlang.memory(:total),
      memory_processes: :erlang.memory(:processes)
    }
  end

  defp save_benchmark_results(results, state) do
    filename = "benchmark_results_#{state.benchmark_id}.json"
    filepath = Path.join(["benchmarks", "results", filename])
    
    # Ensure directory exists
    Path.dirname(filepath) |> File.mkdir_p!()
    
    case Jason.encode(results, pretty: true) do
      {:ok, json} ->
        case File.write(filepath, json) do
          :ok ->
            Logger.info("Benchmark results saved to #{filepath}")
          {:error, reason} ->
            Logger.error("Failed to save benchmark results: #{reason}")
        end
      {:error, reason} ->
        Logger.error("Failed to encode benchmark results: #{reason}")
    end
  end

  defp load_baseline_results(baseline_file) do
    case File.read(baseline_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end
      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end
end